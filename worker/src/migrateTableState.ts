// worker/src/migrateTableState.ts
//
// The DO owns one blob of state D1 does not — the stone pool, the pending
// Junction, the proposal queue, context aspects and the session — under
// `KEY_TABLE_STATE`. This module keeps the load-time compatibility handling
// (colour-named stones, missing fields added by later features, retired fields
// folded forward, and the names section 31 retired) out of the main flow, so it
// is easy to delete once no old blob can still be on disk.
//
// This is the one place the stored blob's old names are translated. Every
// `Legacy*` type below spells a field as some earlier build wrote it; the
// current names are in `CONTEXT.md`. Renamed by section 31.1:
//   overcome        → junction
//   sessionAspects  → contextAspects (and the older `floatingBoons`)
//   sessionAspectId → contextAspectId, on a proposal (and the older `floatingId`)
//   use-session-boon → use-context-boon, a proposal kind

import type {
  ContextAspect,
  Junction,
  Proposal,
  ProposalKind,
  SessionState,
  StoneKind,
} from "./types";

/** The shape held in `KEY_TABLE_STATE` and folded into `GameState` on load. */
export type TableState = {
  stonePool: StoneKind[];
  junction: Junction | null;
  contextAspects: ContextAspect[];
  proposals: Proposal[];
  session: SessionState | null;
};

/** Shape of `KEY_TABLE_STATE` as written by builds before the session pool and the
 * roll bag were merged into one pool, and before untethering was retired. */
export type LegacyStoneKind = StoneKind | "WhiteStone" | "BlackStone";

/** A context aspect as stored under its pre-31.1 name (`sessionAspects`) or
 * pre-26.1 name (`floatingBoons`), and before 23.3 widened it with `kind` —
 * every one on disk from before that point is implicitly a Boon. */
export type LegacyContextAspect = Omit<ContextAspect, "kind" | "consumed"> & {
  kind?: StoneKind;
  consumed?: boolean;
};

/** Proposal kinds and ability kinds as stored before 26.1 renamed the moves
 * (Pledge → Highlight, Suggest Compel → Complicate, Help Out → Alter), and
 * before 31.1 renamed session boons to context boons. */
const LEGACY_MOVE_NAMES: Record<string, string> = {
  pledge: "highlight",
  "suggest-compel": "complicate",
  "help-out": "alter",
  "use-floating": "use-context-boon",
  "use-session-boon": "use-context-boon",
};

/** Proposal kinds 26.2 removed. A proposal of one of these is dropped on load:
 * its move no longer exists, so it could never be resolved. */
const RETIRED_PROPOSAL_KINDS: ReadonlySet<string> = new Set([
  "add-boon",
  "gain-insight",
  "accept-compel",
]);

function migrateMoveName<T extends string>(kind: string): T {
  return (LEGACY_MOVE_NAMES[kind] ?? kind) as T;
}

/** A `Proposal` as stored by earlier builds: legacy `kind` strings, and the
 * context-aspect reference under its pre-31.1 name `sessionAspectId` or its
 * pre-26.1 name `floatingId` (absent entirely before the moves work). */
export type LegacyProposal = Omit<
  Proposal,
  "kind" | "contextAspectId" | "targetSlot" | "text"
> & {
  kind: string;
  /** Retired (26.2): Highlight is always one boon. */
  delta?: number;
  floatingId?: string | null;
  sessionAspectId?: string | null;
  contextAspectId?: string | null;
  targetSlot?: number | null;
  text?: string | null;
};

