// worker/src/migrateStoneState.ts
//
// The DO owns one blob of state D1 does not — the stone pool, pending roll,
// proposal queue, session pool, overcome, floating boons, used-ability flags —
// under `KEY_STONES`. This module keeps the load-time compatibility handling
// (colour-named stones, missing fields added by later features) out of the main
// flow, so it is easy to delete once no old blob can still be on disk.

import type {
  CommittedBoon,
  FloatingBoon,
  Overcome,
  PendingRoll,
  Proposal,
  SessionState,
  StoneKind,
  UsedAbilities,
  Untether,
} from "./types";

/** The shape held in `KEY_STONES` and folded into `GameState` on load. */
export type StoneState = {
  stonePool: StoneKind[];
  pendingRoll: PendingRoll | null;
  overcome: Overcome | null;
  committedBoons: CommittedBoon[];
  floatingBoons: FloatingBoon[];
  usedAbilities: UsedAbilities[];
  proposals: Proposal[];
  session: SessionState | null;
  /** Banes the next session's pool inherits (section 19). Boons never carry. */
  carriedBanes: number;
  /** Whether the most recently ended session failed its goal — blocks a second
   * consecutive untether. */
  lastSessionFailed: boolean;
  /** An in-progress reckoning, or null. */
  untether: Untether | null;
};

/** Shape of `KEY_STONES` as written by builds that still used colour names and
 * had not yet grown the moves / section-19 fields. */
export type LegacyStoneKind = StoneKind | "WhiteStone" | "BlackStone";
export type LegacyStoneState = {
  stonePool: LegacyStoneKind[];
  pendingRoll: {
    chosen: LegacyStoneKind[];
    rest: LegacyStoneKind[];
  } | null;
  overcome?: Overcome | null;
  committedBoons?: CommittedBoon[];
  floatingBoons?: FloatingBoon[];
  usedAbilities?: UsedAbilities[];
  proposals?: Proposal[];
  session?:
    | (Omit<SessionState, "carriedBanes"> & { carriedBanes?: number })
    | null;
  carriedBanes?: number;
  lastSessionFailed?: boolean;
  untether?: Untether | null;
};

function migrateStoneKind(kind: LegacyStoneKind): StoneKind {
  if (kind === "WhiteStone") return "Boon";
  if (kind === "BlackStone") return "Bane";
  return kind;
}

/**
 * Fold a stored `KEY_STONES` blob (or nothing, on a cold table) into the
 * current `StoneState`: colour-named stones become Boon / Bane, and every field
 * a later feature added is defaulted. `initialPool` is `INITIAL_STONE_POOL`.
 */
export function migrateStoneState(
  stored: LegacyStoneState | undefined,
  initialPool: readonly StoneKind[],
): StoneState {
  if (!stored) {
    return {
      stonePool: [...initialPool],
      pendingRoll: null,
      overcome: null,
      committedBoons: [],
      floatingBoons: [],
      usedAbilities: [],
      proposals: [],
      session: null,
      carriedBanes: 0,
      lastSessionFailed: false,
      untether: null,
    };
  }

  return {
    stonePool: stored.stonePool.map(migrateStoneKind),
    pendingRoll: stored.pendingRoll
      ? {
          chosen: stored.pendingRoll.chosen.map(migrateStoneKind),
          rest: stored.pendingRoll.rest.map(migrateStoneKind),
        }
      : null,
    overcome: stored.overcome ?? null,
    committedBoons: stored.committedBoons ?? [],
    floatingBoons: stored.floatingBoons ?? [],
    usedAbilities: stored.usedAbilities ?? [],
    // Proposals from before the moves work carry no `floatingId` / `targetSlot`.
    proposals: (stored.proposals ?? []).map((p) => ({
      ...p,
      floatingId: p.floatingId ?? null,
      targetSlot: p.targetSlot ?? null,
    })),
    // Sessions from before section 19 carry no `carriedBanes`.
    session: stored.session
      ? { ...stored.session, carriedBanes: stored.session.carriedBanes ?? 0 }
      : null,
    carriedBanes: stored.carriedBanes ?? 0,
    lastSessionFailed: stored.lastSessionFailed ?? false,
    untether: stored.untether ?? null,
  };
}
