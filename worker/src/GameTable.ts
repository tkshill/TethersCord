// worker/src/GameTable.ts

import type {
  DurableObject,
  DurableObjectState,
} from "@cloudflare/workers-types";
import type {
  AddOrRemoveStoneInput,
  CharacterSheet,
  CharacterSheetFields,
  ContextAspect,
  EntityKind,
  Env,
  GameState,
  Message,
  MessageKind,
  Proposal,
  ProposalDecisionInput,
  Role,
  SessionSummary,
  StoneKind,
  TableEntity,
  UseContextBoonInput,
} from "./types";
import {
  characterLabel,
  describeStones,
  moveName,
  pairKind,
  pickTwoRandom,
  randomInt,
  removeStones,
} from "./gameLogic";
import {
  type LegacyTableState,
  type TableState,
  migrateTableState,
} from "./migrateTableState";
import {
  type CharacterRow,
  rowToCharacterSheet,
  setFate,
} from "./characters";
import { entityTable, persistDiff, toStatements } from "./persist";
import {
  type Command,
  type CommandBody,
  type Deps,
  type LogEntry,
  logText,
  SESSION_HISTORY_LIMIT,
  transition,
} from "./rules";

// The shape the shared pool starts in, and returns to whenever a Junction is
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

/** Boons an approved Complicate pays the proposer's character. */
const COMPLICATE_BOONS = 2;

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
// The table-state blob. The key string predates the rename and stays, since
// changing it would orphan every stored blob for no gain.
const KEY_TABLE_STATE = "stones";

/**
 * How long a resolved token → `AuthInfo` is trusted from memory before the
 * `sessions_auth` ⋈ `facilitators` query runs again. Bounds how stale a role
 * change (or an expiry that lands mid-window) can be to this many milliseconds,
 * in exchange for one D1 read per token per minute instead of per request.
 */
const AUTH_CACHE_TTL_MS = 60_000;

/** The world the rules core runs against in production. */
const PRODUCTION_DEPS: Deps = {
  roll: (sides) => randomInt(sides) + 1,
  now: () => Date.now(),
  newId: () => crypto.randomUUID(),
};

/**
 * A mutation route handled by the rules core: the path, and how its match and
 * JSON body become a command. Parsing bounds strings and coerces types but
 * never refuses; `transition` does every check, in order.
 */
type CommandRoute = {
  path: RegExp;
  parse: (match: RegExpMatchArray, body: Body) => CommandBody;
};

type Body = Record<string, unknown> | null;

const SLOT = "(\\d+)";
const ENTITY_KIND = "(npcs|locations)";

