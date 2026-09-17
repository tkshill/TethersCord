// worker/src/migrateStoneState.ts
//
// The DO owns one blob of state D1 does not — the stone pool, proposal queue,
// session, floating boons, used-ability flags — under `KEY_STONES`. This
// module keeps the load-time compatibility handling (colour-named stones,
// missing fields added by later features, retired fields folded forward) out
// of the main flow, so it is easy to delete once no old blob can still be on
// disk.

import type {
  CommittedBoon,
  FloatingBoon,
  Proposal,
  SessionState,
  StoneKind,
  UsedAbilities,
} from "./types";

/** The shape held in `KEY_STONES` and folded into `GameState` on load. */
export type StoneState = {
  stonePool: StoneKind[];
  committedBoons: CommittedBoon[];
  floatingBoons: FloatingBoon[];
  usedAbilities: UsedAbilities[];
  proposals: Proposal[];
  session: SessionState | null;
};

/** Shape of `KEY_STONES` as written by builds before the session pool and the
 * roll bag were merged into one pool, and before untethering was retired. */
export type LegacyStoneKind = StoneKind | "WhiteStone" | "BlackStone";
export type LegacyStoneState = {
  stonePool: LegacyStoneKind[];
  /** Retired along with the roll/reroll/accept lifecycle (23.1) — a draw is
   * now a read-only, stateless action, so nothing is left pending between
   * requests. Read for old blobs but dropped from `StoneState`. */
  pendingRoll?: {
    chosen: LegacyStoneKind[];
    rest: LegacyStoneKind[];
  } | null;
  /** Retired along with `pendingRoll` (23.1) — an overcome no longer names a
   * target, so there is nothing left to be "open". */
  overcome?: { targetSlot: number } | null;
  committedBoons?: CommittedBoon[];
  floatingBoons?: FloatingBoon[];
  usedAbilities?: UsedAbilities[];
  proposals?: Proposal[];
  session?:
    | (Pick<SessionState, "id" | "goal"> & {
        pool?: LegacyStoneKind[];
        carriedBanes?: number;
      })
    | null;
  /** Retired: Banes the next session's pool used to inherit. Folded into
   * `stonePool` as that many Bane stones, then dropped. */
  carriedBanes?: number;
  lastSessionFailed?: boolean;
  untether?: unknown;
};

function migrateStoneKind(kind: LegacyStoneKind): StoneKind {
  if (kind === "WhiteStone") return "Boon";
  if (kind === "BlackStone") return "Bane";
  return kind;
}

/**
 * Fold a stored `KEY_STONES` blob (or nothing, on a cold table) into the
 * current `StoneState`: colour-named stones become Boon / Bane, every field a
 * later feature added is defaulted, and the retired per-session pool and
 * carried-Bane count are folded into the single shared `stonePool` so no
 * stones already in play vanish. `initialPool` is `INITIAL_STONE_POOL`.
 */
export function migrateStoneState(
  stored: LegacyStoneState | undefined,
  initialPool: readonly StoneKind[],
): StoneState {
  if (!stored) {
    return {
      stonePool: [...initialPool],
      committedBoons: [],
      floatingBoons: [],
      usedAbilities: [],
      proposals: [],
      session: null,
    };
  }

  const legacySessionPool = (stored.session?.pool ?? []).map(migrateStoneKind);
  const legacyCarriedBanes = Array<StoneKind>(stored.carriedBanes ?? 0).fill(
    "Bane",
  );

  return {
    stonePool: [
      ...stored.stonePool.map(migrateStoneKind),
      ...legacySessionPool,
      ...legacyCarriedBanes,
    ],
    committedBoons: stored.committedBoons ?? [],
    floatingBoons: stored.floatingBoons ?? [],
    usedAbilities: stored.usedAbilities ?? [],
    // Proposals from before the moves work carry no `floatingId` / `targetSlot`.
    proposals: (stored.proposals ?? []).map((p) => ({
      ...p,
      floatingId: p.floatingId ?? null,
      targetSlot: p.targetSlot ?? null,
    })),
    session: stored.session
      ? { id: stored.session.id, goal: stored.session.goal }
      : null,
  };
}