export type LegacyTableState = {
  stonePool: LegacyStoneKind[];
  /** Retired along with the roll/reroll/accept lifecycle (23.1) — a draw is
   * now a read-only, stateless action, so nothing is left pending between
   * requests. Read for old blobs but dropped from `TableState`. */
  pendingRoll?: {
    chosen: LegacyStoneKind[];
    rest: LegacyStoneKind[];
  } | null;
  junction?: Junction | null;
  /** The pre-31.1 name for `junction`, in two shapes: the pre-23.1
   * `{ targetSlot }` (a named target, since retired, read and dropped) and the
   * 26.2 Overcome, which has the `Junction` shape. */
  overcome?: Junction | { targetSlot: number } | null;
  /** Retired (26.2): highlighted boons no longer exist. Read and dropped. */
  committedBoons?: unknown;
  contextAspects?: LegacyContextAspect[];
  /** The pre-31.1 name for `contextAspects`. */
  sessionAspects?: LegacyContextAspect[];
  /** The pre-26.1 name for `contextAspects`. */
  floatingBoons?: LegacyContextAspect[];
  /** Retired (26.2): moves are not once-per-session. Read and dropped. */
  usedAbilities?: unknown;
  proposals?: LegacyProposal[];
  session?:
    | (Pick<SessionState, "id" | "goal"> & {
        startedAt?: number;
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

function isJunction(value: unknown): value is Junction {
  return (
    typeof value === "object" &&
    value !== null &&
    Array.isArray((value as Junction).stones)
  );
}

function migrateStoneKind(kind: LegacyStoneKind): StoneKind {
  if (kind === "WhiteStone") return "Boon";
  if (kind === "BlackStone") return "Bane";
  return kind;
}

/**
 * Fold a stored `KEY_TABLE_STATE` blob (or nothing, on a cold table) into the
 * current `TableState`: colour-named stones become Boon / Bane, every field a
 * later feature added is defaulted, and the retired per-session pool and
 * carried-Bane count are folded into the single shared `stonePool` so no
 * stones already in play vanish. `initialPool` is `INITIAL_STONE_POOL`.
 */
export function migrateTableState(
  stored: LegacyTableState | undefined,
  initialPool: readonly StoneKind[],
): TableState {
  if (!stored) {
    return {
      stonePool: [...initialPool],
      junction: null,
      contextAspects: [],
      proposals: [],
      session: null,
    };
  }

  const legacySessionPool = (stored.session?.pool ?? []).map(migrateStoneKind);
  const legacyCarriedBanes = Array<StoneKind>(stored.carriedBanes ?? 0).fill(
    "Bane",
  );

  // A blob written since 31.1 has `junction` (possibly null) and no
  // `overcome`; an older one has only `overcome`.
  const storedJunction =
    "junction" in stored ? stored.junction : stored.overcome;

  return {
    stonePool: [
      ...stored.stonePool.map(migrateStoneKind),
      ...legacySessionPool,
      ...legacyCarriedBanes,
    ],
    junction: isJunction(storedJunction) ? storedJunction : null,
    // Context aspects from before 23.3 carry no `kind` — every one on disk
    // that old is implicitly a Boon. Before 31.1 they were stored as
    // `sessionAspects`, before 26.1 as `floatingBoons`.
    contextAspects: (
      stored.contextAspects ??
      stored.sessionAspects ??
      stored.floatingBoons ??
      []
    ).map(
      (f) => ({
        ...f,
        kind: f.kind ?? "Boon",
        consumed: f.consumed ?? false,
      }),
    ),
    // Proposals from before the moves work carry no context-aspect reference
    // or `targetSlot`; from before 26.1 they carry legacy `kind` strings and
    // call the reference `floatingId`, and before 31.1 `sessionAspectId`.
    proposals: (stored.proposals ?? [])
      .filter((p) => !RETIRED_PROPOSAL_KINDS.has(p.kind))
      .map(
        ({
          floatingId,
          sessionAspectId,
          contextAspectId,
          kind,
          delta: _delta,
          ...p
        }) => ({
          ...p,
          kind: migrateMoveName<ProposalKind>(kind),
          contextAspectId:
            contextAspectId ?? sessionAspectId ?? floatingId ?? null,
          targetSlot: p.targetSlot ?? null,
          text: p.text ?? null,
        }),
      ),
    // `startedAt` arrived with 31.2a; an older running session has 0, which
    // `GameTable` backfills from its `game_sessions` row on load.
    session: stored.session
      ? {
          id: stored.session.id,
          goal: stored.session.goal,
          startedAt: stored.session.startedAt ?? 0,
        }
      : null,
  };
}
