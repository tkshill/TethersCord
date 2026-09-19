// worker/src/types.ts

import type {
  D1Database,
  DurableObjectNamespace,
} from "@cloudflare/workers-types";

export type Role = "facilitator" | "player";

export type Message = {
  id: string;
  sessionId: string;
  authorId: string;
  authorName: string;
  role: Role;
  content: string;
  createdAt: number;
};

/**
 * A stone names its outcome, not a colour: `Boon` is favourable, `Bane` is not.
 * (Earlier builds called these `WhiteStone` / `BlackStone`; `GameTable` migrates
 * the legacy names out of Durable Object storage on load.)
 */
export type StoneKind = "Boon" | "Bane";

/**
 * The result of one draw from the pool: `chosen` is what a facilitator's
 * `/overcome/roll` shows, `rest` the remainder — the pool itself is never
 * written by a draw, so `rest` is only ever read, never persisted.
 */
export type PendingRoll = {
  chosen: StoneKind[];
  rest: StoneKind[];
};

/**
 * Boon stones a character has highlighted into the next draw's odds
 * (`drawFromBag` adds one extra Boon per committed boon to the bag). One
 * entry per character with a non-zero highlight, keyed by slot. 23.1 retired the
 * roll/reroll/accept lifecycle that used to spend these from `fate` on
 * accept — what a highlight costs, if anything, going forward is an open
 * question (see ROADMAP.md 23).
 */
export type CommittedBoon = {
  slot: number;
  count: number;
};

/**
 * Every player-initiated request the facilitator resolves through the one
 * accept / reject queue:
 * - `add-boon` — add a Boon to the shared pool.
 * - `highlight` — Highlight an Aspect: highlight (`delta` +1) or withdraw (-1) one of
 *   the proposer's own boons on the next roll.
 * - `alter`, `add-detail`, `gain-insight`, `complicate` — the
 *   once-per-session abilities.
 * - `accept-compel` — the move: take on a complication for 2 boons.
 * - `use-session-boon` — spend a session aspect (named by `sessionAspectId`) on the roll.
 *
 * `add-boon`, `highlight`, and (23.3) `use-session-boon` are disconnected from the
 * current client — the facilitator hand-edits the pool and session contexts
 * directly instead — but stay fully functional server-side, unreachable only
 * from the UI.
 */
export type ProposalKind =
  | "add-boon"
  | "highlight"
  | "alter"
  | "add-detail"
  | "gain-insight"
  | "complicate"
  | "accept-compel"
  | "use-session-boon";

/**
 * A player-initiated change to shared state, waiting on the facilitator. One per
 * click. `delta` is +1 / -1 for a highlight. `slot` is the proposer's claimed sheet
 * (null only for `add-boon`). `sessionAspectId` names the boon for `use-session-boon`;
 * `targetSlot` names the target character for `complicate`.
 */
export type Proposal = {
  id: string;
  kind: ProposalKind;
  proposerId: string;
  proposerName: string;
  slot: number | null;
  delta: number;
  sessionAspectId: string | null;
  targetSlot: number | null;
  createdAt: number;
};

/** Once-per-session abilities a player calls on, each gated by facilitator approval. */
export type AbilityKind =
  | "alter"
  | "add-detail"
  | "gain-insight"
  | "complicate";

/**
 * A session context owned by no character — a Boon or (23.3) a Bane, with a
 * note of the context it stands for. The facilitator creates one directly
 * (`POST /session-aspects`), or approves an Add Detail / Gain Insight
 * ability, which always produces a Boon. It waits in `gameState.sessionAspects`
 * until the facilitator deletes it — its only other lifecycle state — and is
 * discarded when the session ends.
 */
export type SessionAspect = {
  id: string;
  kind: StoneKind;
  text: string;
  createdByName: string;
  createdAt: number;
};

/** Which once-per-session abilities a character has already spent this session. */
export type UsedAbilities = {
  slot: number;
  kinds: AbilityKind[];
};

/** The three fixed aspects a character is written around. */
export type AspectName = "archetype" | "desire" | "quest";

