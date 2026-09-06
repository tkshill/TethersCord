// worker/src/GameTable.ts

import type {
  DurableObject,
  DurableObjectState,
} from "@cloudflare/workers-types";
import type {
  AbilityKind,
  AspectName,
  CommitBoonInput,
  CommittedBoon,
  EntityInput,
  EntityKind,
  Env,
  FloatingBoon,
  GameState,
  Message,
  Overcome,
  PendingRoll,
  PostMessageInput,
  Proposal,
  ProposalDecisionInput,
  Role,
  SessionState,
  SessionSummary,
  StartOvercomeInput,
  StartSessionInput,
  StoneKind,
  TableEntity,
  CharacterSheet,
  Untether,
  UpdateCharacterInput,
  UpdateFateInput,
  UpdateSessionGoalInput,
  UsedAbilities,
  UseAbilityInput,
  UseFloatingBoonInput,
} from "./types";

// Every roll starts from this base — two Boon, two Bane — before any boons a
// character pledges into it. Accepting a roll resets the pool to this.
const INITIAL_STONE_POOL: readonly StoneKind[] = ["Boon", "Bane", "Boon", "Bane"];

const CHARACTER_SLOT_COUNT = 3;

/** Boons the overcome target spends to Reroll while an overcome is open. */
const REROLL_COST = 2;

/** Boons the facilitator pays out for an approved Accept Compel move. */
const ACCEPT_COMPEL_BOONS = 2;

/** Boons an approved Suggest Compel pays: the suggester, then the compelled character. */
const SUGGEST_COMPEL_SUGGESTER_BOONS = 1;
const SUGGEST_COMPEL_TARGET_BOONS = 2;

/** The once-per-session abilities, for validation of the `/abilities/use` route. */
const ABILITY_KINDS: readonly AbilityKind[] = [
  "help-out",
  "add-detail",
  "gain-insight",
  "suggest-compel",
];

/** The three fixed aspects, and the D1 column each Bane count lives in. */
const ASPECT_NAMES: readonly AspectName[] = ["archetype", "desire", "quest"];
const ASPECT_BANE_COLUMNS: Record<AspectName, string> = {
  archetype: "archetype_banes",
  desire: "desire_banes",
  quest: "quest_banes",
};

/** Sanity bound on a single coalesced pledge delta; `applyPledge` clamps the
 * real effect to what the character holds anyway. */
const MAX_PLEDGE_DELTA = 50;

/**
 * How many of the most recent messages the Durable Object holds in memory and
 * carries in every snapshot / broadcast. Kept small so the connect payload and
 * each re-render stay cheap; older history is pulled on demand through
 * `GET /messages/history`.
 */
const MESSAGE_WINDOW = 50;

const MAX_MESSAGE_LENGTH = 2000;
const MAX_FIELD_LENGTH = 500;
const MAX_NOTES_LENGTH = 4000;
const MAX_GOAL_LENGTH = 500;

/** A session's pool starts here, then grows one stone per accepted roll. */
const INITIAL_SESSION_POOL: readonly StoneKind[] = [
  "Boon",
  "Bane",
  "Boon",
  "Bane",
];

/** Durable Object storage keys. */
const KEY_SESSION_ID = "sessionId";
const KEY_STONES = "stones";

/**
 * How long a resolved token → `AuthInfo` is trusted from memory before the
 * `sessions_auth` ⋈ `facilitators` query runs again. Bounds how stale a role
 * change (or an expiry that lands mid-window) can be to this many milliseconds,
 * in exchange for one D1 read per token per minute instead of per request.
 */
const AUTH_CACHE_TTL_MS = 60_000;

type StoneState = {
  stonePool: StoneKind[];
  pendingRoll: PendingRoll | null;
  overcome: Overcome | null;
  committedBoons: CommittedBoon[];
  floatingBoons: FloatingBoon[];
  usedAbilities: UsedAbilities[];
  proposals: Proposal[];
  session: SessionState | null;
  /** Banes the next session's pool inherits (section 19). Boons never carry. */
  carriedBanes: number;
  /** Whether the most recently ended session failed its goal — blocks a second
   * consecutive untether. */
  lastSessionFailed: boolean;
  /** An in-progress reckoning, or null. */
  untether: Untether | null;
};

/** Shape of `KEY_STONES` as written by builds that still used colour names. */
type LegacyStoneKind = StoneKind | "WhiteStone" | "BlackStone";
type LegacyStoneState = {
  stonePool: LegacyStoneKind[];
  pendingRoll: {
    chosen: LegacyStoneKind[];
    rest: LegacyStoneKind[];
  } | null;
  overcome?: Overcome | null;
  committedBoons?: CommittedBoon[];
  floatingBoons?: FloatingBoon[];
  usedAbilities?: UsedAbilities[];
  proposals?: Proposal[];
  session?: (Omit<SessionState, "carriedBanes"> & { carriedBanes?: number }) | null;
  carriedBanes?: number;
  lastSessionFailed?: boolean;
  untether?: Untether | null;
};

function migrateStoneKind(kind: LegacyStoneKind): StoneKind {
  if (kind === "WhiteStone") return "Boon";
  if (kind === "BlackStone") return "Bane";
  return kind;
}

export class GameTable implements DurableObject {
  private state: DurableObjectState;
  private env: Env;
  private gameState: GameState | null = null;

  /**
   * Single-flighted initialization. A plain `if (!this.gameState)` check lets two
   * concurrent cold requests both run the character bootstrap and collide on the
   * `(session_id, slot)` unique index, so the promise is memoized instead.
   *
   * It resolves the session id this object is bound to, and installs the loaded
   * snapshot into `this.gameState` as a side effect. It deliberately does NOT
   * resolve the `GameState`: being memoized, it would resolve the cold-start
   * snapshot forever, and assigning that back to `this.gameState` on each
   * request would discard every mutation made since startup.
   */
  private initPromise: Promise<string> | null = null;

  /**
   * Durable Objects interleave concurrent requests at `await` points, so two
   * mutating requests can both read `gameState` before either has written its
   * result back, and the second write clobbers the first (lost update). This
   * chain forces every mutation to run to completion — DB write, in-memory
   * update, and broadcast — before the next one starts.
   */
  private mutationLock: Promise<unknown> = Promise.resolve();

  /**
   * token → resolved `AuthInfo`, memoised for `AUTH_CACHE_TTL_MS`. Only positive
   * results are cached; an unknown or expired token always hits D1 so a freshly
   * minted session is picked up at once. Lives in DO memory, so it is dropped on
   * hibernation — which is fine, the next request just repopulates it.
   */
  private authCache = new Map<string, { info: AuthInfo; expiresAt: number }>();

  constructor(state: DurableObjectState, env: Env) {
    this.state = state;
    this.env = env;
  }

  private async resolveAuthToken(token: string): Promise<AuthInfo | null> {
    const cached = this.authCache.get(token);
    if (cached && cached.expiresAt > Date.now()) {
      return cached.info;
    }

    const info = await getAuthFromToken(this.env, token);
    if (info) {
      this.authCache.set(token, {
        info,
        expiresAt: Date.now() + AUTH_CACHE_TTL_MS,
      });
    } else {
      this.authCache.delete(token);
    }
    return info;
  }

  private async authFromRequest(request: Request): Promise<AuthInfo | null> {
    const authHeader = request.headers.get("Authorization");
    if (!authHeader?.startsWith("Bearer ")) {
      return null;
    }
    const token = authHeader.slice("Bearer ".length).trim();
    if (!token) return null;
    return this.resolveAuthToken(token);
  }

  private withLock<T>(fn: () => Promise<T>): Promise<T> {
    const result = this.mutationLock.then(fn, fn);
    this.mutationLock = result.then(
      () => undefined,
      () => undefined,
    );
    return result;
  }

