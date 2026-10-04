// worker/src/types.ts

import type {
  D1Database,
  DurableObjectNamespace,
} from "@cloudflare/workers-types";
import type { Die, Outcome } from "./rules/dice";

export type Role = "facilitator" | "player";

/**
 * `chat` is a line a person typed into the composer; `event` is a line the table
 * wrote when a mutation happened (a roll, an accepted proposal, a session start).
 */
export type MessageKind = "chat" | "event";

export type Message = {
  id: string;
  sessionId: string;
  authorId: string;
  authorName: string;
  role: Role;
  kind: MessageKind;
  content: string;
  createdAt: number;
};

/**
 * Which way a context aspect pushes the die: a `Boon` steps it up, a `Bane`
 * steps it down. (Called `StoneKind` while the stone pool existed; the wire
 * values are unchanged.)
 */
export type Polarity = "Boon" | "Bane";

/**
 * The Junction in progress: one roll waiting on the facilitator to accept or
 * reject it. `die`, `face` and `outcome` are the current roll (a reroll or an
 * Alter replaces them, on the same die), `rerolls` counts the replacements, and
 * `alteredSlots` lists the characters whose Alter has already been accepted
 * this Junction — each may succeed at one. `null` on the `GameState` means
 * nothing is pending.
 */
export type Junction = {
  rolledBy: string;
  die: Die;
  face: number;
  outcome: Outcome;
  rerolls: number;
  alteredSlots: number[];
};

/**
 * The player moves the facilitator resolves through the one accept / reject
 * queue (Junction is not one — it needs no approval):
 * - `highlight` — pay 1 boon to step the die up.
 * - `complicate` — suggest a complication for your own character; on approval
 *   it gains 2 boons.
 * - `add-detail` — pay 1 boon to establish a fact; on approval a context boon.
 * - `alter` — Alter Fate: pay 2 boons to reroll the pending Junction.
 * - `use-context-boon` — spend a context boon (named by `contextAspectId`),
 *   stepping the die up.
 * (31.3 replaces the queue with direct moves and undo.)
 */
export type ProposalKind =
  | "highlight"
  | "complicate"
  | "add-detail"
  | "alter"
  | "use-context-boon";

/**
 * A player-initiated change to shared state, waiting on the facilitator. One per
 * click. `slot` is the proposer's claimed sheet. `contextAspectId` names the
 * boon for `use-context-boon`. `targetSlot` is only set on an older
 * `complicate`, which named another character; it is null otherwise.
 */
export type Proposal = {
  id: string;
  kind: ProposalKind;
  proposerId: string;
  proposerName: string;
  slot: number | null;
  contextAspectId: string | null;
  targetSlot: number | null;
  /** `add-detail` only: the player's suggested wording, or null to ask the
   * facilitator for one. */
  text: string | null;
  createdAt: number;
};

/**
 * An aspect of the situation owned by no character — a context boon or a
 * context bane. It comes from an accepted Critical Flow (a boon) or Critical
 * Friction (a bane), an accepted Add Detail (always a boon), or the
 * facilitator directly (`POST /context-aspects`). It stays in
 * `gameState.contextAspects` until the facilitator deletes it; spending it marks
 * it `consumed` rather than removing it, and a session ending does not clear it.
 */
export type ContextAspect = {
  id: string;
  kind: Polarity;
  text: string;
  createdByName: string;
  createdAt: number;
  /** Set once the aspect has stepped the die. It is not deleted: it
   * stays on the table, visibly consumed, and cannot be spent again. */
  consumed: boolean;
};

/** The three fixed aspects a character is written around. */
export type AspectName = "archetype" | "desire" | "quest";

/**
 * How many Banes each aspect carries. A mixed junction roll marks one aspect;
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
  /** Epoch millis, matching `game_sessions.started_at`; carried so ending the
   * session can add it to `sessionHistory` without re-reading D1. */
  startedAt: number;
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
  /** The die the next Junction rolls; back to `BASE_DIE` on every accept. */
  die: Die;
  junction: Junction | null;
  contextAspects: ContextAspect[];
  proposals: Proposal[];
  session: SessionState | null;
  sessionHistory: SessionSummary[];
  characters: CharacterSheet[];
  npcs: TableEntity[];
  locations: TableEntity[];
};

export type UseContextBoonInput = {
  contextAspectId: string;
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