const COMMAND_ROUTES: CommandRoute[] = [
  {
    path: /^\/message$/,
    parse: (_, body) => ({
      type: "chat/post",
      content: boundedString(body?.content, MAX_MESSAGE_LENGTH),
    }),
  },
  { path: /^\/messages\/clear$/, parse: () => ({ type: "log/clear" }) },
  {
    path: /^\/session\/start$/,
    parse: (_, body) => ({
      type: "session/start",
      goal: boundedString(body?.goal, MAX_GOAL_LENGTH),
    }),
  },
  { path: /^\/session\/end$/, parse: () => ({ type: "session/end" }) },
  {
    path: /^\/session\/goal$/,
    parse: (_, body) => ({
      type: "session/goal",
      goal: boundedString(body?.goal, MAX_GOAL_LENGTH),
    }),
  },
  {
    path: new RegExp(`^/characters/${SLOT}/update$`),
    parse: ([, slot], body) => ({
      type: "sheet/update",
      slot: Number(slot),
      fields: body && sheetFields(body),
    }),
  },
  {
    path: new RegExp(`^/characters/${SLOT}/fate$`),
    parse: ([, slot], body) => ({
      type: "sheet/boons",
      slot: Number(slot),
      delta: typeof body?.delta === "number" ? body.delta : null,
    }),
  },
  {
    path: new RegExp(`^/characters/${SLOT}/claim$`),
    parse: ([, slot]) => ({ type: "sheet/claim", slot: Number(slot) }),
  },
  {
    path: new RegExp(`^/characters/${SLOT}/release$`),
    parse: ([, slot]) => ({ type: "sheet/release", slot: Number(slot) }),
  },
  {
    path: new RegExp(`^/${ENTITY_KIND}$`),
    parse: ([, kind], body) => ({
      type: "entity/create",
      kind: kind as EntityKind,
      name: boundedString(body?.name, MAX_FIELD_LENGTH),
      notes: boundedString(body?.notes, MAX_NOTES_LENGTH),
    }),
  },
  {
    path: new RegExp(`^/${ENTITY_KIND}/(${UUID})/update$`),
    parse: ([, kind, id], body) => ({
      type: "entity/update",
      kind: kind as EntityKind,
      id,
      fields: body && {
        ...stringField(body, "name", MAX_FIELD_LENGTH),
        ...stringField(body, "notes", MAX_NOTES_LENGTH),
      },
    }),
  },
  {
    path: new RegExp(`^/${ENTITY_KIND}/(${UUID})/delete$`),
    parse: ([, kind, id]) => ({
      type: "entity/delete",
      kind: kind as EntityKind,
      id,
    }),
  },
  {
    path: /^\/context-aspects$/,
    parse: (_, body) => ({
      type: "context/add",
      kind: body?.kind === "Boon" || body?.kind === "Bane" ? body.kind : null,
      text: boundedString(body?.text, MAX_GOAL_LENGTH),
    }),
  },
  {
    path: new RegExp(`^/context-aspects/(${UUID})/update$`),
    parse: ([, id], body) => ({
      type: "context/update",
      id,
      text: boundedString(body?.text, MAX_GOAL_LENGTH),
    }),
  },
  {
    path: new RegExp(`^/context-aspects/(${UUID})/delete$`),
    parse: ([, id]) => ({ type: "context/delete", id }),
  },
];

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

  /** What the rules core may call: randomness, the clock, new ids. */
  private deps: Deps = PRODUCTION_DEPS;

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

    if (request.method === "POST") {
      for (const route of COMMAND_ROUTES) {
        const match = url.pathname.match(route.path);
        if (!match) continue;
        const command = route.parse(match, await readJson(request));
        return this.withLock(() => this.apply(command, authInfo));
      }
    }

    // The routes below still run on the legacy `commit` path. 31.2b moves the
    // Junction and the pool into the rules core; 31.3 deletes the proposals.

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
      return this.withLock(() => this.handleComplicate(authInfo));
    }

    if (url.pathname === "/moves/use-context-boon" && request.method === "POST") {
      return this.withLock(() => this.handleUseContextBoon(request, authInfo));
    }

    if (url.pathname === "/junction/roll" && request.method === "POST") {
      return this.withLock(() => this.handleJunctionRoll(authInfo));
    }

    if (url.pathname === "/junction/accept" && request.method === "POST") {
      return (
        facilitatorOnly(authInfo) ??
        this.withLock(() => this.handleJunctionAccept(authInfo))
      );
    }

    if (url.pathname === "/junction/reject" && request.method === "POST") {
      return (
        facilitatorOnly(authInfo) ??
        this.withLock(() => this.handleJunctionReject(authInfo))
      );
    }

    if (url.pathname === "/junction/reroll" && request.method === "POST") {
      return (
        facilitatorOnly(authInfo) ??
        this.withLock(() => this.handleJunctionReroll(authInfo))
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

    const contextAspectMatch = url.pathname.match(
      new RegExp(`^/context-aspects/(${UUID})/(use|unconsume)$`),
    );
    if (contextAspectMatch && request.method === "POST") {
      const [, contextAspectId, action] = contextAspectMatch;
      return (
        facilitatorOnly(authInfo) ??
        this.withLock(() =>
          action === "use"
            ? this.handleUseContextAspect(contextAspectId, authInfo)
            : this.handleUnconsumeContextAspect(contextAspectId, authInfo),
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

  /**
   * Run one command through the rules core and persist the result (ADR 0003).
   * Every D1 row the change implies is written in one `DB.batch` first, so a
   * failure there leaves nothing changed. Installing the next state, putting
   * the table-state slice and broadcasting then happen with no `await` between
   * them: the output gate holds the broadcast until the put is durable.
   */
  private async apply(body: CommandBody, authInfo: AuthInfo): Promise<Response> {
    const command = {
      ...body,
      by: {
        userId: authInfo.discordUserId,
        name: authInfo.username,
        role: authInfo.role,
      },
    } as Command;
    const { messages, ...table } = this.game;

    const result = transition(table, command, this.deps);
    if (!result.ok) {
      return new Response(result.reason, { status: result.status });
    }
    if (result.next === table && result.log.length === 0 && !result.clearLog) {
      return ackResponse();
    }

    const added = result.log.map((e) => toMessage(e, table.sessionId));
    const writes = persistDiff(table, result.next, added, result.clearLog);
    if (writes.length > 0) {
      await this.env.DB.batch(
        toStatements(this.env.DB, table.sessionId, writes, this.deps.now()),
      );
    }

    const next: GameState = {
      ...result.next,
      messages: capMessages([...(result.clearLog ? [] : messages), ...added]),
    };
    this.gameState = next;
    const saved = this.saveTableState(next);
    this.broadcast(next);
    await saved;
    return ackResponse();
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
   * the table-state slice (a byte-identical slice is skipped, so this is cheap even on
   * a character- or entity-only change), append a log line if one was given,
   * broadcast, and return the 204 ack. A handler's own diff is then just the
   * `next` it builds.
   */
  private async commit(
    next: GameState,
    logLine?: AddMessageInput,
  ): Promise<Response> {
    this.gameState = next;
    await this.saveTableState(next);
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

    // These six reads are independent — different tables plus the KEY_TABLE_STATE
    // blob — so they run concurrently. Meaningful on the Free-tier cold path.
    const [messageRows, characters, stones, sessionHistory, npcs, locations] =
      await Promise.all([
        this.env.DB.prepare(
          `
          SELECT id, session_id AS sessionId, author_id AS authorId,
                 author_name AS authorName, role, kind, content, created_at AS createdAt
          FROM messages
          WHERE session_id = ?
          ORDER BY created_at DESC, id DESC
          LIMIT ?
        `,
        )
          .bind(sessionId, MESSAGE_WINDOW)
          .all<Message>(),
        this.loadOrCreateCharacters(sessionId),
        this.loadTableState(),
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
      junction: stones.junction,
      contextAspects: stones.contextAspects,
      proposals: stones.proposals,
      session: await this.backfillSessionStart(stones.session),
      sessionHistory,
      characters,
      npcs,
      locations,
    };

    // Seed the write-skip baseline so an unchanged table-state slice is not
    // re-persisted on the first mutation after a cold start.
    this.lastSavedTableState = JSON.stringify(this.tableSlice(this.gameState));

    // Equal to `storedSessionId` by the guard above; every later request in this
    // object's lifetime compares against it instead of re-reading storage.
    return sessionId;
  }

  /**
   * The stone pool is the only state this Durable Object genuinely owns, so
   * it lives in its own storage. Keeping it in memory loses it every time the
   * DO hibernates, which is roughly ten seconds after a table goes quiet.
   */
  private async loadTableState(): Promise<TableState> {
    const stored = await this.state.storage.get<LegacyTableState>(KEY_TABLE_STATE);
    const migrated = migrateTableState(stored, INITIAL_STONE_POOL);
    // A cold table writes the base blob once; a stored one is left as-is and
    // persisted by the first mutation that actually changes it.
    if (!stored) {
      await this.state.storage.put(KEY_TABLE_STATE, migrated);
    }
    return migrated;
  }

  /**
   * The serialised `TableState` as last written to storage. `saveTableState`
   * compares against this and skips the `put` when nothing in the table-state slice
   * actually changed — a plain chat post, for instance, runs through the same
   * mutation path but touches none of it.
   */
  private lastSavedTableState: string | null = null;

  private tableSlice(state: GameState): TableState {
    return {
      stonePool: state.stonePool,
      junction: state.junction,
      contextAspects: state.contextAspects,
      proposals: state.proposals,
      session: state.session,
    };
  }

  private async saveTableState(state: GameState): Promise<void> {
    const slice = this.tableSlice(state);

    const serialised = JSON.stringify(slice);
    if (serialised === this.lastSavedTableState) {
      return;
    }

    await this.state.storage.put(KEY_TABLE_STATE, slice);
    this.lastSavedTableState = serialised;
  }

  /**
   * A session running since before 31.2a was stored without `startedAt`
   * (`migrateTableState` gives it 0); read it from its `game_sessions` row
   * once, so ending it can add it to the history from memory.
   */
  private async backfillSessionStart(
    session: TableState["session"],
  ): Promise<TableState["session"]> {
    if (!session || session.startedAt !== 0) return session;
    const row = await this.env.DB.prepare(
      `SELECT started_at AS startedAt FROM game_sessions WHERE id = ?`,
    )
      .bind(session.id)
      .first<{ startedAt: number }>();
    return { ...session, startedAt: row?.startedAt ?? 0 };
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
      LIMIT ?
    `,
    )
      .bind(sessionId, SESSION_HISTORY_LIMIT)
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
             author_name AS authorName, role, kind, content, created_at AS createdAt
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
   * Junction. Only possible while one is pending (after at least one roll),
   * once per player per Junction, and one proposal at a time. Costs
   * `ALTER_COST` boons, paid on approval; a rejection costs nothing and does
   * not use up the attempt.
   */
  private async handleAlter(authInfo: AuthInfo): Promise<Response> {
    const junction = this.game.junction;
    if (!junction) {
      return new Response("Alter Fate needs a pending Junction", {
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
    if (junction.alteredSlots.includes(character.slot)) {
      return new Response("You have already altered fate this Junction", {
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
   * boon, paid on approval; an accepted one plants a context boon.
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
   * Complicate: the caller suggests a way their own character could do
   * something dangerous, destructive, or derailing. Free to propose; on
   * approval the caller's character gains `COMPLICATE_BOONS` boons.
   */
  private async handleComplicate(authInfo: AuthInfo): Promise<Response> {
    const character = this.game.characters.find(
      (c) => c.ownerId === authInfo.discordUserId,
    );
    if (!character) {
      return new Response("Claim a character sheet first", { status: 400 });
    }

    return this.addProposal(
      {
        kind: "complicate",
        proposerId: authInfo.discordUserId,
        proposerName: authInfo.username,
        slot: character.slot,
      },
      authInfo,
      `${characterLabel(character)} proposes Complicate`,
    );
  }

  /**
   * Use Context Boon: the caller proposes to spend an unconsumed context boon.
   * It costs nothing; on approval the boon is marked consumed and a Boon
   * enters the pool. Context banes are the facilitator's to use directly, so a
   * player cannot propose one.
   */
  private async handleUseContextBoon(
    request: Request,
    authInfo: AuthInfo,
  ): Promise<Response> {
    const input = (await readJson(request)) as UseContextBoonInput | null;
    const contextAspectId =
      typeof input?.contextAspectId === "string" ? input.contextAspectId : "";
    if (!contextAspectId) {
      return new Response("contextAspectId is required", { status: 400 });
    }

    const character = this.game.characters.find(
      (c) => c.ownerId === authInfo.discordUserId,
    );
    if (!character) {
      return new Response("Claim a character sheet first", { status: 400 });
    }
    const aspect = this.game.contextAspects.find(
      (f) => f.id === contextAspectId,
    );
    if (!aspect) {
      return new Response("No such context boon", { status: 404 });
    }
    if (aspect.kind !== "Boon") {
      return new Response("Only the facilitator can use a context bane", {
        status: 400,
      });
    }
    if (aspect.consumed) {
      return new Response("That context boon is already consumed", {
        status: 409,
      });
    }
    if (
      this.game.proposals.some(
        (p) =>
          p.kind === "use-context-boon" && p.contextAspectId === contextAspectId,
      )
    ) {
      return new Response("That context boon is already proposed", {
        status: 409,
      });
    }

    return this.addProposal(
      {
        kind: "use-context-boon",
        proposerId: authInfo.discordUserId,
        proposerName: authInfo.username,
        slot: character.slot,
        contextAspectId,
      },
      authInfo,
      `${characterLabel(character)} proposes Use Context Boon`,
    );
  }

  private async addProposal(
    fields: Omit<
      Proposal,
      "id" | "createdAt" | "contextAspectId" | "targetSlot" | "text"
    > & {
      contextAspectId?: string | null;
      targetSlot?: number | null;
      text?: string | null;
    },
    authInfo?: AuthInfo,
    logLine?: string,
  ): Promise<Response> {
    const {
      contextAspectId = null,
      targetSlot = null,
      text = null,
      ...rest
    } = fields;
    const proposal: Proposal = {
      ...rest,
      contextAspectId,
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
          const junction = state.junction;
          if (!junction) {
            return new Response("No Junction is pending", { status: 409 });
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
            junction: {
              ...junction,
              stones: chosen,
              rerolls: junction.rerolls + 1,
              alteredSlots: [...junction.alteredSlots, proposerSheet.slot],
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
          const aspect: ContextAspect = {
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
            contextAspects: [...state.contextAspects, aspect],
          };
          logLine = `Add Detail accepted — ${characterLabel(
            proposerSheet,
          )} pays ${ADD_DETAIL_COST} boon: ${text}`;
          break;
        }

        case "complicate": {
          // Older proposals named another character in `targetSlot`; honour
          // one still queued, otherwise the proposer's own sheet gains.
          const recipientSlot = proposal.targetSlot ?? proposal.slot;
          const recipient =
            recipientSlot === null
              ? undefined
              : state.characters.find((c) => c.slot === recipientSlot);
          if (!recipient) {
            return this.proposalTargetGone();
          }
          state = {
            ...state,
            characters: await this.bumpFate(
              state.characters,
              recipient.slot,
              COMPLICATE_BOONS,
            ),
          };
          logLine = `Complicate accepted — ${characterLabel(
            recipient,
          )} gains ${COMPLICATE_BOONS} boons`;
          break;
        }

        case "use-context-boon": {
          const aspect = state.contextAspects.find(
            (f) => f.id === proposal.contextAspectId,
          );
          const proposerSheet =
            proposal.slot === null
              ? undefined
              : state.characters.find((c) => c.slot === proposal.slot);
          if (!aspect || !proposerSheet) {
            return this.proposalTargetGone();
          }
          if (aspect.consumed) {
            return new Response("That context boon is already consumed", {
              status: 409,
            });
          }
          state = {
            ...state,
            stonePool: [...state.stonePool, "Boon"],
            contextAspects: state.contextAspects.map((f) =>
              f.id === aspect.id ? { ...f, consumed: true } : f,
            ),
          };
          logLine = `Use Context Boon accepted — ${characterLabel(
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
   * An accepted proposal whose character / context aspect has since gone (a
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
   * Junction (26.2): any player presses it, no approval needed. Draws two
   * stones from the pool without touching the pool, and leaves the result
   * pending until the facilitator accepts or rejects it. One at a time.
   */
  private async handleJunctionRoll(authInfo: AuthInfo): Promise<Response> {
    if (this.game.junction) {
      return new Response("A Junction is already pending", { status: 409 });
    }

    const { chosen } = pickTwoRandom(this.game.stonePool);
    return this.commit(
      {
        ...this.game,
        junction: {
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
        content: `Junction — ${authInfo.username} rolled: ${describeStones(chosen)}`,
      },
    );
  }

  /**
   * The facilitator accepts the pending Junction. The pool returns to its
   * starting shape whatever was added to it, and a matched pair plants a
   * context boon (two Boons) or context bane (two Banes) for the facilitator to
   * word later; a mixed draw plants nothing.
   */
  private async handleJunctionAccept(authInfo: AuthInfo): Promise<Response> {
    const junction = this.game.junction;
    if (!junction) {
      return new Response("No Junction is pending", { status: 409 });
    }

    const kind = pairKind(junction.stones);
    const contextAspects = kind
      ? [
          ...this.game.contextAspects,
          {
            id: crypto.randomUUID(),
            kind,
            text: `${kind} from ${junction.rolledBy}'s Junction`,
            createdByName: junction.rolledBy,
            createdAt: Date.now(),
            consumed: false,
          },
        ]
      : this.game.contextAspects;
    const added = kind ? ` (context ${kind.toLowerCase()} added)` : "";

    return this.commit(
      {
        ...this.game,
        junction: null,
        // A queued Alter Fate is only meaningful during the Junction it was
        // raised for.
        proposals: this.game.proposals.filter((p) => p.kind !== "alter"),
        stonePool: [...INITIAL_STONE_POOL],
        contextAspects,
      },
      {
        authorId: authInfo.discordUserId,
        authorName: authInfo.username,
        role: authInfo.role,
        content: `Junction accepted — ${describeStones(junction.stones)}${added}`,
      },
    );
  }

  /**
   * The facilitator rejects the pending Junction: the roll is discarded and
   * nothing else changes — the pool keeps whatever was added to it, and no
   * context aspect is created — so the table can roll again.
   */
  private async handleJunctionReject(authInfo: AuthInfo): Promise<Response> {
    if (!this.game.junction) {
      return new Response("No Junction is pending", { status: 409 });
    }

    return this.commit(
      {
        ...this.game,
        junction: null,
        proposals: this.game.proposals.filter((p) => p.kind !== "alter"),
      },
      {
        authorId: authInfo.discordUserId,
        authorName: authInfo.username,
        role: authInfo.role,
        content: "Junction rejected — the roll is discarded",
      },
    );
  }

  /**
   * The facilitator's own reroll of the pending Junction: free and immediate,
   * with no proposal. Players reroll only through Alter Fate.
   */
  private async handleJunctionReroll(authInfo: AuthInfo): Promise<Response> {
    const junction = this.game.junction;
    if (!junction) {
      return new Response("No Junction is pending", { status: 409 });
    }

    const { chosen } = pickTwoRandom(this.game.stonePool);
    return this.commit(
      {
        ...this.game,
        junction: { ...junction, stones: chosen, rerolls: junction.rerolls + 1 },
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

  /** Facilitator-only: rewrite one context aspect's text. Silent, like a typo fix. */
  /**
   * Facilitator-only: spend a context aspect into the pool directly, no
   * approval. The pool gains a stone of the aspect's kind and the aspect is
   * marked consumed — kept, visibly, so it cannot be spent twice.
   */
  private async handleUseContextAspect(
    contextAspectId: string,
    authInfo: AuthInfo,
  ): Promise<Response> {
    const aspect = this.game.contextAspects.find((f) => f.id === contextAspectId);
    if (!aspect) {
      return new Response("No such context boon", { status: 404 });
    }
    if (aspect.consumed) {
      return new Response("That context boon is already consumed", {
        status: 409,
      });
    }

    return this.commit(
      {
        ...this.game,
        stonePool: [...this.game.stonePool, aspect.kind],
        contextAspects: this.game.contextAspects.map((f) =>
          f.id === contextAspectId ? { ...f, consumed: true } : f,
        ),
      },
      {
        authorId: authInfo.discordUserId,
        authorName: authInfo.username,
        role: authInfo.role,
        content: `Context ${aspect.kind.toLowerCase()} used — ${aspect.text}`,
      },
    );
  }

  /**
   * Facilitator-only: clear a consumed mark. A correction for a table
   * miscommunication (a stone was spent that should not have been), not part of
   * the game — so it does not touch the pool.
   */
  private async handleUnconsumeContextAspect(
    contextAspectId: string,
    authInfo: AuthInfo,
  ): Promise<Response> {
    const aspect = this.game.contextAspects.find((f) => f.id === contextAspectId);
    if (!aspect) {
      return new Response("No such context boon", { status: 404 });
    }
    if (!aspect.consumed) {
      return new Response("That context boon is not consumed", { status: 409 });
    }

    return this.commit(
      {
        ...this.game,
        contextAspects: this.game.contextAspects.map((f) =>
          f.id === contextAspectId ? { ...f, consumed: false } : f,
        ),
      },
      {
        authorId: authInfo.discordUserId,
        authorName: authInfo.username,
        role: authInfo.role,
        content: `Context ${aspect.kind.toLowerCase()} unconsumed — ${aspect.text}`,
      },
    );
  }

  /** Facilitator rewrites the running session's goal. */
  /** Release a sheet. Allowed for the sheet's owner or the facilitator. */
  /** Add a blank NPC / location row, ready for the facilitator to fill in. */
  /** Persists the message, then folds it into the current in-memory state. */
  private async appendMessage(input: AddMessageInput): Promise<void> {
    const msg: Message = {
      id: crypto.randomUUID(),
      sessionId: this.game.sessionId,
      authorId: input.authorId,
      authorName: input.authorName,
      role: input.role,
      kind: input.kind ?? "event",
      content: input.content,
      createdAt: Date.now(),
    };

    await this.env.DB.prepare(
      `
      INSERT INTO messages (id, session_id, author_id, author_name, role, kind, content, created_at)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    `,
    )
      .bind(
        msg.id,
        msg.sessionId,
        msg.authorId,
        msg.authorName,
        msg.role,
        msg.kind,
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
  /** Defaults to `event`: only `handlePostMessage` writes `chat`. */
  kind?: MessageKind;
  content: string;
};

function capMessages(messages: Message[]): Message[] {
  return messages.length > MESSAGE_WINDOW
    ? messages.slice(messages.length - MESSAGE_WINDOW)
    : messages;
}

async function readJson(request: Request): Promise<Body> {
  try {
    const parsed = await request.json();
    return parsed && typeof parsed === "object"
      ? (parsed as Record<string, unknown>)
      : null;
  } catch {
    return null;
  }
}

function boundedString(value: unknown, max: number): string {
  return typeof value === "string" ? value.slice(0, max) : "";
}

/** The sheet's free-text fields present as strings in `body`, each bounded. */
function sheetFields(body: Record<string, unknown>): Partial<CharacterSheetFields> {
  return {
    ...stringField(body, "name"),
    ...stringField(body, "notableFeatures"),
    ...stringField(body, "archetype"),
    ...stringField(body, "desire"),
    ...stringField(body, "quest"),
    ...stringField(body, "condition"),
    ...stringField(body, "notes", MAX_NOTES_LENGTH),
  };
}

/** `{ [key]: value }` when `body[key]` is a string (bounded), else `{}`, so a
 * field the body leaves out keeps its current value. */
function stringField<K extends string>(
  body: Record<string, unknown>,
  key: K,
  max: number = MAX_FIELD_LENGTH,
): Partial<Record<K, string>> {
  const value = body[key];
  return typeof value === "string"
    ? ({ [key]: value.slice(0, max) } as Record<K, string>)
    : {};
}

/** A rules-core log line, as the `messages` row it is stored as. */
function toMessage(entry: LogEntry, sessionId: string): Message {
  return {
    id: entry.id,
    sessionId,
    authorId: entry.by.userId,
    authorName: entry.by.name,
    role: entry.by.role,
    kind: entry.event.type === "chat" ? "chat" : "event",
    content: logText(entry.event),
    createdAt: entry.at,
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