  async fetch(request: Request): Promise<Response> {
    const url = new URL(request.url);

    // `tableId` is stamped onto the URL by the Worker from the request path and
    // overwrites anything the client sent, so it cannot be used to point this
    // Durable Object at another table's rows.
    const sessionId = url.searchParams.get("tableId");
    if (!sessionId) {
      return new Response("Missing table id", { status: 400 });
    }

    // Only ever *load* here. Assigning `this.gameState` from the memoized
    // promise would restore the cold-start snapshot on every request and throw
    // away everything written since — and it would do so ahead of `withLock`,
    // where no handler can defend against it.
    const boundSessionId = await this.ensureLoaded(sessionId);
    if (boundSessionId !== sessionId) {
      return new Response("Table id mismatch", { status: 400 });
    }

    if (url.pathname === "/connect") {
      if (request.headers.get("Upgrade") !== "websocket") {
        return new Response("Expected Upgrade: websocket", { status: 426 });
      }
      return this.handleConnect(request);
    }

    // Every route below this point requires a valid session.
    const authInfo = await this.authFromRequest(request);
    if (!authInfo) {
      return new Response("Unauthorized", { status: 401 });
    }

    if (url.pathname === "/messages" && request.method === "GET") {
      return jsonResponse(this.gameState);
    }

    if (url.pathname === "/messages/history" && request.method === "GET") {
      return this.handleMessageHistory(sessionId, url);
    }

    if (url.pathname === "/message" && request.method === "POST") {
      return this.withLock(() => this.handlePostMessage(request, authInfo));
    }

    if (url.pathname === "/messages/clear" && request.method === "POST") {
      return (
        facilitatorOnly(authInfo) ??
        this.withLock(() => this.handleClearMessages())
      );
    }

    if (url.pathname === "/stones/add-boon" && request.method === "POST") {
      return this.withLock(() =>
        authInfo.role === "facilitator"
          ? this.applyAddBoon()
          : this.proposeAddBoon(authInfo),
      );
    }

    if (url.pathname === "/stones/commit" && request.method === "POST") {
      return this.withLock(() => this.handleCommitBoon(request, authInfo));
    }

    const proposalMatch = url.pathname.match(
      /^\/proposals\/([0-9a-fA-F-]{36})\/(accept|reject|withdraw)$/,
    );
    if (proposalMatch && request.method === "POST") {
      const [, proposalId, action] = proposalMatch;
      // A proposer withdraws their own; the facilitator accepts or rejects
      // anyone's.
      if (action === "withdraw") {
        return this.withLock(() =>
          this.handleWithdrawProposal(proposalId, authInfo),
        );
      }
      return (
        facilitatorOnly(authInfo) ??
        this.withLock(() =>
          this.handleProposalDecision(
            proposalId,
            action as "accept" | "reject",
            authInfo,
            request,
          ),
        )
      );
    }

    if (url.pathname === "/abilities/use" && request.method === "POST") {
      return this.withLock(() => this.handleUseAbility(request, authInfo));
    }

    if (url.pathname === "/moves/accept-compel" && request.method === "POST") {
      return this.withLock(() => this.handleAcceptCompelMove(authInfo));
    }

    if (url.pathname === "/stones/use-floating" && request.method === "POST") {
      return this.withLock(() => this.handleUseFloating(request, authInfo));
    }

    if (url.pathname === "/stones/roll" && request.method === "POST") {
      return (
        this.rollGate(authInfo) ??
        this.withLock(() => this.handleRoll(authInfo, "Rolled"))
      );
    }

    if (url.pathname === "/stones/reroll" && request.method === "POST") {
      return (
        this.rollGate(authInfo) ??
        this.withLock(() => this.handleRoll(authInfo, "Rerolled"))
      );
    }

    if (url.pathname === "/stones/accept" && request.method === "POST") {
      return (
        facilitatorOnly(authInfo) ??
        this.withLock(() => this.handleAcceptRoll(authInfo))
      );
    }

    if (url.pathname === "/overcome/start" && request.method === "POST") {
      return (
        facilitatorOnly(authInfo) ??
        this.withLock(() => this.handleStartOvercome(request, authInfo))
      );
    }

    if (url.pathname === "/overcome/cancel" && request.method === "POST") {
      return (
        facilitatorOnly(authInfo) ??
        this.withLock(() => this.handleCancelOvercome(authInfo))
      );
    }

    if (url.pathname === "/session/start" && request.method === "POST") {
      return (
        facilitatorOnly(authInfo) ??
        this.withLock(() => this.handleStartSession(request, authInfo))
      );
    }

    if (url.pathname === "/session/end" && request.method === "POST") {
      return (
        facilitatorOnly(authInfo) ??
        this.withLock(() => this.handleEndSession(authInfo))
      );
    }

    if (url.pathname === "/session/goal" && request.method === "POST") {
      return (
        facilitatorOnly(authInfo) ??
        this.withLock(() => this.handleUpdateSessionGoal(request, authInfo))
      );
    }

    if (url.pathname === "/untether/resolve" && request.method === "POST") {
      return (
        facilitatorOnly(authInfo) ??
        this.withLock(() => this.handleResolveUntether(authInfo))
      );
    }

    const charUpdateMatch = url.pathname.match(/^\/characters\/(\d+)\/update$/);
    if (charUpdateMatch && request.method === "POST") {
      return this.withLock(() =>
        this.handleUpdateCharacter(
          request,
          Number(charUpdateMatch[1]),
          authInfo,
        ),
      );
    }

    const charClaimMatch = url.pathname.match(/^\/characters\/(\d+)\/claim$/);
    if (charClaimMatch && request.method === "POST") {
      return this.withLock(() =>
        this.handleClaimSlot(Number(charClaimMatch[1]), authInfo),
      );
    }

    const charReleaseMatch = url.pathname.match(
      /^\/characters\/(\d+)\/release$/,
    );
    if (charReleaseMatch && request.method === "POST") {
      return this.withLock(() =>
        this.handleReleaseSlot(Number(charReleaseMatch[1]), authInfo),
      );
    }

    const charFateMatch = url.pathname.match(/^\/characters\/(\d+)\/fate$/);
    if (charFateMatch && request.method === "POST") {
      return (
        facilitatorOnly(authInfo) ??
        this.withLock(() =>
          this.handleUpdateFate(request, Number(charFateMatch[1])),
        )
      );
    }

    // Facilitator-owned reference data: NPCs and locations. Create at
    // `/npcs` | `/locations`, then `/{id}/update` and `/{id}/delete`.
    const entityCreateMatch = url.pathname.match(/^\/(npcs|locations)$/);
    if (entityCreateMatch && request.method === "POST") {
      const kind = entityCreateMatch[1] as EntityKind;
      return (
        facilitatorOnly(authInfo) ??
        this.withLock(() => this.handleCreateEntity(request, kind))
      );
    }

    const entityMatch = url.pathname.match(
      /^\/(npcs|locations)\/([0-9a-fA-F-]{36})\/(update|delete)$/,
    );
    if (entityMatch && request.method === "POST") {
      const kind = entityMatch[1] as EntityKind;
      const [, , entityId, action] = entityMatch;
      return (
        facilitatorOnly(authInfo) ??
        this.withLock(() =>
          action === "update"
            ? this.handleUpdateEntity(request, kind, entityId)
            : this.handleDeleteEntity(kind, entityId),
        )
      );
    }

    return new Response("Not found", { status: 404 });
  }

  private async handleConnect(request: Request): Promise<Response> {
    const token = parseTokenFromProtocol(
      request.headers.get("Sec-WebSocket-Protocol"),
    );
    const authInfo = token ? await this.resolveAuthToken(token) : null;
    if (!authInfo) {
      return new Response("Unauthorized", { status: 401 });
    }

    const pair = new WebSocketPair();
    const [client, server] = Object.values(pair);

    // Hibernatable: the DO can evict from memory between messages and still
    // resume delivering broadcasts to this socket later.
    this.state.acceptWebSocket(server);

    // Never `await` between accepting the socket and sending this snapshot.
    // Registering first means a concurrent mutation's broadcast can only arrive
    // *after* the snapshot; an await here would invert that and leave the new
    // client holding state older than a push it already received.
    server.send(JSON.stringify(this.gameState));

    return new Response(null, {
      status: 101,
      webSocket: client,
      headers: { "Sec-WebSocket-Protocol": "bearer" },
    });
  }

  async webSocketMessage(): Promise<void> {
    // Clients only receive broadcasts; no inbound messages are expected.
  }

  async webSocketClose(): Promise<void> {
    // `web_socket_auto_reply_to_close` (on by default from compatibility date
    // 2026-04-07) completes the closing handshake for us. Echoing the code back
    // with `ws.close(code)` throws on 1005/1006, which the runtime synthesizes
    // for every unclean disconnect.
  }

  async webSocketError(ws: WebSocket): Promise<void> {
    try {
      ws.close(1011, "error");
    } catch {
      // Already closed.
    }
  }

  private broadcast(state: GameState): void {
    const payload = JSON.stringify(state);
    for (const ws of this.state.getWebSockets()) {
      try {
        ws.send(payload);
      } catch {
        // Ignore sends to sockets that are closing; webSocketClose will clean up.
      }
    }
  }

  private ensureLoaded(sessionId: string): Promise<string> {
    if (!this.initPromise) {
      this.initPromise = this.loadInitialState(sessionId).catch((error) => {
        // Let the next request retry rather than caching a rejected promise.
        this.initPromise = null;
        throw error;
      });
    }
    return this.initPromise;
  }

  /** Populates `this.gameState` and returns the session id this object is bound to. */
  private async loadInitialState(sessionId: string): Promise<string> {
    // The first request to reach a fresh Durable Object fixes its session id.
    // Later requests carrying a different one are a routing bug, not a rename.
    const storedSessionId =
      await this.state.storage.get<string>(KEY_SESSION_ID);
    if (storedSessionId === undefined) {
      await this.state.storage.put(KEY_SESSION_ID, sessionId);
    } else if (storedSessionId !== sessionId) {
      throw new Error(
        `Durable Object is bound to session ${storedSessionId}, refusing ${sessionId}`,
      );
    }

    const rows = await this.env.DB.prepare(
      `
      SELECT id, session_id AS sessionId, author_id AS authorId,
             author_name AS authorName, role, content, created_at AS createdAt
      FROM messages
      WHERE session_id = ?
      ORDER BY created_at DESC, id DESC
      LIMIT ?
    `,
    )
      .bind(sessionId, MESSAGE_WINDOW)
      .all<Message>();

    const messages = rows.results ? [...rows.results].reverse() : [];
    const characters = await this.loadOrCreateCharacters(sessionId);
    const stones = await this.loadStoneState();
    this.carriedBanes = stones.carriedBanes;
    this.lastSessionFailed = stones.lastSessionFailed;
    const sessionHistory = await this.loadSessionHistory(sessionId);
    const npcs = await this.loadEntities(sessionId, "npcs");
    const locations = await this.loadEntities(sessionId, "locations");

    this.gameState = {
      sessionId,
      messages,
      stonePool: stones.stonePool,
      pendingRoll: stones.pendingRoll,
      overcome: stones.overcome,
      committedBoons: stones.committedBoons,
      floatingBoons: stones.floatingBoons,
      usedAbilities: stones.usedAbilities,
      proposals: stones.proposals,
      session: stones.session,
      sessionHistory,
      characters,
      npcs,
      locations,
      untether: stones.untether,
    };

    // Seed the write-skip baseline so an unchanged stone slice is not
    // re-persisted on the first mutation after a cold start.
    this.lastSavedStones = JSON.stringify(this.stoneSlice(this.gameState));

    // Equal to `storedSessionId` by the guard above; every later request in this
    // object's lifetime compares against it instead of re-reading storage.
    return sessionId;
  }

