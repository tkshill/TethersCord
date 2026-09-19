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
 * The Overcome in progress: one roll waiting on the facilitator to accept or
 * reject it. `stones` is the current draw (a reroll replaces it), `rerolls`
 * counts how many times it has been redrawn, and `alteredSlots` lists the
 * characters whose Alter Fate has already been accepted this Overcome — each
 * may succeed at one. `null` on the `GameState` means nothing is pending.
 */
export type Overcome = {
  rolledBy: string;
  stones: StoneKind[];
  rerolls: number;
  alteredSlots: number[];
};

/**
 * The player moves the facilitator resolves through the one accept / reject
 * queue (Overcome is not one — it needs no approval):
 * - `highlight` — pay 1 boon to add a Boon to the pool.
 * - `complicate` — suggest a complication for another character; on approval
 *   that character's player gains 2 boons.
 * - `add-detail` — pay 1 boon to establish a fact; on approval a session boon.
 * - `alter` — Alter Fate: pay 2 boons to reroll the pending Overcome.
 * - `use-session-boon` — spend a session boon (named by `sessionAspectId`),
 *   adding a Boon to the pool.
 */
export type ProposalKind =
  | "highlight"
  | "complicate"
  | "add-detail"
  | "alter"
  | "use-session-boon";

/**
 * A player-initiated change to shared state, waiting on the facilitator. One per
 * click. `slot` is the proposer's claimed sheet. `sessionAspectId` names the
 * boon for `use-session-boon`; `targetSlot` names the target character for
 * `complicate`.
 */
export type Proposal = {
  id: string;
  kind: ProposalKind;
  proposerId: string;
  proposerName: string;
  slot: number | null;
  sessionAspectId: string | null;
  targetSlot: number | null;
  /** `add-detail` only: the player's suggested wording, or null to ask the
   * facilitator for one. */
  text: string | null;
  createdAt: number;
};

/**
 * A session context owned by no character — a Boon or (23.3) a Bane, with a
 * note of the context it stands for. It comes from an accepted Overcome that
 * drew a matched pair, an accepted Add Detail (always a Boon), or the
 * facilitator directly (`POST /session-aspects`). It stays in
 * `gameState.sessionAspects` until the facilitator deletes it; spending it marks
 * it `consumed` rather than removing it, and a session ending does not clear it.
 */
export type SessionAspect = {
  id: string;
  kind: StoneKind;
  text: string;
  createdByName: string;
  createdAt: number;
  /** Set once the aspect has been spent into the pool. It is not deleted: it
   * stays on the table, visibly consumed, and cannot be spent again. */
  consumed: boolean;
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
  overcome: Overcome | null;
  sessionAspects: SessionAspect[];
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

export type StartSessionInput = {
  goal: string;
};

export type UpdateSessionGoalInput = {
  goal: string;
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
 * a session context directly, picking its `kind`. */
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
  /** The facilitator's wording, when accepting an Add Detail. */
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
