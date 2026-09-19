// worker/src/GameTable.ts

import type {
  DurableObject,
  DurableObjectState,
} from "@cloudflare/workers-types";
import type {
  AddSessionAspectInput,
  AddOrRemoveStoneInput,
  AspectName,
  EntityInput,
  EntityKind,
  Env,
  SessionAspect,
  GameState,
  Message,
  PostMessageInput,
  Proposal,
  ProposalDecisionInput,
  Role,
  SessionState,
  SessionSummary,
  StartSessionInput,
  StoneKind,
  TableEntity,
  CharacterSheet,
  UpdateCharacterInput,
  UpdateFateInput,
  UpdateSessionGoalInput,
  UseSessionBoonInput,
} from "./types";
import {
  characterLabel,
  clearSlotPendingState,
  describeStones,
  moveName,
  pairKind,
  pickTwoRandom,
  removeStones,
} from "./gameLogic";
import {
  type LegacyStoneState,
  type StoneState,
  migrateStoneState,
} from "./migrateStoneState";
import {
  type CharacterRow,
  rowToCharacterSheet,
  setFate,
  setOwner,
  updateFields,
} from "./characters";

// The shape the shared pool starts in, and returns to whenever an Overcome is
// accepted. Between accepts the pool only changes through moves and the
// facilitator's direct edits; a roll only ever reads it.
const INITIAL_STONE_POOL: readonly StoneKind[] = ["Boon", "Bane", "Boon", "Bane"];

const CHARACTER_SLOT_COUNT = 3;

/** Boons a player pays for a Highlight, on approval. */
const HIGHLIGHT_COST = 1;

/** Boons a player pays for an Add Detail, on approval. */
const ADD_DETAIL_COST = 1;

/** Boons a player pays for an Alter Fate, on approval. */
const ALTER_COST = 2;

/** Boons an approved Complicate pays the target character. The suggester gets none. */
const COMPLICATE_TARGET_BOONS = 2;

/** A crypto.randomUUID() shape, for the `/proposals/:id/…` and
 * `/{npcs,locations}/:id/…` route patterns. */