  /**
   * The stone pool and pending roll are the only state this Durable Object
   * genuinely owns, so they live in its own storage. Keeping them in memory
   * loses them every time the DO hibernates, which is roughly ten seconds
   * after a table goes quiet.
   */
  private async loadStoneState(): Promise<StoneState> {
    const stored = await this.state.storage.get<LegacyStoneState>(KEY_STONES);
    if (stored) {
      // Fold the colour-named stones of earlier builds into Boon / Bane.
      return {
        stonePool: stored.stonePool.map(migrateStoneKind),
        pendingRoll: stored.pendingRoll
          ? {
              chosen: stored.pendingRoll.chosen.map(migrateStoneKind),
              rest: stored.pendingRoll.rest.map(migrateStoneKind),
            }
          : null,
        overcome: stored.overcome ?? null,
        committedBoons: stored.committedBoons ?? [],
        floatingBoons: stored.floatingBoons ?? [],
        usedAbilities: stored.usedAbilities ?? [],
        // Proposals from before the moves work carry no `floatingId` /
        // `targetSlot`.
        proposals: (stored.proposals ?? []).map((p) => ({
          ...p,
          floatingId: p.floatingId ?? null,
          targetSlot: p.targetSlot ?? null,
        })),
        // Sessions from before section 19 carry no `carriedBanes`.
        session: stored.session
          ? { ...stored.session, carriedBanes: stored.session.carriedBanes ?? 0 }
          : null,
        carriedBanes: stored.carriedBanes ?? 0,
        lastSessionFailed: stored.lastSessionFailed ?? false,
        untether: stored.untether ?? null,
      };
    }

    const initial: StoneState = {
      stonePool: [...INITIAL_STONE_POOL],
      pendingRoll: null,
      overcome: null,
      committedBoons: [],
      floatingBoons: [],
      usedAbilities: [],
      proposals: [],
      session: null,
      carriedBanes: 0,
      lastSessionFailed: false,
      untether: null,
    };
    await this.state.storage.put(KEY_STONES, initial);
    return initial;
  }

  /**
   * The serialised `StoneState` as last written to storage. `saveStoneState`
   * compares against this and skips the `put` when nothing in the stone slice
   * actually changed — a plain chat post, for instance, runs through the same
   * mutation path but touches none of it.
   */
  private lastSavedStones: string | null = null;

  /**
   * Banes the next session's pool inherits (section 19), and whether the last
   * ended session failed its goal. These are DO-owned but not broadcast, so they
   * live on the instance rather than in `GameState`; `stoneSlice` folds them in.
   */
  private carriedBanes = 0;
  private lastSessionFailed = false;

  private stoneSlice(state: GameState): StoneState {
    return {
      stonePool: state.stonePool,
      pendingRoll: state.pendingRoll,
      overcome: state.overcome,
      committedBoons: state.committedBoons,
      floatingBoons: state.floatingBoons,
      usedAbilities: state.usedAbilities,
      proposals: state.proposals,
      session: state.session,
      carriedBanes: this.carriedBanes,
      lastSessionFailed: this.lastSessionFailed,
      untether: state.untether,
    };
  }

  private async saveStoneState(state: GameState): Promise<void> {
    const slice = this.stoneSlice(state);

    const serialised = JSON.stringify(slice);
    if (serialised === this.lastSavedStones) {
      return;
    }

    await this.state.storage.put(KEY_STONES, slice);
    this.lastSavedStones = serialised;
  }

  /**
   * The most recent completed sessions for this table, newest first, read
   * straight from D1. The running session is excluded (`ended_at IS NULL`); it
   * is already carried in `gameState.session`. Refreshed on `/session/end`
   * rather than kept live, since that is the only event that adds a row here.
   */
  private async loadSessionHistory(
    sessionId: string,
  ): Promise<SessionSummary[]> {
    const rows = await this.env.DB.prepare(
      `
      SELECT id, goal, started_at AS startedAt, ended_at AS endedAt, outcome
      FROM game_sessions
      WHERE session_id = ? AND ended_at IS NOT NULL
      ORDER BY started_at DESC
      LIMIT 20
    `,
    )
      .bind(sessionId)
      .all<SessionSummary>();

    return rows.results ?? [];
  }

  /**
   * The facilitator's reference rows for this table — NPCs or locations —
   * oldest first, read straight from D1 on cold start. Kept live in
   * `gameState` thereafter; every mutation goes through `withLock`.
   */
  private async loadEntities(
    sessionId: string,
    kind: EntityKind,
  ): Promise<TableEntity[]> {
    const rows = await this.env.DB.prepare(
      `
      SELECT id, name, notes, created_at AS createdAt, updated_at AS updatedAt
      FROM ${entityTable(kind)}
      WHERE session_id = ?
      ORDER BY created_at, id
    `,
    )
      .bind(sessionId)
      .all<TableEntity>();

    return rows.results ?? [];
  }

  private async loadOrCreateCharacters(
    sessionId: string,
  ): Promise<CharacterSheet[]> {
    const rows = await this.env.DB.prepare(
      `
      SELECT id, slot, name, notable_features, archetype, desire, quest, condition,
             notes, fate, discord_user_id,
             archetype_banes, desire_banes, quest_banes
      FROM characters
      WHERE session_id = ?
      ORDER BY slot
    `,
    )
      .bind(sessionId)
      .all<CharacterRow>();

    const bySlot = new Map((rows.results ?? []).map((row) => [row.slot, row]));

    for (let slot = 0; slot < CHARACTER_SLOT_COUNT; slot++) {
      if (bySlot.has(slot)) continue;

      const id = crypto.randomUUID();
      await this.env.DB.prepare(
        `
        INSERT INTO characters (id, session_id, slot, updated_at)
        VALUES (?, ?, ?, ?)
      `,
      )
        .bind(id, sessionId, slot, Date.now())
        .run();

      bySlot.set(slot, {
        id,
        slot,
        name: "",
        notable_features: "",
        archetype: "",
        desire: "",
        quest: "",
        condition: "",
        notes: "",
        fate: 0,
        discord_user_id: null,
        archetype_banes: 0,
        desire_banes: 0,
        quest_banes: 0,
      });
    }

    return Array.from(bySlot.values())
      .sort((a, b) => a.slot - b.slot)
      .map(rowToCharacterSheet);
  }

  private async handlePostMessage(
    request: Request,
    authInfo: AuthInfo,
  ): Promise<Response> {
    const input = (await readJson(request)) as PostMessageInput | null;
    const content = boundedString(input?.content, MAX_MESSAGE_LENGTH);
    if (!content.trim()) {
      return new Response("Message content is required", { status: 400 });
    }

    await this.appendMessage({
      authorId: authInfo.discordUserId,
      authorName: authInfo.username,
      role: authInfo.role,
      content,
    });

    this.broadcast(this.gameState!);
    return ackResponse();
  }

  /**
   * Older history for the "load earlier" affordance. The snapshot only carries
   * the last `MESSAGE_WINDOW` messages; this returns the page of up to
   * `MESSAGE_WINDOW` rows immediately before `?before=<createdAt>`, oldest first.
   * Read-only: no lock, no broadcast, does not touch `this.gameState`.
   */
  private async handleMessageHistory(
    sessionId: string,
    url: URL,
  ): Promise<Response> {
    const rawBefore = url.searchParams.get("before");
    const before = Number(rawBefore);
    if (!rawBefore || !Number.isFinite(before) || before <= 0) {
      return new Response("before must be a positive timestamp", { status: 400 });
    }

    const rows = await this.env.DB.prepare(
      `
      SELECT id, session_id AS sessionId, author_id AS authorId,
             author_name AS authorName, role, content, created_at AS createdAt
      FROM messages
      WHERE session_id = ? AND created_at < ?
      ORDER BY created_at DESC, id DESC
      LIMIT ?
    `,
    )
      .bind(sessionId, before, MESSAGE_WINDOW)
      .all<Message>();

    const messages = rows.results ? [...rows.results].reverse() : [];
    return jsonResponse({ messages });
  }

  /**
   * Wipe this table's log: delete the D1 rows and drop the in-memory copy. The
   * supported alternative to cycling the Durable Object by hand.
   */
  private async handleClearMessages(): Promise<Response> {
    await this.env.DB.prepare(`DELETE FROM messages WHERE session_id = ?`)
      .bind(this.gameState!.sessionId)
      .run();

    this.gameState = { ...this.gameState!, messages: [] };

    this.broadcast(this.gameState);
    return ackResponse();
  }

  /** Add one Boon to the shared pool. Direct only for the facilitator. */
  private async applyAddBoon(): Promise<Response> {
    // Read `this.gameState` fresh rather than from a snapshot taken before an
    // await, so concurrent requests cannot clobber each other's writes.
    this.gameState = {
      ...this.gameState!,
      stonePool: [...this.gameState!.stonePool, "Boon"],
    };
    await this.saveStoneState(this.gameState);

    this.broadcast(this.gameState);
    return ackResponse();
  }

