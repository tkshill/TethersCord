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

export type PendingRoll = {
  chosen: StoneKind[];
  rest: StoneKind[];
};

/**
 * Boon stones a character has pledged into the next roll, spent from their
 * `fate` stock when the roll is accepted. One entry per character with a
 * non-zero pledge, keyed by slot.
 */
export type CommittedBoon = {
  slot: number;
  count: number;
};

export type ProposalKind = "add-boon" | "pledge";

/**
 * A player-initiated change to shared stone state, waiting on the facilitator.
 * One per click — `delta` is +1 / -1. `slot` is the proposer's claimed sheet
 * for a pledge, null for add-boon.
 */
export type Proposal = {
  id: string;
  kind: ProposalKind;
  proposerId: string;
  proposerName: string;
  slot: number | null;
  delta: number;
  createdAt: number;
};

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
  /** Discord user id of the player who claimed this sheet, or null. */
  ownerId: string | null;
};

export type CharacterSheetFields = Omit<
  CharacterSheet,
  "id" | "slot" | "fate" | "ownerId"
>;

/**
 * The running game session, if one is open. `id` ties back to the
 * `game_sessions` D1 row; `pool` is the session stone pool, held in Durable
 * Object storage and grown one stone per accepted roll.
 */
export type SessionState = {
  id: string;
  goal: string;
  pool: StoneKind[];
};

export type GameState = {
  sessionId: string;
  messages: Message[];
  stonePool: StoneKind[];
  pendingRoll: PendingRoll | null;
  committedBoons: CommittedBoon[];
  proposals: Proposal[];
  session: SessionState | null;
  characters: CharacterSheet[];
};

export type PostMessageInput = {
  content: string;
};

export type UpdateCharacterInput = Partial<CharacterSheetFields>;

export type UpdateFateInput = {
  delta: number;
};

export type CommitBoonInput = {
  delta: number;
};

export type StartSessionInput = {
  goal: string;
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
