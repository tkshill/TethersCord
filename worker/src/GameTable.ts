// worker/src/GameTable.ts

import type {
  DurableObject,
  DurableObjectState,
} from "@cloudflare/workers-types";
import type {
  Env,
  GameState,
  Message,
  PendingRoll,
  PostMessageInput,
  Role,
  StoneKind,
  CharacterSheet,
  UpdateCharacterInput,
  UpdateFateInput,
} from "./types";

const INITIAL_STONE_POOL: readonly StoneKind[] = [
  "WhiteStone",
  "BlackStone",
  "WhiteStone",
  "BlackStone",
];

const CHARACTER_SLOT_COUNT = 3;

const MAX_MESSAGE_LENGTH = 2000;
const MAX_FIELD_LENGTH = 500;
const MAX_NOTES_LENGTH = 4000;

/** Durable Object storage keys. */
const KEY_SESSION_ID = "sessionId";
const KEY_STONES = "stones";

type StoneState = {
  stonePool: StoneKind[];
  pendingRoll: PendingRoll | null;
};

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

  constructor(state: DurableObjectState, env: Env) {
    this.state = state;
    this.env = env;
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
    const authInfo = await getAuthFromRequest(this.env, request);
    if (!authInfo) {
      return new Response("Unauthorized", { status: 401 });
    }

    if (url.pathname === "/messages" && request.method === "GET") {
      return jsonResponse(this.gameState);
    }

    if (url.pathname === "/message" && request.method === "POST") {
      return this.withLock(() => this.handlePostMessage(request, authInfo));
    }

    if (url.pathname === "/stones/add-white" && request.method === "POST") {
      return this.withLock(() => this.handleAddWhiteStone());
    }

    if (url.pathname === "/stones/roll" && request.method === "POST") {
      return this.withLock(() => this.handleRoll(authInfo, "Rolled"));
    }

    if (url.pathname === "/stones/reroll" && request.method === "POST") {
      return this.withLock(() => this.handleRoll(authInfo, "Rerolled"));
    }

    if (url.pathname === "/stones/accept" && request.method === "POST") {
      return this.withLock(() => this.handleAcceptRoll());
    }

    const charUpdateMatch = url.pathname.match(/^\/characters\/(\d+)\/update$/);
    if (charUpdateMatch && request.method === "POST") {
      return this.withLock(() =>
        this.handleUpdateCharacter(request, Number(charUpdateMatch[1])),
      );
    }

    const charFateMatch = url.pathname.match(/^\/characters\/(\d+)\/fate$/);
    if (charFateMatch && request.method === "POST") {
      return this.withLock(() =>
        this.handleUpdateFate(request, Number(charFateMatch[1])),
      );
    }

    return new Response("Not found", { status: 404 });
  }

  private async handleConnect(request: Request): Promise<Response> {
    const token = parseTokenFromProtocol(
      request.headers.get("Sec-WebSocket-Protocol"),
    );
    const authInfo = token ? await getAuthFromToken(this.env, token) : null;
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
      LIMIT 200
    `,
    )
      .bind(sessionId)
      .all<Message>();

    const messages = rows.results ? [...rows.results].reverse() : [];
    const characters = await this.loadOrCreateCharacters(sessionId);
    const stones = await this.loadStoneState();

    this.gameState = {
      sessionId,
      messages,
      stonePool: stones.stonePool,
      pendingRoll: stones.pendingRoll,
      characters,
    };

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
    const stored = await this.state.storage.get<StoneState>(KEY_STONES);
    if (stored) {
      return stored;
    }

    const initial: StoneState = {
      stonePool: [...INITIAL_STONE_POOL],
      pendingRoll: null,
    };
    await this.state.storage.put(KEY_STONES, initial);
    return initial;
  }

  private async saveStoneState(state: GameState): Promise<void> {
    await this.state.storage.put(KEY_STONES, {
      stonePool: state.stonePool,
      pendingRoll: state.pendingRoll,
    } satisfies StoneState);
  }

  private async loadOrCreateCharacters(
    sessionId: string,
  ): Promise<CharacterSheet[]> {
    const rows = await this.env.DB.prepare(
      `
      SELECT id, slot, name, notable_features, archetype, desire, quest, condition, notes, fate
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

  private async handleAddWhiteStone(): Promise<Response> {
    // Read `this.gameState` fresh rather than from a snapshot taken before an
    // await, so concurrent requests cannot clobber each other's writes.
    this.gameState = {
      ...this.gameState!,
      stonePool: [...this.gameState!.stonePool, "WhiteStone"],
    };
    await this.saveStoneState(this.gameState);

    this.broadcast(this.gameState);
    return ackResponse();
  }

  private async handleRoll(
    authInfo: AuthInfo,
    verb: "Rolled" | "Rerolled",
  ): Promise<Response> {
    const pendingRoll = pickTwoRandom(this.gameState!.stonePool);

    this.gameState = { ...this.gameState!, pendingRoll };
    await this.saveStoneState(this.gameState);

    await this.appendMessage({
      authorId: authInfo.discordUserId,
      authorName: authInfo.username,
      role: authInfo.role,
      content: `${verb}: ${describeStones(pendingRoll.chosen)}`,
    });

    this.broadcast(this.gameState!);
    return ackResponse();
  }

  private async handleAcceptRoll(): Promise<Response> {
    this.gameState = {
      ...this.gameState!,
      stonePool: [...INITIAL_STONE_POOL],
      pendingRoll: null,
    };
    await this.saveStoneState(this.gameState);

    this.broadcast(this.gameState);
    return ackResponse();
  }

  private async handleUpdateCharacter(
    request: Request,
    slot: number,
  ): Promise<Response> {
    const input = (await readJson(request)) as UpdateCharacterInput | null;
    if (!input) {
      return new Response("Invalid body", { status: 400 });
    }

    const character = this.gameState!.characters.find((c) => c.slot === slot);
    if (!character) {
      return new Response("Not found", { status: 404 });
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

const MAX_MESSAGES = 200;

function capMessages(messages: Message[]): Message[] {
  return messages.length > MAX_MESSAGES
    ? messages.slice(messages.length - MAX_MESSAGES)
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
  return stones.map((s) => (s === "WhiteStone" ? "White" : "Black")).join(", ");
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
  };
}

type AuthInfo = {
  discordUserId: string;
  username: string;
  role: Role;
};

function parseTokenFromProtocol(header: string | null): string | null {
  if (!header) return null;

  const parts = header.split(",").map((part) => part.trim());
  return parts.find((part) => part && part !== "bearer") ?? null;
}

async function getAuthFromRequest(
  env: Env,
  request: Request,
): Promise<AuthInfo | null> {
  const authHeader = request.headers.get("Authorization");
  if (!authHeader?.startsWith("Bearer ")) {
    return null;
  }

  const token = authHeader.slice("Bearer ".length).trim();
  if (!token) return null;

  return getAuthFromToken(env, token);
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

  const role: Role = row.dm_id ? "facilitator" : "player";

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