  /** A player asking to add a boon to the pool — queued for the facilitator. */
  private async proposeAddBoon(authInfo: AuthInfo): Promise<Response> {
    return this.addProposal({
      kind: "add-boon",
      proposerId: authInfo.discordUserId,
      proposerName: authInfo.username,
      slot: null,
      delta: 1,
    });
  }

  /**
   * Pledge (or withdraw) boons of the caller's own on the next roll. The slot is
   * the sheet they have claimed. Queued as a proposal; the effect only lands
   * when the facilitator accepts it. `delta` is the net change the client has
   * coalesced from a run of +/- taps, not necessarily ±1; `applyPledge` clamps
   * it to `[0, fate]` on accept.
   */
  private async handleCommitBoon(
    request: Request,
    authInfo: AuthInfo,
  ): Promise<Response> {
    const input = (await readJson(request)) as CommitBoonInput | null;
    const delta = input?.delta;
    if (
      typeof delta !== "number" ||
      !Number.isInteger(delta) ||
      delta === 0 ||
      Math.abs(delta) > MAX_PLEDGE_DELTA
    ) {
      return new Response("delta must be a non-zero integer", { status: 400 });
    }

    const character = this.gameState!.characters.find(
      (c) => c.ownerId === authInfo.discordUserId,
    );
    if (!character) {
      return new Response("Claim a character sheet first", { status: 400 });
    }

    return this.addProposal({
      kind: "pledge",
      proposerId: authInfo.discordUserId,
      proposerName: authInfo.username,
      slot: character.slot,
      delta,
    });
  }

  /**
   * Raise a once-per-session ability (`help-out` / `add-detail` / `gain-insight`
   * / `suggest-compel`) for the caller's claimed sheet. The ability is only
   * marked used when the facilitator accepts it; a rejection costs nothing.
   * `suggest-compel` carries a `targetSlot` — the character being compelled.
   */
  private async handleUseAbility(
    request: Request,
    authInfo: AuthInfo,
  ): Promise<Response> {
    const input = (await readJson(request)) as UseAbilityInput | null;
    const kind = input?.kind;
    if (!kind || !ABILITY_KINDS.includes(kind)) {
      return new Response("Unknown ability", { status: 400 });
    }
    if (!this.gameState!.session) {
      return new Response("Abilities need a running session", { status: 400 });
    }

    const character = this.gameState!.characters.find(
      (c) => c.ownerId === authInfo.discordUserId,
    );
    if (!character) {
      return new Response("Claim a character sheet first", { status: 400 });
    }

    const used =
      this.gameState!.usedAbilities.find((u) => u.slot === character.slot)
        ?.kinds ?? [];
    if (used.includes(kind)) {
      return new Response("Already used this ability this session", {
        status: 409,
      });
    }
    if (
      this.gameState!.proposals.some(
        (p) => p.slot === character.slot && p.kind === kind,
      )
    ) {
      return new Response("That ability is already proposed", { status: 409 });
    }
    if (
      kind === "help-out" &&
      (!this.gameState!.overcome || !this.gameState!.pendingRoll)
    ) {
      return new Response("Help Out needs an overcome roll to help with", {
        status: 400,
      });
    }

    let targetSlot: number | null = null;
    if (kind === "suggest-compel") {
      const raw = input?.targetSlot;
      if (
        typeof raw !== "number" ||
        !Number.isInteger(raw) ||
        raw < 0 ||
        raw >= CHARACTER_SLOT_COUNT
      ) {
        return new Response("A target character is required", { status: 400 });
      }
      if (raw === character.slot) {
        return new Response("You cannot compel your own character", {
          status: 400,
        });
      }
      targetSlot = raw;
    }

    return this.addProposal({
      kind,
      proposerId: authInfo.discordUserId,
      proposerName: authInfo.username,
      slot: character.slot,
      delta: 0,
      targetSlot,
    });
  }

  /**
   * Raise the Accept Compel move — take on a complication for
   * `ACCEPT_COMPEL_BOONS` boons once the facilitator approves. No per-session
   * limit, unlike the abilities.
   */
  private async handleAcceptCompelMove(
    authInfo: AuthInfo,
  ): Promise<Response> {
    const character = this.gameState!.characters.find(
      (c) => c.ownerId === authInfo.discordUserId,
    );
    if (!character) {
      return new Response("Claim a character sheet first", { status: 400 });
    }
    if (
      this.gameState!.proposals.some(
        (p) => p.slot === character.slot && p.kind === "accept-compel",
      )
    ) {
      return new Response("An Accept Compel is already proposed", {
        status: 409,
      });
    }

    return this.addProposal({
      kind: "accept-compel",
      proposerId: authInfo.discordUserId,
      proposerName: authInfo.username,
      slot: character.slot,
      delta: ACCEPT_COMPEL_BOONS,
    });
  }

  /**
   * Raise a request to spend a floating boon on the roll. Like a Highlight, it
   * only lands when the facilitator accepts it; the boon then leaves the
   * floating pool and a Boon enters the bag.
   */
  private async handleUseFloating(
    request: Request,
    authInfo: AuthInfo,
  ): Promise<Response> {
    const input = (await readJson(request)) as UseFloatingBoonInput | null;
    const floatingId =
      typeof input?.floatingId === "string" ? input.floatingId : "";
    if (!floatingId) {
      return new Response("floatingId is required", { status: 400 });
    }

    const character = this.gameState!.characters.find(
      (c) => c.ownerId === authInfo.discordUserId,
    );
    if (!character) {
      return new Response("Claim a character sheet first", { status: 400 });
    }
    if (!this.gameState!.floatingBoons.some((f) => f.id === floatingId)) {
      return new Response("No such floating boon", { status: 404 });
    }
    if (
      this.gameState!.proposals.some(
        (p) => p.kind === "use-floating" && p.floatingId === floatingId,
      )
    ) {
      return new Response("That floating boon is already proposed", {
        status: 409,
      });
    }

    return this.addProposal({
      kind: "use-floating",
      proposerId: authInfo.discordUserId,
      proposerName: authInfo.username,
      slot: character.slot,
      delta: 0,
      floatingId,
    });
  }

  private async addProposal(
    fields: Omit<
      Proposal,
      "id" | "createdAt" | "floatingId" | "targetSlot"
    > & {
      floatingId?: string | null;
      targetSlot?: number | null;
    },
  ): Promise<Response> {
    const { floatingId = null, targetSlot = null, ...rest } = fields;
    const proposal: Proposal = {
      ...rest,
      floatingId,
      targetSlot,
      id: crypto.randomUUID(),
      createdAt: Date.now(),
    };
    this.gameState = {
      ...this.gameState!,
      proposals: [...this.gameState!.proposals, proposal],
    };
    await this.saveStoneState(this.gameState);

    this.broadcast(this.gameState);
    return ackResponse();
  }

  /**
   * Facilitator resolves one proposal. Accept applies its effect (clamped to
   * current state); reject just drops it. Either way it leaves the queue. Some
   * accepts can still be refused — Help Out with no roll to affect, an
   * Add a Detail / Gain Insight with no context note — in which case the
   * proposal stays put for another try.
   */
  private async handleProposalDecision(
    proposalId: string,
    decision: "accept" | "reject",
    authInfo: AuthInfo,
    request: Request,
  ): Promise<Response> {
    const proposal = this.gameState!.proposals.find((p) => p.id === proposalId);
    if (!proposal) {
      return new Response("No such proposal", { status: 404 });
    }

    let state: GameState = {
      ...this.gameState!,
      proposals: this.gameState!.proposals.filter((p) => p.id !== proposalId),
    };
    let logLine = "";

    if (decision === "accept") {
      switch (proposal.kind) {
        case "add-boon":
          state = { ...state, stonePool: [...state.stonePool, "Boon"] };
          break;

        case "pledge": {
          const pledger =
            proposal.slot === null
              ? undefined
              : state.characters.find((c) => c.slot === proposal.slot);
          if (!pledger) {
            return this.proposalTargetGone();
          }
          state = applyPledge(state, pledger.slot, proposal.delta);
          break;
        }

        case "help-out": {
          if (!state.overcome || !state.pendingRoll) {
            return new Response(
              "Help Out needs an overcome roll to help with",
              { status: 400 },
            );
          }
          const pendingRoll = this.drawFromBag();
          state = {
            ...state,
            pendingRoll,
            usedAbilities: markAbilityUsed(
              state.usedAbilities,
              proposal.slot ?? -1,
              "help-out",
            ),
          };
          logLine = `Help Out — ${proposal.proposerName} · rerolled ${describeStones(
            pendingRoll.chosen,
          )}`;
          break;
        }

        case "add-detail":
        case "gain-insight": {
          const body = (await readJson(request)) as ProposalDecisionInput | null;
          const text = boundedString(body?.text, MAX_GOAL_LENGTH).trim();
          if (!text) {
            return new Response("A context note is required", { status: 400 });
          }
          const floating: FloatingBoon = {
            id: crypto.randomUUID(),
            text,
            createdByName: proposal.proposerName,
            createdAt: Date.now(),
          };
          state = {
            ...state,
            floatingBoons: [...state.floatingBoons, floating],
            usedAbilities: markAbilityUsed(
              state.usedAbilities,
              proposal.slot ?? -1,
              proposal.kind,
            ),
          };
          logLine = `${
            proposal.kind === "add-detail" ? "Detail added" : "Insight gained"
          } — ${text} (${proposal.proposerName})`;
          break;
        }

        case "suggest-compel": {
          const suggester =
            proposal.slot === null
              ? undefined
              : state.characters.find((c) => c.slot === proposal.slot);
          const compelled =
            proposal.targetSlot === null
              ? undefined
              : state.characters.find((c) => c.slot === proposal.targetSlot);
          if (!suggester || !compelled) {
            return this.proposalTargetGone();
          }
          let characters = state.characters;
          characters = await this.bumpFate(
            characters,
            suggester.slot,
            SUGGEST_COMPEL_SUGGESTER_BOONS,
          );
          characters = await this.bumpFate(
            characters,
            compelled.slot,
            SUGGEST_COMPEL_TARGET_BOONS,
          );
          state = {
            ...state,
            characters,
            usedAbilities: markAbilityUsed(
              state.usedAbilities,
              suggester.slot,
              "suggest-compel",
            ),
          };
          logLine = `Compel suggested — ${characterLabel(
            suggester,
          )} +${SUGGEST_COMPEL_SUGGESTER_BOONS}, ${characterLabel(
            compelled,
          )} +${SUGGEST_COMPEL_TARGET_BOONS} boons`;
          break;
        }

        case "accept-compel": {
          const character =
            proposal.slot === null
              ? undefined
              : state.characters.find((c) => c.slot === proposal.slot);
          if (!character) {
            return this.proposalTargetGone();
          }
          state = {
            ...state,
            characters: await this.bumpFate(
              state.characters,
              character.slot,
              ACCEPT_COMPEL_BOONS,
            ),
          };
          logLine = `Compel accepted — ${characterLabel(
            character,
          )} +${ACCEPT_COMPEL_BOONS} boons`;
          break;
        }

        case "use-floating": {
          const floating = state.floatingBoons.find(
            (f) => f.id === proposal.floatingId,
          );
          if (!floating) {
            return this.proposalTargetGone();
          }
          state = {
            ...state,
            floatingBoons: state.floatingBoons.filter(
              (f) => f.id !== floating.id,
            ),
            stonePool: [...state.stonePool, "Boon"],
          };
          logLine = `Floating boon spent — ${floating.text} (${proposal.proposerName})`;
          break;
        }
      }
    }

    this.gameState = state;
    await this.saveStoneState(this.gameState);

    if (logLine) {
      await this.appendMessage({
        authorId: authInfo.discordUserId,
        authorName: authInfo.username,
        role: authInfo.role,
        content: logLine,
      });
    }

    this.broadcast(this.gameState);
    return ackResponse();
  }

