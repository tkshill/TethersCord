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

/**
 * Every player-initiated request the facilitator resolves through the one
 * accept / reject queue:
 * - `add-boon` — add a Boon to the shared pool.
 * - `pledge` — Highlight an Aspect: pledge (`delta` +1) or withdraw (-1) one of
 *   the proposer's own boons on the next roll.
 * - `help-out`, `add-detail`, `gain-insight`, `suggest-compel` — the
 *   once-per-session abilities.
 * - `accept-compel` — the move: take on a complication for 2 boons.
 * - `use-floating` — spend a floating boon (named by `floatingId`) on the roll.
 */
export type ProposalKind =
  | "add-boon"
  | "pledge"
  | "help-out"
  | "add-detail"
  | "gain-insight"
  | "suggest-compel"
  | "accept-compel"
  | "use-floating";

/**
 * A player-initiated change to shared state, waiting on the facilitator. One per
 * click. `delta` is +1 / -1 for a pledge. `slot` is the proposer's claimed sheet
 * (null only for `add-boon`). `floatingId` names the boon for `use-floating`;
 * `targetSlot` names the compelled character for `suggest-compel`.
 */
export type Proposal = {
  id: string;
  kind: ProposalKind;
  proposerId: string;
  proposerName: string;
  slot: number | null;
  delta: number;
  floatingId: string | null;
  targetSlot: number | null;
  createdAt: number;
};

/** Once-per-session abilities a player calls on, each gated by facilitator approval. */
export type AbilityKind =
  | "help-out"
  | "add-detail"
  | "gain-insight"
  | "suggest-compel";

/**
 * A boon owned by no character. The facilitator creates one — with a note of the
 * context it stands for — by approving an Add a Detail or Gain Insight ability.
 * It waits in `gameState.floatingBoons` until a player spends it on a roll (also
 * facilitator-approved), and is discarded when the session ends.
 */
export type FloatingBoon = {
  id: string;
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

/**
 * An open overcome: the facilitator has framed a risky attempt and named one
 * character as its target. While it is set, that character's player may Roll and
 * Reroll to resolve it (otherwise a facilitator-only action), and a Reroll costs
 * the target boons. Lives alongside `pendingRoll` in Durable Object storage;
 * cleared when the roll is accepted or the overcome is called off.
 */
export type Overcome = {
  targetSlot: number;
};

export type GameState = {
  sessionId: string;
  messages: Message[];
  stonePool: StoneKind[];
  pendingRoll: PendingRoll | null;
  overcome: Overcome | null;
  committedBoons: CommittedBoon[];
  floatingBoons: FloatingBoon[];
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

export type CommitBoonInput = {
  delta: number;
};

export type StartSessionInput = {
  goal: string;
};

export type UpdateSessionGoalInput = {
  goal: string;
};

export type StartOvercomeInput = {
  slot: number;
};

export type UseAbilityInput = {
  kind: AbilityKind;
  /** Required for `suggest-compel`: the slot of the character being compelled. */
  targetSlot?: number;
};

export type UseFloatingBoonInput = {
  floatingId: string;
};

/** Create (`POST /npcs`) or update (`POST /npcs/:id/update`) a reference row. */
export type EntityInput = {
  name?: string;
  notes?: string;
};

export type ProposalDecisionInput = {
  /** The facilitator's context note, when accepting an Add a Detail / Gain Insight. */
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
