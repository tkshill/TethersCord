// worker/src/types.ts

import type {
  D1Database,
  DurableObjectNamespace,
} from "@cloudflare/workers-types";
import type { Die, Direction, Outcome, Roll } from "./rules/dice";

export type Role = "facilitator" | "player";

/**
 * `chat` is a line a person typed into the composer; `event` is a line the table
 * wrote when a mutation happened (a roll, a move, a session start).
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

/** The five moves (RULES.md "Moves"). Rolling a Junction is not one. */
export type MoveKind =
  | "highlight"
  | "highlight-context"
  | "complicate"
  | "create"
  | "alter";

/**
 * One thing a move did to the table, as data. A move records its effects so
 * that undo can apply their inverse (ADR 0002, ADR 0003) — reversing that
 * move and nothing else, so moves made since survive.
 */
export type MoveEffect =
  | { type: "die"; direction: Direction }
  | { type: "boons"; slot: number; delta: number }
  | { type: "aspect-added"; aspect: ContextAspect }
  | { type: "aspect-consumed"; id: string }
  | {
      type: "rerolled";
      slot: number;
      previous: Roll;
      next: Roll;
      /** The Junction's reroll count with this Alter applied; a higher count
       * at undo means a later reroll replaced it. */
      rerolls: number;
    };

/**
 * A move that can still be undone. Held in `gameState.moves` (Durable Object
 * state, never D1) until its window closes: when a Junction is rolled, or for
 * an Alter when its Junction is accepted or rejected. `messageId` is the move's
 * log line, so the client can put the undo link on it.
 */
export type MoveRecord = {
  id: string;
  kind: MoveKind;
  actorId: string;
  actorName: string;
  /** The mover's sheet, or null for a Highlight Context made without one. */
  slot: number | null;
  /** The character aspect a Highlight or Complicate drew on. */
  aspect: AspectName | null;
  effects: MoveEffect[];
  messageId: string;
};

/**
 * An aspect of the situation owned by no character — a context boon or a
 * context bane. It comes from an accepted Critical Flow (a boon) or Critical
 * Friction (a bane), a Create (a boon), a Complicate (a bane), or the
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
  /** The character aspect a Complicate drew this bane from, or null. */
  fromAspect: { slot: number; aspect: AspectName } | null;
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
  /** Moves that can still be undone, oldest first. */
  moves: MoveRecord[];
  session: SessionState | null;
  sessionHistory: SessionSummary[];
  characters: CharacterSheet[];
  npcs: TableEntity[];
  locations: TableEntity[];
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