  /**
   * An accepted proposal whose character / floating boon has since gone (a
   * released or reslotted sheet). Return an error and leave the proposal
   * queued rather than dropping it with no effect and no log line.
   */
  private proposalTargetGone(): Response {
    return new Response("That proposal's target no longer exists", {
      status: 409,
    });
  }

  /** A proposer pulls back their own still-pending proposal. */
  private async handleWithdrawProposal(
    proposalId: string,
    authInfo: AuthInfo,
  ): Promise<Response> {
    const proposal = this.gameState!.proposals.find((p) => p.id === proposalId);
    if (!proposal) {
      return new Response("No such proposal", { status: 404 });
    }
    if (proposal.proposerId !== authInfo.discordUserId) {
      return new Response("Not your proposal", { status: 403 });
    }

    this.gameState = {
      ...this.gameState!,
      proposals: this.gameState!.proposals.filter((p) => p.id !== proposalId),
    };
    await this.saveStoneState(this.gameState);

    await this.appendMessage({
      authorId: authInfo.discordUserId,
      authorName: authInfo.username,
      role: authInfo.role,
      content: `${proposal.proposerName} withdrew a proposal`,
    });

    this.broadcast(this.gameState);
    return ackResponse();
  }

  private drawFromBag(): PendingRoll {
    const committed = totalCommittedBoons(this.gameState!.committedBoons);
    const bag: StoneKind[] = [
      ...this.gameState!.stonePool,
      ...Array<StoneKind>(committed).fill("Boon"),
    ];
    return pickTwoRandom(bag);
  }

  /**
   * Add `amount` boons to one character's `fate` in D1, and return the character
   * list with that change folded in. `amount` may be negative; `fate` floors at
   * zero.
   */
  private async bumpFate(
    characters: CharacterSheet[],
    slot: number,
    amount: number,
  ): Promise<CharacterSheet[]> {
    const character = characters.find((c) => c.slot === slot);
    if (!character || amount === 0) return characters;

    const fate = Math.max(0, character.fate + amount);
    await this.env.DB.prepare(
      `UPDATE characters SET fate = ?, updated_at = ? WHERE id = ?`,
    )
      .bind(fate, Date.now(), character.id)
      .run();
    return characters.map((c) => (c.slot === slot ? { ...c, fate } : c));
  }

  /**
   * Gate for `/stones/roll` and `/stones/reroll`. The facilitator may always
   * roll. While an overcome is open, the player whose sheet is its target may
   * roll too; nobody else.
   */
  private rollGate(authInfo: AuthInfo): Response | undefined {
    if (authInfo.role === "facilitator") return undefined;

    const overcome = this.gameState!.overcome;
    if (overcome) {
      const own = this.gameState!.characters.find(
        (c) => c.ownerId === authInfo.discordUserId,
      );
      if (own && own.slot === overcome.targetSlot) return undefined;
    }

    return new Response(
      "Only the facilitator or the overcome target can roll",
      { status: 403 },
    );
  }

  private async handleRoll(
    authInfo: AuthInfo,
    verb: "Rolled" | "Rerolled",
  ): Promise<Response> {
    const overcome = this.gameState!.overcome;
    let characters = this.gameState!.characters;
    let costNote = "";

    // A Reroll during an overcome is bought with the target's boons.
    if (verb === "Rerolled" && overcome) {
      const target = characters.find((c) => c.slot === overcome.targetSlot);
      if (!target) {
        return new Response("The overcome target has no sheet", { status: 400 });
      }
      if (target.fate < REROLL_COST) {
        return new Response(
          `The overcome target needs ${REROLL_COST} boons to reroll`,
          { status: 400 },
        );
      }

      const fate = target.fate - REROLL_COST;
      await this.env.DB.prepare(
        `UPDATE characters SET fate = ?, updated_at = ? WHERE id = ?`,
      )
        .bind(fate, Date.now(), target.id)
        .run();
      characters = characters.map((c) =>
        c.slot === target.slot ? { ...c, fate } : c,
      );
      costNote = ` — reroll cost ${REROLL_COST} boons`;
    }

    const committed = totalCommittedBoons(this.gameState!.committedBoons);
    const pendingRoll = this.drawFromBag();

    this.gameState = { ...this.gameState!, characters, pendingRoll };
    await this.saveStoneState(this.gameState);

    const committedNote =
      committed > 0 ? ` — ${committed} boon committed` : "";
    const label = overcome
      ? verb === "Rerolled"
        ? "Overcome reroll"
        : "Overcome roll"
      : verb;
    await this.appendMessage({
      authorId: authInfo.discordUserId,
      authorName: authInfo.username,
      role: authInfo.role,
      content: `${label}: ${describeStones(pendingRoll.chosen)}${committedNote}${costNote}`,
    });

    this.broadcast(this.gameState!);
    return ackResponse();
  }

  private async handleAcceptRoll(authInfo: AuthInfo): Promise<Response> {
    // Nothing to accept without a roll on the table — refuse rather than
    // silently reset the pool and drop the proposal queue.
    if (!this.gameState!.pendingRoll) {
      return new Response("No roll to accept", { status: 400 });
    }

    // Spend the pledged boons from each character's stock, then clear the pool
    // and pledges back to the base state.
    const now = Date.now();
    let characters = this.gameState!.characters;

    for (const { slot, count } of this.gameState!.committedBoons) {
      const character = characters.find((c) => c.slot === slot);
      if (!character || count <= 0) continue;

      const fate = Math.max(0, character.fate - count);
      await this.env.DB.prepare(
        `UPDATE characters SET fate = ?, updated_at = ? WHERE id = ?`,
      )
        .bind(fate, now, character.id)
        .run();
      characters = characters.map((c) => (c.slot === slot ? { ...c, fate } : c));
    }

    // Route the accepted roll's result stones (section 19). An overcome draws
    // two: two of a kind feed the session pool whole; a mixed roll sends the
    // Boon to the pool and drops the Bane onto one of the acting character's
    // aspects at random — unless that character is untethered, in which case the
    // Bane also goes to the pool (no new aspect strain mid-reckoning). A plain
    // non-overcome roll still seeds the pool with one random result stone.
    const priorSession = this.gameState!.session;
    const drawn = this.gameState!.pendingRoll?.chosen ?? [];
    const overcome = this.gameState!.overcome;
    const poolAdds: StoneKind[] = [];
    let routeNote = "";

    if (overcome && drawn.length === 2) {
      const boons = drawn.filter((s) => s === "Boon").length;
      const untetheredTarget =
        this.gameState!.untether?.slot === overcome.targetSlot;

      if (boons === 1 && !untetheredTarget) {
        poolAdds.push("Boon");
        const aspect = ASPECT_NAMES[randomInt(ASPECT_NAMES.length)];
        const target = characters.find((c) => c.slot === overcome.targetSlot);
        if (target) {
          const column = ASPECT_BANE_COLUMNS[aspect];
          await this.env.DB.prepare(
            `UPDATE characters SET ${column} = ${column} + 1, updated_at = ? WHERE id = ?`,
          )
            .bind(now, target.id)
            .run();
          characters = characters.map((c) =>
            c.slot === target.slot
              ? {
                  ...c,
                  aspectBanes: {
                    ...c.aspectBanes,
                    [aspect]: c.aspectBanes[aspect] + 1,
                  },
                }
              : c,
          );
          routeNote = `Boon to the pool, Bane onto ${aspect}`;
        }
      } else {
        poolAdds.push(...drawn);
        routeNote =
          boons === 2
            ? "both Boons to the pool"
            : boons === 0
              ? "both Banes to the pool"
              : "Boon to the pool, Bane to the pool (untethered)";
      }
    } else if (drawn.length > 0) {
      poolAdds.push(drawn[randomInt(drawn.length)]);
    }

    const session: SessionState | null =
      priorSession && poolAdds.length > 0
        ? { ...priorSession, pool: [...priorSession.pool, ...poolAdds] }
        : priorSession;

    this.gameState = {
      ...this.gameState!,
      characters,
      stonePool: [...INITIAL_STONE_POOL],
      pendingRoll: null,
      // Accepting the roll resolves any open overcome.
      overcome: null,
      committedBoons: [],
      // A resolved roll clears the slate; unaccepted proposals do not carry over.
      proposals: [],
      session,
    };
    await this.saveStoneState(this.gameState);

    if (overcome) {
      const target = characters.find((c) => c.slot === overcome.targetSlot);
      await this.appendMessage({
        authorId: authInfo.discordUserId,
        authorName: authInfo.username,
        role: authInfo.role,
        content: `Overcome${target ? ` — ${characterLabel(target)}` : ""}: ${
          routeNote || drawn.join(", ")
        }`,
      });
    }

    this.broadcast(this.gameState);
    return ackResponse();
  }

