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
};

export type CharacterSheetFields = Omit<CharacterSheet, "id" | "slot" | "fate">;

export type GameState = {
  sessionId: string;
  messages: Message[];
  stonePool: StoneKind[];
  pendingRoll: PendingRoll | null;
  committedBoons: CommittedBoon[];
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
  slot: number;
  delta: number;
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
