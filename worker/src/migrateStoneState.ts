// worker/src/migrateStoneState.ts
//
// The DO owns one blob of state D1 does not — the stone pool, proposal queue,
// session, session aspects, used-ability flags — under `KEY_STONES`. This
// module keeps the load-time compatibility handling (colour-named stones,
// missing fields added by later features, retired fields folded forward) out
// of the main flow, so it is easy to delete once no old blob can still be on
// disk.

import type {
  AbilityKind,
  CommittedBoon,
  Proposal,
  ProposalKind,
  SessionAspect,
  SessionState,
  StoneKind,
  UsedAbilities,
} from "./types";

/** The shape held in `KEY_STONES` and folded into `GameState` on load. */
export type StoneState = {
  stonePool: StoneKind[];
  committedBoons: CommittedBoon[];
  sessionAspects: SessionAspect[];
  usedAbilities: UsedAbilities[];
  proposals: Proposal[];
  session: SessionState | null;
};

/** Shape of `KEY_STONES` as written by builds before the session pool and the
 * roll bag were merged into one pool, and before untethering was retired. */
export type LegacyStoneKind = StoneKind | "WhiteStone" | "BlackStone";

/** A session aspect as stored under its pre-26.1 name (`floatingBoons`), and
 * before 23.3 widened it with `kind` — every one on disk from before that point
 * is implicitly a Boon. */
export type LegacyFloatingBoon = Omit<SessionAspect, "kind"> & {
  kind?: StoneKind;
};

/** Proposal kinds and ability kinds as stored before 26.1 renamed the moves
 * (Pledge → Highlight, Suggest Compel → Complicate, Help Out → Alter). */
const LEGACY_MOVE_NAMES: Record<string, string> = {
  pledge: "highlight",
  "suggest-compel": "complicate",
  "help-out": "alter",
  "use-floating": "use-session-boon",
};

function migrateMoveName<T extends string>(kind: string): T {
  return (LEGACY_MOVE_NAMES[kind] ?? kind) as T;
}

/** A `Proposal` as stored before 26.1: legacy `kind` strings, and the
 * session-aspect reference under its old `floatingId` name (absent entirely
 * before the moves work). */
export type LegacyProposal = Omit<
  Proposal,
  "kind" | "sessionAspectId" | "targetSlot"
> & {
  kind: string;
  floatingId?: string | null;
  sessionAspectId?: string | null;
  targetSlot?: number | null;
};

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
  /** The pre-26.1 name for `sessionAspects`. */
  floatingBoons?: LegacyFloatingBoon[];
  sessionAspects?: LegacyFloatingBoon[];
  usedAbilities?: { slot: number; kinds: string[] }[];
  proposals?: LegacyProposal[];
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
      sessionAspects: [],
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
    // Session aspects from before 23.3 carry no `kind` — every one on disk
    // that old is implicitly a Boon. Before 26.1 they were stored as
    // `floatingBoons`.
    sessionAspects: (stored.sessionAspects ?? stored.floatingBoons ?? []).map(
      (f) => ({
        ...f,
        kind: f.kind ?? "Boon",
      }),
    ),
    usedAbilities: (stored.usedAbilities ?? []).map((u) => ({
      slot: u.slot,
      kinds: u.kinds.map((k) => migrateMoveName<AbilityKind>(k)),
    })),
    // Proposals from before the moves work carry no `sessionAspectId` /
    // `targetSlot`; from before 26.1 they carry legacy `kind` strings and
    // call the session-aspect reference `floatingId`.
    proposals: (stored.proposals ?? []).map(
      ({ floatingId, sessionAspectId, kind, ...p }) => ({
        ...p,
        kind: migrateMoveName<ProposalKind>(kind),
        sessionAspectId: sessionAspectId ?? floatingId ?? null,
        targetSlot: p.targetSlot ?? null,
      }),
    ),
    session: stored.session
      ? { id: stored.session.id, goal: stored.session.goal }
      : null,
  };
}
