// worker/src/migrateTableState.ts
//
// The DO owns one blob of state D1 does not — the die, the pending Junction,
// context aspects, the moves still open to undo, and the session — under
// `KEY_TABLE_STATE`. This module keeps the load-time compatibility handling
// (missing fields added by later features, retired fields dropped, and the
// names section 31 retired) out of the main flow, so it is easy to delete once
// no old blob can still be on disk.
//
// This is the one place the stored blob's old names are translated. Every
// `Legacy*` type below spells a field as some earlier build wrote it; the
// current names are in `CONTEXT.md`. Renamed by section 31.1:
//   overcome        → junction
//   sessionAspects  → contextAspects (and the older `floatingBoons`)
// Replaced by 31.2b (ADR 0001, the die ladder):
//   stonePool (and the older per-session pool and carriedBanes) → dropped;
//     a blob with no `die` starts at BASE_DIE
//   a pending stone Junction (`stones`) → dropped, so nothing is pending
// Replaced by 31.3 (ADR 0002, direct moves and undo):
//   proposals → dropped; queued moves are not made, and nothing is undoable
//   a context aspect with no `fromAspect` → null

import { BASE_DIE, type Die, isDie } from "./rules/dice";
import type {
  ContextAspect,
  Junction,
  MoveRecord,
  Polarity,
  SessionState,
} from "./types";

/** The shape held in `KEY_TABLE_STATE` and folded into `GameState` on load. */
export type TableState = {
  die: Die;
  junction: Junction | null;
  contextAspects: ContextAspect[];
  moves: MoveRecord[];
  session: SessionState | null;
};

/** A context aspect as stored under its pre-31.1 name (`sessionAspects`) or
 * pre-26.1 name (`floatingBoons`), before 23.3 widened it with `kind` — every
 * one on disk from before that point is implicitly a Boon — and before 31.3
 * added `fromAspect`. */
export type LegacyContextAspect = Omit<
  ContextAspect,
  "kind" | "consumed" | "fromAspect"
> & {
  kind?: Polarity;
  consumed?: boolean;
  fromAspect?: ContextAspect["fromAspect"];
};

export type LegacyTableState = {
  /** Added by 31.2b; absent from every older blob. */
  die?: number;
  /** Retired by 31.2b with the rest of the stone pool. Read and dropped. */
  stonePool?: unknown;
  /** Retired along with the roll/reroll/accept lifecycle (23.1). Read and
   * dropped. */
  pendingRoll?: unknown;
  /** Since 31.2b a die roll; before it a stone draw (`stones`), which is
   * dropped. */
  junction?: Junction | LegacyStoneJunction | null;
  /** The pre-31.1 name for `junction`: the pre-23.1 `{ targetSlot }` or the
   * 26.2 stone Overcome. Both are dropped now. */
  overcome?: unknown;
  /** Retired (26.2): highlighted boons no longer exist. Read and dropped. */
  committedBoons?: unknown;
  contextAspects?: LegacyContextAspect[];
  /** The pre-31.1 name for `contextAspects`. */
  sessionAspects?: LegacyContextAspect[];
  /** The pre-26.1 name for `contextAspects`. */
  floatingBoons?: LegacyContextAspect[];
  /** Retired (26.2): moves are not once-per-session. Read and dropped. */
  usedAbilities?: unknown;
  /** Retired by 31.3: the approval queue. Read and dropped. */
  proposals?: unknown;
  /** Added by 31.3. */
  moves?: MoveRecord[];
  session?:
    | (Pick<SessionState, "id" | "goal"> & {
        startedAt?: number;
        /** Retired per-session pool. Read and dropped. */
        pool?: unknown;
        carriedBanes?: number;
      })
    | null;
  /** Retired: Banes the next session's pool used to inherit. Read and
   * dropped. */
  carriedBanes?: number;
  lastSessionFailed?: boolean;
  untether?: unknown;
};

/** A Junction as stored while the stone pool existed (26.2 to 31.2a). */
export type LegacyStoneJunction = {
  rolledBy: string;
  stones: Polarity[];
  rerolls: number;
  alteredSlots: number[];
};

function isDieJunction(value: unknown): value is Junction {
  const junction = value as Junction | null;
  return (
    typeof junction === "object" &&
    junction !== null &&
    isDie(junction.die) &&
    Number.isInteger(junction.face)
  );
}

/**
 * Fold a stored `KEY_TABLE_STATE` blob (or nothing, on a cold table) into the
 * current `TableState`: every field a later feature added is defaulted, and
 * every retired one — the stone pool, a stone draw left pending, the proposal
 * queue — is dropped.
 */
export function migrateTableState(
  stored: LegacyTableState | undefined,
): TableState {
  if (!stored) {
    return {
      die: BASE_DIE,
      junction: null,
      contextAspects: [],
      moves: [],
      session: null,
    };
  }

  return {
    die: isDie(stored.die) ? stored.die : BASE_DIE,
    // A pending stone draw cannot be read as a die roll, so it is dropped and
    // the table rolls again; so is anything older under `overcome`.
    junction: isDieJunction(stored.junction) ? stored.junction : null,
    // Context aspects from before 23.3 carry no `kind` — every one on disk
    // that old is implicitly a Boon. Before 31.1 they were stored as
    // `sessionAspects`, before 26.1 as `floatingBoons`.
    contextAspects: (
      stored.contextAspects ??
      stored.sessionAspects ??
      stored.floatingBoons ??
      []
    ).map((f) => ({
      ...f,
      kind: f.kind ?? "Boon",
      consumed: f.consumed ?? false,
      fromAspect: f.fromAspect ?? null,
    })),
    moves: stored.moves ?? [],
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