/**
 * How many Banes each aspect carries. A mixed overcome roll marks one aspect;
 * the counts persist between sessions.
 */
export type AspectBanes = Record<AspectName, number>;

export type CharacterSheet = {
  id: string;
  slot: number;
  name: string;
  notableFeatures: string;
  archetype: string;
  desire: string;
  quest: string;
  condition: string;
  notes: string;
  fate: number;
  aspectBanes: AspectBanes;
  /** Discord user id of the player who claimed this sheet, or null. */
  ownerId: string | null;
};

export type CharacterSheetFields = Omit<
  CharacterSheet,
  "id" | "slot" | "fate" | "aspectBanes" | "ownerId"
>;

/**
 * A facilitator-owned reference row — an NPC or a location. Broadcast to the
 * whole table, editable only by the facilitator. Backed by the `npcs` /
 * `locations` D1 tables, scoped by `session_id` like `characters`.
 */
export type TableEntity = {
  id: string;
  name: string;
  notes: string;
  createdAt: number;
  updatedAt: number;
};

/** Which reference collection a `/npcs` or `/locations` route acts on. */
export type EntityKind = "npcs" | "locations";

/**
 * The running game session, if one is open. `id` ties back to the
 * `game_sessions` D1 row. The goal is free text the facilitator sets and can
 * rewrite; nothing about the session itself resolves it — there is no roll or
 * verdict tied to ending a session.
 */
export type SessionState = {
  id: string;
  goal: string;
};

/**
 * A completed session, as read back from the `game_sessions` D1 rows. Feeds the
 * table's session-history view; the running session is not included.
 */
export type SessionSummary = {
  id: string;
  goal: string;
  startedAt: number;
  endedAt: number;
};

export type GameState = {
  sessionId: string;
  messages: Message[];
  stonePool: StoneKind[];
  committedBoons: CommittedBoon[];
  sessionAspects: SessionAspect[];
  usedAbilities: UsedAbilities[];
  proposals: Proposal[];
  session: SessionState | null;
  sessionHistory: SessionSummary[];
  characters: CharacterSheet[];
  npcs: TableEntity[];
  locations: TableEntity[];
};

export type PostMessageInput = {
  content: string;
};

export type UpdateCharacterInput = Partial<CharacterSheetFields>;

export type UpdateFateInput = {
  delta: number;
};

export type HighlightInput = {
  delta: number;
};

export type StartSessionInput = {
  goal: string;
};

export type UpdateSessionGoalInput = {
  goal: string;
};

export type UseAbilityInput = {
  kind: AbilityKind;
  /** Required for `complicate`: the slot of the target character. */
  targetSlot?: number;
};

export type UseSessionBoonInput = {
  sessionAspectId: string;
};

/** `POST /stones/{add,remove}` (23.2): a facilitator hand-edit of the shared
 * pool, one stone at a time, independent of any draw. */
export type AddOrRemoveStoneInput = {
  kind: StoneKind;
};

/** `POST /session-aspects` (23.2, widened 23.3): the facilitator plants
 * a session context directly, picking its `kind` — an accepted Add Detail /
 * Gain Insight still only ever produces a Boon. */
export type AddSessionAspectInput = {
  kind: StoneKind;
  text: string;
};

/** Create (`POST /npcs`) or update (`POST /npcs/:id/update`) a reference row. */
export type EntityInput = {
  name?: string;
  notes?: string;
};

export type ProposalDecisionInput = {
  /** The facilitator's context note, when accepting an Add Detail / Gain Insight. */
  text?: string;
};

export type BackendAuthResult = {
  userId: string;
  username: string;
  role: Role;
  sessionToken: string;
  /** Epoch millis at which `sessionToken` stops being accepted. */
  expiresAt: number;
  /** Discord access token, for `discordSdk.commands.authenticate`. */
  accessToken: string;
};

export type Env = {
  DB: D1Database;
  GAME_TABLE: DurableObjectNamespace;
  DISCORD_CLIENT_ID: string;
  DISCORD_CLIENT_SECRET: string;
  /** Discord user id always treated as facilitator; "" to rely on table rows. */
  BOOTSTRAP_FACILITATOR_ID: string;
};
