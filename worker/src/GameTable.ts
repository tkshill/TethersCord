// worker/src/GameTable.ts

import type {
  DurableObject,
  DurableObjectState,
} from "@cloudflare/workers-types";
import type {
  AspectName,
  CharacterSheet,
  CharacterSheetFields,
  EntityKind,
  Env,
  GameState,
  Message,
  Role,
  SessionSummary,
  TableEntity,
} from "./types";
import { ASPECT_NAMES, randomInt } from "./gameLogic";
import {
  type LegacyTableState,
  type TableState,
  migrateTableState,
} from "./migrateTableState";
import { type CharacterRow, rowToCharacterSheet } from "./characters";
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

const CHARACTER_SLOT_COUNT = 3;

/** A crypto.randomUUID() shape, for the `/moves/:id/…`,
 * `/context-aspects/:id/…` and `/{npcs,locations}/:id/…` route patterns. */
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
  {
    path: /^\/moves\/highlight$/,
    parse: (_, body) => ({ type: "move/highlight", aspect: aspectName(body?.aspect) }),
  },
  {
    path: /^\/moves\/highlight-context$/,
    parse: (_, body) => ({
      type: "move/highlight-context",
      id: typeof body?.contextAspectId === "string" ? body.contextAspectId : "",
    }),
  },
  {
    path: /^\/moves\/complicate$/,
    parse: (_, body) => ({ type: "move/complicate", aspect: aspectName(body?.aspect) }),
  },
  {
    path: /^\/moves\/create$/,
    parse: (_, body) => ({
      type: "move/create",
      text: boundedString(body?.text, MAX_GOAL_LENGTH),
    }),
  },
  { path: /^\/moves\/alter$/, parse: () => ({ type: "move/alter" }) },
  {
    path: new RegExp(`^/moves/(${UUID})/undo$`),
    parse: ([, id]) => ({ type: "move/undo", id }),
  },
  { path: /^\/junction\/roll$/, parse: () => ({ type: "junction/roll" }) },
  { path: /^\/junction\/reroll$/, parse: () => ({ type: "junction/reroll" }) },
  { path: /^\/junction\/accept$/, parse: () => ({ type: "junction/accept" }) },
  { path: /^\/junction\/reject$/, parse: () => ({ type: "junction/reject" }) },
  {
    path: /^\/die\/step-(up|down)$/,
    parse: ([, direction]) => ({
      type: "die/step",
      direction: direction as "up" | "down",
    }),
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
    const [messageRows, characters, tableState, sessionHistory, npcs, locations] =
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
      die: tableState.die,
      junction: tableState.junction,
      contextAspects: tableState.contextAspects,
      moves: tableState.moves,
      session: await this.backfillSessionStart(tableState.session),
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
   * The die, the pending Junction, context aspects, open moves and the session
   * are the only state this Durable Object genuinely owns, so they live in its
   * own storage. Keeping it in memory loses it every time the
   * DO hibernates, which is roughly ten seconds after a table goes quiet.
   */
  private async loadTableState(): Promise<TableState> {
    const stored = await this.state.storage.get<LegacyTableState>(KEY_TABLE_STATE);
    const migrated = migrateTableState(stored);
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
      die: state.die,
      junction: state.junction,
      contextAspects: state.contextAspects,
      moves: state.moves,
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
}

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

/** A character aspect's name, or `null` for anything else. */
function aspectName(value: unknown): AspectName | null {
  return ASPECT_NAMES.includes(value as AspectName) ? (value as AspectName) : null;
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
