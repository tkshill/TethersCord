// worker/src/migrateTableState.ts
//
// The DO owns one blob of state D1 does not — the die, the pending Junction,
// the proposal queue, context aspects and the session — under
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
//   sessionAspectId → contextAspectId, on a proposal (and the older `floatingId`)
//   use-session-boon → use-context-boon, a proposal kind
// Replaced by 31.2b (ADR 0001, the die ladder):
//   stonePool (and the older per-session pool and carriedBanes) → dropped;
//     a blob with no `die` starts at BASE_DIE
//   a pending stone Junction (`stones`) → dropped, so nothing is pending

import { BASE_DIE, type Die, isDie } from "./rules/dice";
import type {
  ContextAspect,
  Junction,
  Polarity,
  Proposal,
  ProposalKind,
  SessionState,
} from "./types";

/** The shape held in `KEY_TABLE_STATE` and folded into `GameState` on load. */
export type TableState = {
  die: Die;
  junction: Junction | null;
  contextAspects: ContextAspect[];
  proposals: Proposal[];
  session: SessionState | null;
};

/** A context aspect as stored under its pre-31.1 name (`sessionAspects`) or
 * pre-26.1 name (`floatingBoons`), and before 23.3 widened it with `kind` —
 * every one on disk from before that point is implicitly a Boon. */
export type LegacyContextAspect = Omit<ContextAspect, "kind" | "consumed"> & {
  kind?: Polarity;
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
  proposals?: LegacyProposal[];
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
 * every retired one — the stone pool, a stone draw left pending — is dropped.
 */
export function migrateTableState(
  stored: LegacyTableState | undefined,
): TableState {
  if (!stored) {
    return {
      die: BASE_DIE,
      junction: null,
      contextAspects: [],
      proposals: [],
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