  private async handleStartOvercome(
    request: Request,
    authInfo: AuthInfo,
  ): Promise<Response> {
    if (this.gameState!.overcome) {
      return new Response("An overcome is already open", { status: 409 });
    }

    const input = (await readJson(request)) as StartOvercomeInput | null;
    const slot = input?.slot;
    if (
      typeof slot !== "number" ||
      !Number.isInteger(slot) ||
      slot < 0 ||
      slot >= CHARACTER_SLOT_COUNT
    ) {
      return new Response("slot out of range", { status: 400 });
    }

    const target = this.gameState!.characters.find((c) => c.slot === slot);
    if (!target) {
      return new Response("Not found", { status: 404 });
    }

    // A fresh attempt: drop any roll still sitting on the table.
    this.gameState = {
      ...this.gameState!,
      overcome: { targetSlot: slot },
      pendingRoll: null,
    };
    await this.saveStoneState(this.gameState);

    await this.appendMessage({
      authorId: authInfo.discordUserId,
      authorName: authInfo.username,
      role: authInfo.role,
      content: `Overcome — ${characterLabel(target)} attempts something risky`,
    });

    this.broadcast(this.gameState);
    return ackResponse();
  }

  private async handleCancelOvercome(authInfo: AuthInfo): Promise<Response> {
    const overcome = this.gameState!.overcome;
    if (!overcome) {
      return new Response("No overcome is open", { status: 400 });
    }

    const target = this.gameState!.characters.find(
      (c) => c.slot === overcome.targetSlot,
    );

    this.gameState = { ...this.gameState!, overcome: null };
    await this.saveStoneState(this.gameState);

    await this.appendMessage({
      authorId: authInfo.discordUserId,
      authorName: authInfo.username,
      role: authInfo.role,
      content: `Overcome called off${
        target ? ` — ${characterLabel(target)}` : ""
      }`,
    });

    this.broadcast(this.gameState);
    return ackResponse();
  }

  private async handleStartSession(
    request: Request,
    authInfo: AuthInfo,
  ): Promise<Response> {
    if (this.gameState!.session) {
      return new Response("A session is already running", { status: 409 });
    }

    const input = (await readJson(request)) as StartSessionInput | null;
    const goal = boundedString(input?.goal, MAX_GOAL_LENGTH).trim();
    if (!goal) {
      return new Response("A session goal is required", { status: 400 });
    }

    const id = crypto.randomUUID();
    await this.env.DB.prepare(
      `INSERT INTO game_sessions (id, session_id, goal, started_at) VALUES (?, ?, ?, ?)`,
    )
      .bind(id, this.gameState!.sessionId, goal, Date.now())
      .run();

    // Section 19: the pool starts from the base four plus every Bane carried
    // from the previous session (Boons never carry; a failed goal flushes the
    // carry to zero). `untether` is deliberately not touched here — a reckoning
    // spans into the following session.
    const carriedBanes = this.carriedBanes;
    const pool: StoneKind[] = [
      ...INITIAL_SESSION_POOL,
      ...Array<StoneKind>(carriedBanes).fill("Bane"),
    ];

    this.gameState = {
      ...this.gameState!,
      session: { id, goal, pool, carriedBanes },
      // A new session starts from a clean slate. Nothing left open at the end
      // of the previous session (or before this one began) carries in:
      // abilities, floating boons, an unresolved overcome or roll, pledges, or
      // a proposal queue.
      usedAbilities: [],
      floatingBoons: [],
      overcome: null,
      pendingRoll: null,
      committedBoons: [],
      proposals: [],
    };
    await this.saveStoneState(this.gameState);

    await this.appendMessage({
      authorId: authInfo.discordUserId,
      authorName: authInfo.username,
      role: authInfo.role,
      content: `Session started — ${goal}${
        carriedBanes > 0 ? ` (carrying ${carriedBanes} Bane${carriedBanes === 1 ? "" : "s"})` : ""
      }`,
    });

    this.broadcast(this.gameState);
    return ackResponse();
  }

  private async handleEndSession(authInfo: AuthInfo): Promise<Response> {
    const session = this.gameState!.session;
    if (!session) {
      return new Response("No session is running", { status: 400 });
    }

    // Section 19: the goal succeeds or fails on a single stone drawn from the
    // pool. On success the Boons flush and the Banes carry; a failure flushes
    // the pool completely back to the base four.
    const now = Date.now();
    const drawn = session.pool[randomInt(session.pool.length)];
    const success = drawn === "Boon";
    const banesInPool = session.pool.filter((s) => s === "Bane").length;
    const nextCarry = success ? banesInPool : 0;
    const wasConsecutiveFailure = this.lastSessionFailed;

    // A failed goal untethers one character — unless a reckoning is already
    // open, or the previous session also failed, or nobody carries an aspect
    // Bane. The character is drawn by weighting every aspect Bane on every
    // sheet equally; the drawn aspect is the one they untether on, and all
    // their aspect Banes then clear.
    let characters = this.gameState!.characters;
    let untether = this.gameState!.untether;
    let untetherNote = "";

    if (!success && untether === null && !wasConsecutiveFailure) {
      const bag: { slot: number; aspect: AspectName }[] = [];
      for (const c of characters) {
        for (const aspect of ASPECT_NAMES) {
          for (let i = 0; i < c.aspectBanes[aspect]; i++) {
            bag.push({ slot: c.slot, aspect });
          }
        }
      }

      if (bag.length > 0) {
        const pick = bag[randomInt(bag.length)];
        untether = { slot: pick.slot, aspect: pick.aspect };
        const target = characters.find((c) => c.slot === pick.slot)!;
        await this.env.DB.prepare(
          `UPDATE characters
             SET archetype_banes = 0, desire_banes = 0, quest_banes = 0, updated_at = ?
           WHERE id = ?`,
        )
          .bind(now, target.id)
          .run();
        characters = characters.map((c) =>
          c.slot === pick.slot
            ? { ...c, aspectBanes: { archetype: 0, desire: 0, quest: 0 } }
            : c,
        );
        untetherNote = ` — ${characterLabel(target)} untethered on ${pick.aspect}`;
      }
    }

    const outcome = success
      ? `goal met — drew Boon${nextCarry > 0 ? ` (${nextCarry} Bane${nextCarry === 1 ? "" : "s"} carried)` : ""}`
      : `goal failed — drew Bane (pool flushed)${untetherNote}`;

    await this.env.DB.prepare(
      `UPDATE game_sessions SET ended_at = ?, outcome = ? WHERE id = ?`,
    )
      .bind(now, outcome, session.id)
      .run();

    this.carriedBanes = nextCarry;
    this.lastSessionFailed = !success;

    const sessionHistory = await this.loadSessionHistory(
      this.gameState!.sessionId,
    );
    this.gameState = {
      ...this.gameState!,
      session: null,
      sessionHistory,
      characters,
      untether,
      // Ending a session discards everything left unresolved: unspent floating
      // boons, once-per-session abilities, an open overcome or roll on the
      // table, pledged boons, and any proposal the facilitator never accepted
      // or rejected. Nothing from a closed session carries into the next one.
      floatingBoons: [],
      usedAbilities: [],
      overcome: null,
      pendingRoll: null,
      committedBoons: [],
      proposals: [],
    };
    await this.saveStoneState(this.gameState);

    await this.appendMessage({
      authorId: authInfo.discordUserId,
      authorName: authInfo.username,
      role: authInfo.role,
      content: `Session ended — ${session.goal}: ${outcome}`,
    });

    this.broadcast(this.gameState);
    return ackResponse();
  }