const UUID = "[0-9a-fA-F-]{36}";

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

  /**
   * The loaded game state. Every route runs after `ensureLoaded` in `fetch`, so
   * by the time a handler reads this it is always populated — this getter is the
   * one place that assertion lives, instead of ~85 `this.gameState!` sites.
   */
  private get game(): GameState {
    return this.gameState!;
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

    if (url.pathname === "/moves/highlight" && request.method === "POST") {
      return this.withLock(() => this.handleHighlight(authInfo));
    }

    const proposalMatch = url.pathname.match(
      new RegExp(`^/proposals/(${UUID})/(accept|reject|withdraw)$`),
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

    if (url.pathname === "/moves/alter" && request.method === "POST") {
      return this.withLock(() => this.handleAlter(authInfo));
    }

    if (url.pathname === "/moves/add-detail" && request.method === "POST") {
      return this.withLock(() => this.handleAddDetail(request, authInfo));
    }

    if (url.pathname === "/moves/complicate" && request.method === "POST") {
      return this.withLock(() => this.handleComplicate(request, authInfo));
    }

    if (url.pathname === "/moves/use-session-boon" && request.method === "POST") {
      return this.withLock(() => this.handleUseSessionBoon(request, authInfo));
    }

    if (url.pathname === "/overcome/roll" && request.method === "POST") {
      return this.withLock(() => this.handleOvercomeRoll(authInfo));
    }

    if (url.pathname === "/overcome/accept" && request.method === "POST") {
      return (
        facilitatorOnly(authInfo) ??
        this.withLock(() => this.handleOvercomeAccept(authInfo))
      );
    }

    if (url.pathname === "/overcome/reject" && request.method === "POST") {
      return (
        facilitatorOnly(authInfo) ??
        this.withLock(() => this.handleOvercomeReject(authInfo))
      );
    }

    if (url.pathname === "/overcome/reroll" && request.method === "POST") {
      return (
        facilitatorOnly(authInfo) ??
        this.withLock(() => this.handleOvercomeReroll(authInfo))
      );
    }

    if (url.pathname === "/stones/add" && request.method === "POST") {
      return (
        facilitatorOnly(authInfo) ??
        this.withLock(() => this.handleAddStone(request))
      );
    }

    if (url.pathname === "/stones/remove" && request.method === "POST") {
      return (
        facilitatorOnly(authInfo) ??
        this.withLock(() => this.handleRemoveStone(request))
      );
    }

    if (url.pathname === "/session-aspects" && request.method === "POST") {
      return (
        facilitatorOnly(authInfo) ??
        this.withLock(() => this.handleAddSessionAspect(request, authInfo))
      );
    }

    const sessionAspectMatch = url.pathname.match(
      new RegExp(`^/session-aspects/(${UUID})/(update|delete|use|unconsume)$`),
    );
    if (sessionAspectMatch && request.method === "POST") {
      const [, sessionAspectId, action] = sessionAspectMatch;
      return (
        facilitatorOnly(authInfo) ??
        this.withLock(() => {
          switch (action) {
            case "update":
              return this.handleUpdateSessionAspect(
                request,
                sessionAspectId,
              );
            case "use":
              return this.handleUseSessionAspect(sessionAspectId, authInfo);
            case "unconsume":
              return this.handleUnconsumeSessionAspect(
                sessionAspectId,
                authInfo,
              );
            default:
              return this.handleDeleteSessionAspect(
                sessionAspectId,
                authInfo,
              );
          }
        })
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
      new RegExp(`^/(npcs|locations)/(${UUID})/(update|delete)$`),
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

  /**
   * The trailer every mutating handler shares: install the new state, persist
   * the stone slice (a byte-identical slice is skipped, so this is cheap even on
   * a character- or entity-only change), append a log line if one was given,
   * broadcast, and return the 204 ack. A handler's own diff is then just the
   * `next` it builds.
   */
  private async commit(
    next: GameState,
    logLine?: AddMessageInput,
  ): Promise<Response> {
    this.gameState = next;
    await this.saveStoneState(next);
    if (logLine) {
      await this.appendMessage(logLine);
    }
    this.broadcast(this.game);
    return ackResponse();
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

    // These six reads are independent — different tables plus the KEY_STONES
    // blob — so they run concurrently. Meaningful on the Free-tier cold path.
    const [messageRows, characters, stones, sessionHistory, npcs, locations] =
      await Promise.all([
        this.env.DB.prepare(
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
          .all<Message>(),
        this.loadOrCreateCharacters(sessionId),
        this.loadStoneState(),
        this.loadSessionHistory(sessionId),
        this.loadEntities(sessionId, "npcs"),
        this.loadEntities(sessionId, "locations"),
      ]);

    const messages = messageRows.results
      ? [...messageRows.results].reverse()
      : [];

    this.gameState = {
      sessionId,
      messages,
      stonePool: stones.stonePool,
      overcome: stones.overcome,
      sessionAspects: stones.sessionAspects,
      proposals: stones.proposals,
      session: stones.session,
      sessionHistory,
      characters,
      npcs,
      locations,
    };

    // Seed the write-skip baseline so an unchanged stone slice is not
    // re-persisted on the first mutation after a cold start.
    this.lastSavedStones = JSON.stringify(this.stoneSlice(this.gameState));

    // Equal to `storedSessionId` by the guard above; every later request in this
    // object's lifetime compares against it instead of re-reading storage.
    return sessionId;
  }

  /**
   * The stone pool is the only state this Durable Object genuinely owns, so
   * it lives in its own storage. Keeping it in memory loses it every time the
   * DO hibernates, which is roughly ten seconds after a table goes quiet.
   */
  private async loadStoneState(): Promise<StoneState> {
    const stored = await this.state.storage.get<LegacyStoneState>(KEY_STONES);
    const migrated = migrateStoneState(stored, INITIAL_STONE_POOL);
    // A cold table writes the base blob once; a stored one is left as-is and
    // persisted by the first mutation that actually changes it.
    if (!stored) {
      await this.state.storage.put(KEY_STONES, migrated);
    }
    return migrated;
  }

  /**
   * The serialised `StoneState` as last written to storage. `saveStoneState`
   * compares against this and skips the `put` when nothing in the stone slice
   * actually changed — a plain chat post, for instance, runs through the same
   * mutation path but touches none of it.
   */
  private lastSavedStones: string | null = null;

  private stoneSlice(state: GameState): StoneState {
    return {
      stonePool: state.stonePool,
      overcome: state.overcome,
      sessionAspects: state.sessionAspects,
      proposals: state.proposals,
      session: state.session,
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
      SELECT id, goal, started_at AS startedAt, ended_at AS endedAt
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

    // No state of its own to change — `commit` just persists the message and
    // broadcasts.
    return this.commit(this.game, {
      authorId: authInfo.discordUserId,
      authorName: authInfo.username,
      role: authInfo.role,
      content,
    });
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
      .bind(this.game.sessionId)
      .run();

    return this.commit({ ...this.game, messages: [] });
  }

  /**
   * Highlight: the caller proposes to move one of their own boons into the
   * shared pool. It costs 1 boon, so it cannot be proposed without one; the
   * cost is paid only when the facilitator accepts.
   */
  private async handleHighlight(authInfo: AuthInfo): Promise<Response> {
    const character = this.game.characters.find(
      (c) => c.ownerId === authInfo.discordUserId,
    );
    if (!character) {
      return new Response("Claim a character sheet first", { status: 400 });
    }
    if (character.fate < HIGHLIGHT_COST) {
      return new Response("You need a boon to Highlight", { status: 400 });
    }

    return this.addProposal(
      {
        kind: "highlight",
        proposerId: authInfo.discordUserId,
        proposerName: authInfo.username,
        slot: character.slot,
      },
      authInfo,
      `${characterLabel(character)} proposes Highlight`,
    );
  }

  /**
   * Alter Fate: the caller proposes to pay boons to reroll the pending
   * Overcome. Only possible while one is pending (after at least one roll),
   * once per player per Overcome, and one proposal at a time. Costs
   * `ALTER_COST` boons, paid on approval; a rejection costs nothing and does
   * not use up the attempt.
   */
  private async handleAlter(authInfo: AuthInfo): Promise<Response> {
    const overcome = this.game.overcome;
    if (!overcome) {
      return new Response("Alter Fate needs a pending Overcome", {
        status: 409,
      });
    }
    const character = this.game.characters.find(
      (c) => c.ownerId === authInfo.discordUserId,
    );
    if (!character) {
      return new Response("Claim a character sheet first", { status: 400 });
    }
    if (character.fate < ALTER_COST) {
      return new Response("You need two boons to Alter Fate", { status: 400 });
    }
    if (overcome.alteredSlots.includes(character.slot)) {
      return new Response("You have already altered fate this Overcome", {
        status: 409,
      });
    }
    if (this.game.proposals.some((p) => p.kind === "alter")) {
      return new Response("An Alter Fate is already proposed", { status: 409 });
    }

    return this.addProposal(
      {
        kind: "alter",
        proposerId: authInfo.discordUserId,
        proposerName: authInfo.username,
        slot: character.slot,
      },
      authInfo,
      `${characterLabel(character)} proposes Alter Fate`,
    );
  }

  /**
   * Add Detail: the caller proposes to establish something true about the scene,
   * either suggesting the wording or leaving it for the facilitator. It costs 1
   * boon, paid on approval; an accepted one plants a session boon.
   */
  private async handleAddDetail(
    request: Request,
    authInfo: AuthInfo,
  ): Promise<Response> {
    const input = (await readJson(request)) as { text?: unknown } | null;
    const character = this.game.characters.find(
      (c) => c.ownerId === authInfo.discordUserId,
    );
    if (!character) {
      return new Response("Claim a character sheet first", { status: 400 });
    }
    if (character.fate < ADD_DETAIL_COST) {
      return new Response("You need a boon to Add Detail", { status: 400 });
    }
    const text = boundedString(input?.text, MAX_GOAL_LENGTH).trim() || null;

    return this.addProposal(
      {
        kind: "add-detail",
        proposerId: authInfo.discordUserId,
        proposerName: authInfo.username,
        slot: character.slot,
        text,
      },
      authInfo,
      `${characterLabel(character)} proposes Add Detail`,
    );
  }

  /**
   * Complicate: the caller suggests a way another character could do something
   * dangerous, destructive, or derailing. Free to propose; on approval the
   * target character's player gains `COMPLICATE_TARGET_BOONS` boons and the
   * suggester nothing.
   */
  private async handleComplicate(
    request: Request,
    authInfo: AuthInfo,
  ): Promise<Response> {
    const input = (await readJson(request)) as { targetSlot?: unknown } | null;
    const character = this.game.characters.find(
      (c) => c.ownerId === authInfo.discordUserId,
    );
    if (!character) {
      return new Response("Claim a character sheet first", { status: 400 });
    }

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
      return new Response("You cannot complicate your own character", {
        status: 400,
      });
    }
    const target = this.game.characters.find((c) => c.slot === raw);

    return this.addProposal(
      {
        kind: "complicate",
        proposerId: authInfo.discordUserId,
        proposerName: authInfo.username,
        slot: character.slot,
        targetSlot: raw,
      },
      authInfo,
      `${characterLabel(character)} proposes Complicate on ${
        target ? characterLabel(target) : `Character ${raw + 1}`
      }`,
    );
  }

  /**
   * Use Session Boon: the caller proposes to spend an unconsumed session boon.
   * It costs nothing; on approval the boon is marked consumed and a Boon
   * enters the pool. Session banes are the facilitator's to use directly, so a
   * player cannot propose one.
   */
  private async handleUseSessionBoon(
    request: Request,
    authInfo: AuthInfo,
  ): Promise<Response> {
    const input = (await readJson(request)) as UseSessionBoonInput | null;
    const sessionAspectId =
      typeof input?.sessionAspectId === "string" ? input.sessionAspectId : "";
    if (!sessionAspectId) {
      return new Response("sessionAspectId is required", { status: 400 });
    }

    const character = this.game.characters.find(
      (c) => c.ownerId === authInfo.discordUserId,
    );
    if (!character) {
      return new Response("Claim a character sheet first", { status: 400 });
    }
    const aspect = this.game.sessionAspects.find(
      (f) => f.id === sessionAspectId,
    );
    if (!aspect) {
      return new Response("No such session boon", { status: 404 });
    }
    if (aspect.kind !== "Boon") {
      return new Response("Only the facilitator can use a session bane", {
        status: 400,
      });
    }
    if (aspect.consumed) {
      return new Response("That session boon is already consumed", {
        status: 409,
      });
    }
    if (
      this.game.proposals.some(
        (p) =>
          p.kind === "use-session-boon" && p.sessionAspectId === sessionAspectId,
      )
    ) {
      return new Response("That session boon is already proposed", {
        status: 409,
      });
    }

    return this.addProposal(
      {
        kind: "use-session-boon",
        proposerId: authInfo.discordUserId,
        proposerName: authInfo.username,
        slot: character.slot,
        sessionAspectId,
      },
      authInfo,
      `${characterLabel(character)} proposes Use Session Boon`,
    );
  }

  private async addProposal(
    fields: Omit<
      Proposal,
      "id" | "createdAt" | "sessionAspectId" | "targetSlot" | "text"
    > & {
      sessionAspectId?: string | null;
      targetSlot?: number | null;
      text?: string | null;
    },
    authInfo?: AuthInfo,
    logLine?: string,
  ): Promise<Response> {
    const {
      sessionAspectId = null,
      targetSlot = null,
      text = null,
      ...rest
    } = fields;
    const proposal: Proposal = {
      ...rest,
      sessionAspectId,
      targetSlot,
      text,
      id: crypto.randomUUID(),
      createdAt: Date.now(),
    };
    return this.commit(
      { ...this.game, proposals: [...this.game.proposals, proposal] },
      authInfo && logLine ? authoredLine(authInfo, logLine) : undefined,
    );
  }

  /**
   * Facilitator resolves one proposal. Accept applies its effect (clamped to
   * current state); reject just drops it. Either way it leaves the queue. Some
   * accepts can still be refused — Alter Fate with no roll to affect, an
   * Add Detail / Gain Insight with no context note — in which case the
   * proposal stays put for another try.
   */
  private async handleProposalDecision(
    proposalId: string,
    decision: "accept" | "reject",
    authInfo: AuthInfo,
    request: Request,
  ): Promise<Response> {
    const proposal = this.game.proposals.find((p) => p.id === proposalId);
    if (!proposal) {
      return new Response("No such proposal", { status: 404 });
    }

    let state: GameState = {
      ...this.game,
      proposals: this.game.proposals.filter((p) => p.id !== proposalId),
    };
    let logLine = "";

    if (decision === "accept") {
      switch (proposal.kind) {
        case "highlight": {
          const proposerSheet =
            proposal.slot === null
              ? undefined
              : state.characters.find((c) => c.slot === proposal.slot);
          if (!proposerSheet) {
            return this.proposalTargetGone();
          }
          if (proposerSheet.fate < HIGHLIGHT_COST) {
            return this.notEnoughBoons();
          }
          state = {
            ...state,
            characters: await this.bumpFate(
              state.characters,
              proposerSheet.slot,
              -HIGHLIGHT_COST,
            ),
            stonePool: [...state.stonePool, "Boon"],
          };
          logLine = `Highlight accepted — ${characterLabel(
            proposerSheet,
          )} pays ${HIGHLIGHT_COST} boon, the pool gains a Boon`;
          break;
        }

        case "alter": {
          const overcome = state.overcome;
          if (!overcome) {
            return new Response("No Overcome is pending", { status: 409 });
          }
          const proposerSheet =
            proposal.slot === null
              ? undefined
              : state.characters.find((c) => c.slot === proposal.slot);
          if (!proposerSheet) {
            return this.proposalTargetGone();
          }
          if (proposerSheet.fate < ALTER_COST) {
            return this.notEnoughBoons();
          }
          const { chosen } = pickTwoRandom(state.stonePool);
          state = {
            ...state,
            characters: await this.bumpFate(
              state.characters,
              proposerSheet.slot,
              -ALTER_COST,
            ),
            overcome: {
              ...overcome,
              stones: chosen,
              rerolls: overcome.rerolls + 1,
              alteredSlots: [...overcome.alteredSlots, proposerSheet.slot],
            },
          };
          logLine = `Alter Fate accepted — ${characterLabel(
            proposerSheet,
          )} pays ${ALTER_COST} boons, rerolled: ${describeStones(chosen)}`;
          break;
        }

        case "add-detail": {
          const proposerSheet =
            proposal.slot === null
              ? undefined
              : state.characters.find((c) => c.slot === proposal.slot);
          if (!proposerSheet) {
            return this.proposalTargetGone();
          }
          if (proposerSheet.fate < ADD_DETAIL_COST) {
            return this.notEnoughBoons();
          }
          // The facilitator's field arrives pre-filled with the player's
          // suggestion and stays editable; blank falls back, then to a default.
          const body = (await readJson(request)) as ProposalDecisionInput | null;
          const text =
            boundedString(body?.text, MAX_GOAL_LENGTH).trim() ||
            proposal.text ||
            `Detail from ${proposal.proposerName}`;
          const aspect: SessionAspect = {
            id: crypto.randomUUID(),
            kind: "Boon",
            text,
            createdByName: proposal.proposerName,
            createdAt: Date.now(),
            consumed: false,
          };
          state = {
            ...state,
            characters: await this.bumpFate(
              state.characters,
              proposerSheet.slot,
              -ADD_DETAIL_COST,
            ),
            sessionAspects: [...state.sessionAspects, aspect],
          };
          logLine = `Add Detail accepted — ${characterLabel(
            proposerSheet,
          )} pays ${ADD_DETAIL_COST} boon: ${text}`;
          break;
        }

        case "complicate": {
          const suggester =
            proposal.slot === null
              ? undefined
              : state.characters.find((c) => c.slot === proposal.slot);
          const target =
            proposal.targetSlot === null
              ? undefined
              : state.characters.find((c) => c.slot === proposal.targetSlot);
          if (!suggester || !target) {
            return this.proposalTargetGone();
          }
          state = {
            ...state,
            characters: await this.bumpFate(
              state.characters,
              target.slot,
              COMPLICATE_TARGET_BOONS,
            ),
          };
          logLine = `Complicate accepted — ${characterLabel(
            target,
          )} gains ${COMPLICATE_TARGET_BOONS} boons (suggested by ${characterLabel(
            suggester,
          )})`;
          break;
        }

        case "use-session-boon": {
          const aspect = state.sessionAspects.find(
            (f) => f.id === proposal.sessionAspectId,
          );
          const proposerSheet =
            proposal.slot === null
              ? undefined
              : state.characters.find((c) => c.slot === proposal.slot);
          if (!aspect || !proposerSheet) {
            return this.proposalTargetGone();
          }
          if (aspect.consumed) {
            return new Response("That session boon is already consumed", {
              status: 409,
            });
          }
          state = {
            ...state,
            stonePool: [...state.stonePool, "Boon"],
            sessionAspects: state.sessionAspects.map((f) =>
              f.id === aspect.id ? { ...f, consumed: true } : f,
            ),
          };
          logLine = `Use Session Boon accepted — ${characterLabel(
            proposerSheet,
          )} spends ${aspect.text}; the pool gains a Boon`;
          break;
        }
      }
    }

    if (decision === "reject") {
      const proposerSheet =
        proposal.slot === null
          ? undefined
          : state.characters.find((c) => c.slot === proposal.slot);
      logLine = `${moveName(proposal.kind)} rejected — ${
        proposerSheet ? characterLabel(proposerSheet) : proposal.proposerName
      }`;
    }

    return this.commit(state, logLine ? authoredLine(authInfo, logLine) : undefined);
  }

  /** An accepted proposal the proposer can no longer pay for. It stays queued. */
  private notEnoughBoons(): Response {
    return new Response("Not enough boons to pay for that move", {
      status: 409,
    });
  }

  /**
   * An accepted proposal whose character / session aspect has since gone (a
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
    const proposal = this.game.proposals.find((p) => p.id === proposalId);
    if (!proposal) {
      return new Response("No such proposal", { status: 404 });
    }
    if (proposal.proposerId !== authInfo.discordUserId) {
      return new Response("Not your proposal", { status: 403 });
    }

    return this.commit(
      {
        ...this.game,
        proposals: this.game.proposals.filter((p) => p.id !== proposalId),
      },
      {
        authorId: authInfo.discordUserId,
        authorName: authInfo.username,
        role: authInfo.role,
        content: `${proposal.proposerName} withdrew a proposal`,
      },
    );
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
    await setFate(this.env.DB, character.id, fate, Date.now());
    return characters.map((c) => (c.slot === slot ? { ...c, fate } : c));
  }

  /**
   * Overcome (26.2): any player presses it, no approval needed. Draws two
   * stones from the pool without touching the pool, and leaves the result
   * pending until the facilitator accepts or rejects it. One at a time.
   */
  private async handleOvercomeRoll(authInfo: AuthInfo): Promise<Response> {
    if (this.game.overcome) {
      return new Response("An Overcome is already pending", { status: 409 });
    }

    const { chosen } = pickTwoRandom(this.game.stonePool);
    return this.commit(
      {
        ...this.game,
        overcome: {
          rolledBy: authInfo.username,
          stones: chosen,
          rerolls: 0,
          alteredSlots: [],
        },
      },
      {
        authorId: authInfo.discordUserId,
        authorName: authInfo.username,
        role: authInfo.role,
        content: `Overcome — ${authInfo.username} rolled: ${describeStones(chosen)}`,
      },
    );
  }

  /**
   * The facilitator accepts the pending Overcome. The pool returns to its
   * starting shape whatever was added to it, and a matched pair plants a
   * session boon (two Boons) or session bane (two Banes) for the facilitator to
   * word later; a mixed draw plants nothing.
   */
  private async handleOvercomeAccept(authInfo: AuthInfo): Promise<Response> {
    const overcome = this.game.overcome;
    if (!overcome) {
      return new Response("No Overcome is pending", { status: 409 });
    }

    const kind = pairKind(overcome.stones);
    const sessionAspects = kind
      ? [
          ...this.game.sessionAspects,
          {
            id: crypto.randomUUID(),
            kind,
            text: `${kind} from ${overcome.rolledBy}'s Overcome`,
            createdByName: overcome.rolledBy,
            createdAt: Date.now(),
            consumed: false,
          },
        ]
      : this.game.sessionAspects;
    const added = kind ? ` (session ${kind.toLowerCase()} added)` : "";

    return this.commit(
      {
        ...this.game,
        overcome: null,
        // A queued Alter Fate is only meaningful during the Overcome it was
        // raised for.
        proposals: this.game.proposals.filter((p) => p.kind !== "alter"),
        stonePool: [...INITIAL_STONE_POOL],
        sessionAspects,
      },
      {
        authorId: authInfo.discordUserId,
        authorName: authInfo.username,
        role: authInfo.role,
        content: `Overcome accepted — ${describeStones(overcome.stones)}${added}`,
      },
    );
  }

  /**
   * The facilitator rejects the pending Overcome: the roll is discarded and
   * nothing else changes — the pool keeps whatever was added to it, and no
   * session aspect is created — so the table can roll again.
   */
  private async handleOvercomeReject(authInfo: AuthInfo): Promise<Response> {
    if (!this.game.overcome) {
      return new Response("No Overcome is pending", { status: 409 });
    }

    return this.commit(
      {
        ...this.game,
        overcome: null,
        proposals: this.game.proposals.filter((p) => p.kind !== "alter"),
      },
      {
        authorId: authInfo.discordUserId,
        authorName: authInfo.username,
        role: authInfo.role,
        content: "Overcome rejected — the roll is discarded",
      },
    );
  }

  /**
   * The facilitator's own reroll of the pending Overcome: free and immediate,
   * with no proposal. Players reroll only through Alter Fate.
   */
  private async handleOvercomeReroll(authInfo: AuthInfo): Promise<Response> {
    const overcome = this.game.overcome;
    if (!overcome) {
      return new Response("No Overcome is pending", { status: 409 });
    }

    const { chosen } = pickTwoRandom(this.game.stonePool);
    return this.commit(
      {
        ...this.game,
        overcome: { ...overcome, stones: chosen, rerolls: overcome.rerolls + 1 },
      },
      {
        authorId: authInfo.discordUserId,
        authorName: authInfo.username,
        role: authInfo.role,
        content: `Reroll — ${describeStones(chosen)}`,
      },
    );
  }

  /**
   * Facilitator-only (23.2): add one stone directly to the shared pool, no
   * proposal needed. Independent of a draw and of every other free-standing
   * resource action — the interface makes no attempt to link this to
   * anything. Silent like the facilitator's direct `add-boon`: a hand-edit to
   * the pool, not a narrated table event.
   */
  private async handleAddStone(request: Request): Promise<Response> {
    const input = (await readJson(request)) as AddOrRemoveStoneInput | null;
    const kind = input?.kind;
    if (kind !== "Boon" && kind !== "Bane") {
      return new Response("kind must be Boon or Bane", { status: 400 });
    }

    return this.commit({
      ...this.game,
      stonePool: [...this.game.stonePool, kind],
    });
  }

  /**
   * Facilitator-only (23.2): remove one stone of `kind` directly from the
   * shared pool. 400s when the pool holds none of that kind, rather than
   * silently broadcasting a pool that never actually changed.
   */
  private async handleRemoveStone(request: Request): Promise<Response> {
    const input = (await readJson(request)) as AddOrRemoveStoneInput | null;
    const kind = input?.kind;
    if (kind !== "Boon" && kind !== "Bane") {
      return new Response("kind must be Boon or Bane", { status: 400 });
    }
    if (!this.game.stonePool.includes(kind)) {
      return new Response(`The pool has no ${kind} to remove`, {
        status: 400,
      });
    }

    return this.commit({
      ...this.game,
      stonePool: removeStones(this.game.stonePool, [kind]),
    });
  }

  /**
   * Facilitator-only (23.2, widened 23.3): plant a session context directly —
   * Boon or Bane, the facilitator's choice — the same shape an accepted Add
   * a Detail / Gain Insight creates (always a Boon), without routing through
   * that ability's proposal.
   */
  private async handleAddSessionAspect(
    request: Request,
    authInfo: AuthInfo,
  ): Promise<Response> {
    const input = (await readJson(request)) as AddSessionAspectInput | null;
    const kind = input?.kind;
    if (kind !== "Boon" && kind !== "Bane") {
      return new Response("kind must be Boon or Bane", { status: 400 });
    }
    const text = boundedString(input?.text, MAX_GOAL_LENGTH).trim();
    if (!text) {
      return new Response("text is required", { status: 400 });
    }

    const aspect: SessionAspect = {
      id: crypto.randomUUID(),
      kind,
      text,
      createdByName: authInfo.username,
      createdAt: Date.now(),
      consumed: false,
    };

    return this.commit(
      { ...this.game, sessionAspects: [...this.game.sessionAspects, aspect] },
      {
        authorId: authInfo.discordUserId,
        authorName: authInfo.username,
        role: authInfo.role,
        content: `Session note added (${kind}) — ${text}`,
      },
    );
  }

  /** Facilitator-only: rewrite one session aspect's text. Silent, like a typo fix. */
  private async handleUpdateSessionAspect(
    request: Request,
    sessionAspectId: string,
  ): Promise<Response> {
    const aspect = this.game.sessionAspects.find((f) => f.id === sessionAspectId);
    if (!aspect) {
      return new Response("No such session boon", { status: 404 });
    }
    const input = (await readJson(request)) as { text?: unknown } | null;
    const text = boundedString(input?.text, MAX_GOAL_LENGTH).trim();
    if (!text) {
      return new Response("text is required", { status: 400 });
    }

    return this.commit({
      ...this.game,
      sessionAspects: this.game.sessionAspects.map((f) =>
        f.id === sessionAspectId ? { ...f, text } : f,
      ),
    });
  }

  /**
   * Facilitator-only: spend a session aspect into the pool directly, no
   * approval. The pool gains a stone of the aspect's kind and the aspect is
   * marked consumed — kept, visibly, so it cannot be spent twice.
   */
  private async handleUseSessionAspect(
    sessionAspectId: string,
    authInfo: AuthInfo,
  ): Promise<Response> {
    const aspect = this.game.sessionAspects.find((f) => f.id === sessionAspectId);
    if (!aspect) {
      return new Response("No such session boon", { status: 404 });
    }
    if (aspect.consumed) {
      return new Response("That session boon is already consumed", {
        status: 409,
      });
    }

    return this.commit(
      {
        ...this.game,
        stonePool: [...this.game.stonePool, aspect.kind],
        sessionAspects: this.game.sessionAspects.map((f) =>
          f.id === sessionAspectId ? { ...f, consumed: true } : f,
        ),
      },
      {
        authorId: authInfo.discordUserId,
        authorName: authInfo.username,
        role: authInfo.role,
        content: `Session ${aspect.kind.toLowerCase()} used — ${aspect.text}`,
      },
    );
  }

  /**
   * Facilitator-only: clear a consumed mark. A correction for a table
   * miscommunication (a stone was spent that should not have been), not part of
   * the game — so it does not touch the pool.
   */
  private async handleUnconsumeSessionAspect(
    sessionAspectId: string,
    authInfo: AuthInfo,
  ): Promise<Response> {
    const aspect = this.game.sessionAspects.find((f) => f.id === sessionAspectId);
    if (!aspect) {
      return new Response("No such session boon", { status: 404 });
    }
    if (!aspect.consumed) {
      return new Response("That session boon is not consumed", { status: 409 });
    }

    return this.commit(
      {
        ...this.game,
        sessionAspects: this.game.sessionAspects.map((f) =>
          f.id === sessionAspectId ? { ...f, consumed: false } : f,
        ),
      },
      {
        authorId: authInfo.discordUserId,
        authorName: authInfo.username,
        role: authInfo.role,
        content: `Session ${aspect.kind.toLowerCase()} unconsumed — ${aspect.text}`,
      },
    );
  }

  /**
   * Facilitator-only (23.2): remove a session context outright. There is no
   * "use" state distinct from this now that a roll no longer draws from
   * anything but the pool (23.1) — the lifecycle is just create and delete.
   */
  private async handleDeleteSessionAspect(
    sessionAspectId: string,
    authInfo: AuthInfo,
  ): Promise<Response> {
    const aspect = this.game.sessionAspects.find((f) => f.id === sessionAspectId);
    if (!aspect) {
      return new Response("No such session boon", { status: 404 });
    }

    return this.commit(
      {
        ...this.game,
        sessionAspects: this.game.sessionAspects.filter(
          (f) => f.id !== sessionAspectId,
        ),
      },
      {
        authorId: authInfo.discordUserId,
        authorName: authInfo.username,
        role: authInfo.role,
        content: `Session note removed (${aspect.kind}) — ${aspect.text}`,
      },
    );
  }

  private async handleStartSession(
    request: Request,
    authInfo: AuthInfo,
  ): Promise<Response> {
    if (this.game.session) {
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
      .bind(id, this.game.sessionId, goal, Date.now())
      .run();

    // Starting a session records the goal and nothing else: the pool,
    // proposals, session boons and banes, and any pending Overcome all carry
    // across (RULES.md, "Sessions and the goal").
    return this.commit(
      { ...this.game, session: { id, goal } },
      {
        authorId: authInfo.discordUserId,
        authorName: authInfo.username,
        role: authInfo.role,
        content: `Session started — ${goal}`,
      },
    );
  }

  private async handleEndSession(authInfo: AuthInfo): Promise<Response> {
    const session = this.game.session;
    if (!session) {
      return new Response("No session is running", { status: 400 });
    }

    // Ending a session records it in the history and nothing else. The goal is
    // just text: nothing is rolled, judged, topped up, or cleared.
    await this.env.DB.prepare(
      `UPDATE game_sessions SET ended_at = ? WHERE id = ?`,
    )
      .bind(Date.now(), session.id)
      .run();

    const sessionHistory = await this.loadSessionHistory(
      this.game.sessionId,
    );
    return this.commit(
      { ...this.game, session: null, sessionHistory },
      {
        authorId: authInfo.discordUserId,
        authorName: authInfo.username,
        role: authInfo.role,
        content: `Session ended — ${session.goal}`,
      },
    );
  }

  /** Facilitator rewrites the running session's goal. */
  private async handleUpdateSessionGoal(
    request: Request,
    authInfo: AuthInfo,
  ): Promise<Response> {
    const session = this.game.session;
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

    return this.commit(
      { ...this.game, session: { ...session, goal } },
      {
        authorId: authInfo.discordUserId,
        authorName: authInfo.username,
        role: authInfo.role,
        content: `Goal updated — ${goal}`,
      },
    );
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

    const character = this.game.characters.find((c) => c.slot === slot);
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

    await updateFields(this.env.DB, updated, Date.now());

    return this.commit({
      ...this.game,
      characters: this.game.characters.map((c) =>
        c.slot === slot ? updated : c,
      ),
    });
  }

  /**
   * Bind the calling user to a sheet. Fails if someone else holds it; releases
   * any other sheet the caller already holds so a player owns at most one.
   */
  private async handleClaimSlot(
    slot: number,
    authInfo: AuthInfo,
  ): Promise<Response> {
    const target = this.game.characters.find((c) => c.slot === slot);
    if (!target) {
      return new Response("Not found", { status: 404 });
    }
    if (target.ownerId && target.ownerId !== authInfo.discordUserId) {
      return new Response("Sheet already claimed", { status: 409 });
    }
    // Re-claiming a sheet the caller already holds is a no-op — don't wipe that
    // slot's own highlights / proposals.
    if (target.ownerId === authInfo.discordUserId) {
      return ackResponse();
    }

    const now = Date.now();
    const priorSlots = this.game.characters.filter(
      (c) => c.ownerId === authInfo.discordUserId && c.slot !== slot,
    );
    for (const prior of priorSlots) {
      await this.setSheetOwner(prior.id, null, now);
    }
    await this.setSheetOwner(target.id, authInfo.discordUserId, now);

    let next: GameState = {
      ...this.game,
      characters: this.game.characters.map((c) => {
        if (c.slot === slot) return { ...c, ownerId: authInfo.discordUserId };
        if (priorSlots.some((p) => p.id === c.id)) return { ...c, ownerId: null };
        return c;
      }),
    };
    // Any sheet whose owner just changed — the one just claimed, and any the
    // caller was released from to take it — must not keep highlights or proposals
    // aimed at whoever held it before.
    for (const changed of [slot, ...priorSlots.map((p) => p.slot)]) {
      next = clearSlotPendingState(next, changed);
    }
    return this.commit(next);
  }

  /** Release a sheet. Allowed for the sheet's owner or the facilitator. */
  private async handleReleaseSlot(
    slot: number,
    authInfo: AuthInfo,
  ): Promise<Response> {
    const target = this.game.characters.find((c) => c.slot === slot);
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
    return this.commit(
      clearSlotPendingState(
        {
          ...this.game,
          characters: this.game.characters.map((c) =>
            c.slot === slot ? { ...c, ownerId: null } : c,
          ),
        },
        slot,
      ),
    );
  }

  private setSheetOwner(
    id: string,
    ownerId: string | null,
    now: number,
  ): Promise<void> {
    return setOwner(this.env.DB, id, ownerId, now);
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

    const character = this.game.characters.find((c) => c.slot === slot);
    if (!character) {
      return new Response("Not found", { status: 404 });
    }

    const fate = Math.max(0, character.fate + delta);

    await setFate(this.env.DB, character.id, fate, Date.now());

    return this.commit({
      ...this.game,
      characters: this.game.characters.map((c) =>
        c.slot === slot ? { ...c, fate } : c,
      ),
    });
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
        this.game.sessionId,
        entity.name,
        entity.notes,
        now,
        now,
      )
      .run();

    return this.commit({ ...this.game, [kind]: [...this.game[kind], entity] });
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

    const entity = this.game[kind].find((e) => e.id === id);
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

    return this.commit({
      ...this.game,
      [kind]: this.game[kind].map((e) => (e.id === id ? updated : e)),
    });
  }

  private async handleDeleteEntity(
    kind: EntityKind,
    id: string,
  ): Promise<Response> {
    if (!this.game[kind].some((e) => e.id === id)) {
      return new Response("Not found", { status: 404 });
    }

    await this.env.DB.prepare(
      `DELETE FROM ${entityTable(kind)} WHERE id = ?`,
    )
      .bind(id)
      .run();

    return this.commit({
      ...this.game,
      [kind]: this.game[kind].filter((e) => e.id !== id),
    });
  }

  /** Persists the message, then folds it into the current in-memory state. */
  private async appendMessage(input: AddMessageInput): Promise<void> {
    const msg: Message = {
      id: crypto.randomUUID(),
      sessionId: this.game.sessionId,
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
      ...this.game,
      messages: capMessages([...this.game.messages, msg]),
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

/**
 * The D1 table backing an entity kind. An explicit allowlist so the name is
 * never anything but one of these two literals when it reaches a SQL string.
 */
function entityTable(kind: EntityKind): "npcs" | "locations" {
  return kind === "npcs" ? "npcs" : "locations";
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
/** A message-log entry authored by `authInfo`, for `commit`'s log line. */
function authoredLine(authInfo: AuthInfo, content: string): AddMessageInput {
  return {
    authorId: authInfo.discordUserId,
    authorName: authInfo.username,
    role: authInfo.role,
    content,
  };
}

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