  /** Facilitator rewrites the running session's goal. */
  private async handleUpdateSessionGoal(
    request: Request,
    authInfo: AuthInfo,
  ): Promise<Response> {
    const session = this.gameState!.session;
    if (!session) {
      return new Response("No session is running", { status: 400 });
    }

    const input = (await readJson(request)) as UpdateSessionGoalInput | null;
    const goal = boundedString(input?.goal, MAX_GOAL_LENGTH).trim();
    if (!goal) {
      return new Response("A session goal is required", { status: 400 });
    }
    if (goal === session.goal) {
      return ackResponse();
    }

    await this.env.DB.prepare(
      `UPDATE game_sessions SET goal = ? WHERE id = ?`,
    )
      .bind(goal, session.id)
      .run();

    this.gameState = {
      ...this.gameState!,
      session: { ...session, goal },
    };
    await this.saveStoneState(this.gameState);

    await this.appendMessage({
      authorId: authInfo.discordUserId,
      authorName: authInfo.username,
      role: authInfo.role,
      content: `Goal updated — ${goal}`,
    });

    this.broadcast(this.gameState);
    return ackResponse();
  }

  /**
   * Close an in-progress reckoning (section 19). The facilitator-framed scene
   * is table talk; this just clears the flag so a later failed goal can untether
   * again. The player rewriting or replacing the untethered aspect happens
   * through the normal sheet edit.
   */
  private async handleResolveUntether(authInfo: AuthInfo): Promise<Response> {
    const untether = this.gameState!.untether;
    if (!untether) {
      return new Response("No untether to resolve", { status: 400 });
    }

    const target = this.gameState!.characters.find(
      (c) => c.slot === untether.slot,
    );

    this.gameState = { ...this.gameState!, untether: null };
    await this.saveStoneState(this.gameState);

    await this.appendMessage({
      authorId: authInfo.discordUserId,
      authorName: authInfo.username,
      role: authInfo.role,
      content: `Untether resolved${
        target ? ` — ${characterLabel(target)}` : ""
      } (${untether.aspect})`,
    });

    this.broadcast(this.gameState);
    return ackResponse();
  }

  private async handleUpdateCharacter(
    request: Request,
    slot: number,
    authInfo: AuthInfo,
  ): Promise<Response> {
    const input = (await readJson(request)) as UpdateCharacterInput | null;
    if (!input) {
      return new Response("Invalid body", { status: 400 });
    }

    const character = this.gameState!.characters.find((c) => c.slot === slot);
    if (!character) {
      return new Response("Not found", { status: 404 });
    }

    // The facilitator may edit any sheet; a player only their own, or one that
    // no one has claimed yet (setup before claiming).
    const mayEdit =
      authInfo.role === "facilitator" ||
      character.ownerId === null ||
      character.ownerId === authInfo.discordUserId;
    if (!mayEdit) {
      return new Response("Not your character sheet", { status: 403 });
    }

    const updated: CharacterSheet = {
      ...character,
      name: boundedField(input.name, character.name),
      notableFeatures: boundedField(
        input.notableFeatures,
        character.notableFeatures,
      ),
      archetype: boundedField(input.archetype, character.archetype),
      desire: boundedField(input.desire, character.desire),
      quest: boundedField(input.quest, character.quest),
      condition: boundedField(input.condition, character.condition),
      notes: boundedField(input.notes, character.notes, MAX_NOTES_LENGTH),
    };

    await this.env.DB.prepare(
      `
      UPDATE characters
      SET name = ?, notable_features = ?, archetype = ?, desire = ?, quest = ?, condition = ?, notes = ?, updated_at = ?
      WHERE id = ?
    `,
    )
      .bind(
        updated.name,
        updated.notableFeatures,
        updated.archetype,
        updated.desire,
        updated.quest,
        updated.condition,
        updated.notes,
        Date.now(),
        updated.id,
      )
      .run();

    this.gameState = {
      ...this.gameState!,
      characters: this.gameState!.characters.map((c) =>
        c.slot === slot ? updated : c,
      ),
    };

    this.broadcast(this.gameState);
    return ackResponse();
  }

  /**
   * Bind the calling user to a sheet. Fails if someone else holds it; releases
   * any other sheet the caller already holds so a player owns at most one.
   */
  private async handleClaimSlot(
    slot: number,
    authInfo: AuthInfo,
  ): Promise<Response> {
    const target = this.gameState!.characters.find((c) => c.slot === slot);
    if (!target) {
      return new Response("Not found", { status: 404 });
    }
    if (target.ownerId && target.ownerId !== authInfo.discordUserId) {
      return new Response("Sheet already claimed", { status: 409 });
    }
    // Re-claiming a sheet the caller already holds is a no-op — don't wipe that
    // slot's own pledges / proposals.
    if (target.ownerId === authInfo.discordUserId) {
      return ackResponse();
    }

    const now = Date.now();
    const priorSlots = this.gameState!.characters.filter(
      (c) => c.ownerId === authInfo.discordUserId && c.slot !== slot,
    );
    for (const prior of priorSlots) {
      await this.setSheetOwner(prior.id, null, now);
    }
    await this.setSheetOwner(target.id, authInfo.discordUserId, now);

    let next: GameState = {
      ...this.gameState!,
      characters: this.gameState!.characters.map((c) => {
        if (c.slot === slot) return { ...c, ownerId: authInfo.discordUserId };
        if (priorSlots.some((p) => p.id === c.id)) return { ...c, ownerId: null };
        return c;
      }),
    };
    // Any sheet whose owner just changed — the one just claimed, and any the
    // caller was released from to take it — must not keep pledges or proposals
    // aimed at whoever held it before.
    for (const changed of [slot, ...priorSlots.map((p) => p.slot)]) {
      next = clearSlotPendingState(next, changed);
    }
    this.gameState = next;
    await this.saveStoneState(this.gameState);

    this.broadcast(this.gameState);
    return ackResponse();
  }

  /** Release a sheet. Allowed for the sheet's owner or the facilitator. */
  private async handleReleaseSlot(
    slot: number,
    authInfo: AuthInfo,
  ): Promise<Response> {
    const target = this.gameState!.characters.find((c) => c.slot === slot);
    if (!target) {
      return new Response("Not found", { status: 404 });
    }
    if (!target.ownerId) {
      return ackResponse();
    }
    if (
      target.ownerId !== authInfo.discordUserId &&
      authInfo.role !== "facilitator"
    ) {
      return new Response("Not your character sheet", { status: 403 });
    }

    await this.setSheetOwner(target.id, null, Date.now());
    this.gameState = clearSlotPendingState(
      {
        ...this.gameState!,
        characters: this.gameState!.characters.map((c) =>
          c.slot === slot ? { ...c, ownerId: null } : c,
        ),
      },
      slot,
    );
    await this.saveStoneState(this.gameState);

    this.broadcast(this.gameState);
    return ackResponse();
  }

  private async setSheetOwner(
    id: string,
    ownerId: string | null,
    now: number,
  ): Promise<void> {
    await this.env.DB.prepare(
      `UPDATE characters SET discord_user_id = ?, updated_at = ? WHERE id = ?`,
    )
      .bind(ownerId, now, id)
      .run();
  }

  private async handleUpdateFate(
    request: Request,
    slot: number,
  ): Promise<Response> {
    const input = (await readJson(request)) as UpdateFateInput | null;
    const delta = input?.delta;
    if (typeof delta !== "number" || !Number.isInteger(delta)) {
      return new Response("delta must be an integer", { status: 400 });
    }

    const character = this.gameState!.characters.find((c) => c.slot === slot);
    if (!character) {
      return new Response("Not found", { status: 404 });
    }

    const fate = Math.max(0, character.fate + delta);

    await this.env.DB.prepare(
      `UPDATE characters SET fate = ?, updated_at = ? WHERE id = ?`,
    )
      .bind(fate, Date.now(), character.id)
      .run();

    this.gameState = {
      ...this.gameState!,
      characters: this.gameState!.characters.map((c) =>
        c.slot === slot ? { ...c, fate } : c,
      ),
    };

    this.broadcast(this.gameState);
    return ackResponse();
  }

  /** Add a blank NPC / location row, ready for the facilitator to fill in. */
  private async handleCreateEntity(
    request: Request,
    kind: EntityKind,
  ): Promise<Response> {
    const input = (await readJson(request)) as EntityInput | null;
    const now = Date.now();
    const entity: TableEntity = {
      id: crypto.randomUUID(),
      name: boundedString(input?.name, MAX_FIELD_LENGTH),
      notes: boundedString(input?.notes, MAX_NOTES_LENGTH),
      createdAt: now,
      updatedAt: now,
    };

    await this.env.DB.prepare(
      `
      INSERT INTO ${entityTable(kind)} (id, session_id, name, notes, created_at, updated_at)
      VALUES (?, ?, ?, ?, ?, ?)
    `,
    )
      .bind(
        entity.id,
        this.gameState!.sessionId,
        entity.name,
        entity.notes,
        now,
        now,
      )
      .run();

    this.gameState = {
      ...this.gameState!,
      [kind]: [...this.gameState![kind], entity],
    };

    this.broadcast(this.gameState);
    return ackResponse();
  }

  private async handleUpdateEntity(
    request: Request,
    kind: EntityKind,
    id: string,
  ): Promise<Response> {
    const input = (await readJson(request)) as EntityInput | null;
    if (!input) {
      return new Response("Invalid body", { status: 400 });
    }

    const entity = this.gameState![kind].find((e) => e.id === id);
    if (!entity) {
      return new Response("Not found", { status: 404 });
    }

    const updated: TableEntity = {
      ...entity,
      name: boundedField(input.name, entity.name),
      notes: boundedField(input.notes, entity.notes, MAX_NOTES_LENGTH),
      updatedAt: Date.now(),
    };

    await this.env.DB.prepare(
      `UPDATE ${entityTable(kind)} SET name = ?, notes = ?, updated_at = ? WHERE id = ?`,
    )
      .bind(updated.name, updated.notes, updated.updatedAt, id)
      .run();

    this.gameState = {
      ...this.gameState!,
      [kind]: this.gameState![kind].map((e) => (e.id === id ? updated : e)),
    };

    this.broadcast(this.gameState);
    return ackResponse();
  }

  private async handleDeleteEntity(
    kind: EntityKind,
    id: string,
  ): Promise<Response> {
    if (!this.gameState![kind].some((e) => e.id === id)) {
      return new Response("Not found", { status: 404 });
    }

    await this.env.DB.prepare(
      `DELETE FROM ${entityTable(kind)} WHERE id = ?`,
    )
      .bind(id)
      .run();

    this.gameState = {
      ...this.gameState!,
      [kind]: this.gameState![kind].filter((e) => e.id !== id),
    };

    this.broadcast(this.gameState);
    return ackResponse();
  }

  /** Persists the message, then folds it into the current in-memory state. */
  private async appendMessage(input: AddMessageInput): Promise<void> {
    const msg: Message = {
      id: crypto.randomUUID(),
      sessionId: this.gameState!.sessionId,
      authorId: input.authorId,
      authorName: input.authorName,
      role: input.role,
      content: input.content,
      createdAt: Date.now(),
    };

    await this.env.DB.prepare(
      `
      INSERT INTO messages (id, session_id, author_id, author_name, role, content, created_at)
      VALUES (?, ?, ?, ?, ?, ?, ?)
    `,
    )
      .bind(
        msg.id,
        msg.sessionId,
        msg.authorId,
        msg.authorName,
        msg.role,
        msg.content,
        msg.createdAt,
      )
      .run();

    this.gameState = {
      ...this.gameState!,
      messages: capMessages([...this.gameState!.messages, msg]),
    };
  }
}

type AddMessageInput = {
  authorId: string;
  authorName: string;
  role: Role;
  content: string;
};

function capMessages(messages: Message[]): Message[] {
  return messages.length > MESSAGE_WINDOW
    ? messages.slice(messages.length - MESSAGE_WINDOW)
    : messages;
}

async function readJson(request: Request): Promise<unknown> {
  try {
    const parsed = await request.json();
    return parsed && typeof parsed === "object" ? parsed : null;
  } catch {
    return null;
  }
}

function boundedString(value: unknown, max: number): string {
  return typeof value === "string" ? value.slice(0, max) : "";
}

function boundedField(
  value: unknown,
  fallback: string,
  max: number = MAX_FIELD_LENGTH,
): string {
  return typeof value === "string" ? value.slice(0, max) : fallback;
}

function pickTwoRandom(pool: StoneKind[]): PendingRoll {
  const indices = pool.map((_, i) => i);

  for (let i = indices.length - 1; i > 0; i--) {
    const j = randomInt(i + 1);
    [indices[i], indices[j]] = [indices[j], indices[i]];
  }

  const chosenIndices = new Set(indices.slice(0, Math.min(2, indices.length)));
  const chosen: StoneKind[] = [];
  const rest: StoneKind[] = [];

  pool.forEach((stone, i) => {
    if (chosenIndices.has(i)) {
      chosen.push(stone);
    } else {
      rest.push(stone);
    }
  });

  return { chosen, rest };
}

/** Rejection sampling, so the low indices are not favoured by modulo bias. */
function randomInt(maxExclusive: number): number {
  const limit = Math.floor(0x100000000 / maxExclusive) * maxExclusive;
  const buf = new Uint32Array(1);

  do {
    crypto.getRandomValues(buf);
  } while (buf[0] >= limit);

  return buf[0] % maxExclusive;
}

function describeStones(stones: StoneKind[]): string {
  return stones.join(", ");
}

/** A character's name for the log, falling back to its slot number. */
function characterLabel(character: CharacterSheet): string {
  const name = character.name.trim();
  return name || `Character ${character.slot + 1}`;
}

function totalCommittedBoons(committed: CommittedBoon[]): number {
  return committed.reduce((sum, c) => sum + c.count, 0);
}

/**
 * Pledge (`delta` +1) or withdraw (-1) one of a character's own boons on the
 * next roll, clamped to what they hold. Shared by the direct pledge route and
 * an accepted `pledge` proposal.
 */
function applyPledge(state: GameState, slot: number, delta: number): GameState {
  const character = state.characters.find((c) => c.slot === slot);
  if (!character) return state;

  const current =
    state.committedBoons.find((c) => c.slot === slot)?.count ?? 0;
  const next = Math.max(0, Math.min(character.fate, current + delta));

  const committedBoons = state.committedBoons.filter((c) => c.slot !== slot);
  if (next > 0) {
    committedBoons.push({ slot, count: next });
  }
  committedBoons.sort((a, b) => a.slot - b.slot);
  return { ...state, committedBoons };
}

/**
 * Drop a slot's pledged boons and any proposal that points at it (as the
 * proposer's own slot or as a `suggest-compel` target). Called when a sheet
 * changes hands, so an accepted roll or proposal cannot spend or target the
 * wrong character's boons.
 */
function clearSlotPendingState(state: GameState, slot: number): GameState {
  return {
    ...state,
    committedBoons: state.committedBoons.filter((c) => c.slot !== slot),
    proposals: state.proposals.filter(
      (p) => p.slot !== slot && p.targetSlot !== slot,
    ),
  };
}

/** Record `kind` as spent for `slot` this session; idempotent. */
function markAbilityUsed(
  used: UsedAbilities[],
  slot: number,
  kind: AbilityKind,
): UsedAbilities[] {
  const row = used.find((u) => u.slot === slot);
  if (!row) return [...used, { slot, kinds: [kind] }];
  if (row.kinds.includes(kind)) return used;
  return used.map((u) =>
    u.slot === slot ? { ...u, kinds: [...u.kinds, kind] } : u,
  );
}

/**
 * The D1 table backing an entity kind. An explicit allowlist so the name is
 * never anything but one of these two literals when it reaches a SQL string.
 */
function entityTable(kind: EntityKind): "npcs" | "locations" {
  return kind === "npcs" ? "npcs" : "locations";
}

type CharacterRow = {
  id: string;
  slot: number;
  name: string;
  notable_features: string;
  archetype: string;
  desire: string;
  quest: string;
  condition: string;
  notes: string;
  fate: number;
  discord_user_id: string | null;
  archetype_banes: number;
  desire_banes: number;
  quest_banes: number;
};

function rowToCharacterSheet(row: CharacterRow): CharacterSheet {
  return {
    id: row.id,
    slot: row.slot,
    name: row.name,
    notableFeatures: row.notable_features,
    archetype: row.archetype,
    desire: row.desire,
    quest: row.quest,
    condition: row.condition,
    notes: row.notes,
    fate: row.fate,
    aspectBanes: {
      archetype: row.archetype_banes,
      desire: row.desire_banes,
      quest: row.quest_banes,
    },
    ownerId: row.discord_user_id,
  };
}

type AuthInfo = {
  discordUserId: string;
  username: string;
  role: Role;
};

/**
 * Gate for routes only the facilitator may call. Returns a 403 to short-circuit
 * the route, or `undefined` to let it run: `facilitatorOnly(authInfo) ?? run()`.
 */
function facilitatorOnly(authInfo: AuthInfo): Response | undefined {
  if (authInfo.role !== "facilitator") {
    return new Response("Facilitator only", { status: 403 });
  }
  return undefined;
}

function parseTokenFromProtocol(header: string | null): string | null {
  if (!header) return null;

  const parts = header.split(",").map((part) => part.trim());
  return parts.find((part) => part && part !== "bearer") ?? null;
}

async function getAuthFromToken(
  env: Env,
  token: string,
): Promise<AuthInfo | null> {
  const row = await env.DB.prepare(
    `
    SELECT s.discord_user_id, s.discord_username, dm.discord_user_id AS dm_id
    FROM sessions_auth s
    LEFT JOIN facilitators dm ON dm.discord_user_id = s.discord_user_id
    WHERE s.session_token = ? AND s.expires_at > ?
    LIMIT 1
  `,
  )
    .bind(token, Date.now())
    .first<{
      discord_user_id: string;
      discord_username: string;
      dm_id: string | null;
    } | null>();

  if (!row) return null;

  const isBootstrap =
    !!env.BOOTSTRAP_FACILITATOR_ID &&
    env.BOOTSTRAP_FACILITATOR_ID === row.discord_user_id;
  const role: Role = row.dm_id || isBootstrap ? "facilitator" : "player";

  return {
    discordUserId: row.discord_user_id,
    username: row.discord_username,
    role,
  };
}

function jsonResponse(data: unknown, init?: ResponseInit): Response {
  return new Response(JSON.stringify(data), {
    status: 200,
    ...init,
    headers: { "Content-Type": "application/json", ...init?.headers },
  });
}

/**
 * Mutations acknowledge only. Returning a snapshot here too would race the
 * `broadcast` that already went out over the WebSocket: the two travel on
 * independent transports with no ordering between them, so a slow HTTP response
 * could land after — and overwrite — a newer push. The socket is the single
 * source of truth for state.
 */
function ackResponse(): Response {
  return new Response(null, { status: 204 });
}
