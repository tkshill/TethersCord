// worker/src/gameLogic.ts
//
// The pure rules helpers, pulled out of GameTable.ts so they can be unit-tested
// directly rather than only through SELF.fetch against the Durable Object.
// Nothing here touches storage, D1, the socket, or `this` — every function is a
// value in, a value out.

import type {
  AbilityKind,
  AspectName,
  CharacterSheet,
  CommittedBoon,
  GameState,
  PendingRoll,
  StoneKind,
  UsedAbilities,
} from "./types";

export const ASPECT_NAMES: readonly AspectName[] = [
  "archetype",
  "desire",
  "quest",
];

/** Rejection sampling, so the low indices are not favoured by modulo bias. */
export function randomInt(maxExclusive: number): number {
  const limit = Math.floor(0x100000000 / maxExclusive) * maxExclusive;
  const buf = new Uint32Array(1);

  do {
    crypto.getRandomValues(buf);
  } while (buf[0] >= limit);

  return buf[0] % maxExclusive;
}

/** Draw two stones from `pool` at random, returning the drawn pair and the rest. */
export function pickTwoRandom(pool: StoneKind[]): PendingRoll {
  const indices = pool.map((_, i) => i);

  for (let i = indices.length - 1; i > 0; i--) {
    const j = randomInt(i + 1);
    [indices[i], indices[j]] = [indices[j], indices[i]];
  }

  const chosenIndices = new Set(indices.slice(0, Math.min(2, indices.length)));
  const chosen: StoneKind[] = [];
  const rest: StoneKind[] = [];

  pool.forEach((stone, i) => {
    if (chosenIndices.has(i)) {
      chosen.push(stone);
    } else {
      rest.push(stone);
    }
  });

  return { chosen, rest };
}

/**
 * Section 19 stone routing for an accepted overcome roll, kept pure so it can be
 * unit-tested exhaustively. `marksAspect` is true only for a mixed draw against
 * a not-untethered target — the caller then picks which aspect at random and
 * writes it; otherwise every drawn stone is returned in `poolAdds`.
 */
export function routeOvercomeDraw(
  drawn: StoneKind[],
  untetheredTarget: boolean,
): { poolAdds: StoneKind[]; marksAspect: boolean } {
  const boons = drawn.filter((s) => s === "Boon").length;
  if (drawn.length === 2 && boons === 1 && !untetheredTarget) {
    return { poolAdds: ["Boon"], marksAspect: true };
  }
  return { poolAdds: [...drawn], marksAspect: false };
}

/**
 * The weighted draw bag for untethering: one `{ slot, aspect }` entry per Bane
 * on every aspect of every character. Pure; the caller draws from it at random.
 */
export function aspectBaneBag(
  characters: readonly Pick<CharacterSheet, "slot" | "aspectBanes">[],
): { slot: number; aspect: AspectName }[] {
  const bag: { slot: number; aspect: AspectName }[] = [];
  for (const c of characters) {
    for (const aspect of ASPECT_NAMES) {
      for (let i = 0; i < c.aspectBanes[aspect]; i++) {
        bag.push({ slot: c.slot, aspect });
      }
    }
  }
  return bag;
}

export function describeStones(stones: StoneKind[]): string {
  return stones.join(", ");
}

/** A character's name for the log, falling back to its slot number. */
export function characterLabel(character: CharacterSheet): string {
  const name = character.name.trim();
  return name || `Character ${character.slot + 1}`;
}

export function totalCommittedBoons(committed: CommittedBoon[]): number {
  return committed.reduce((sum, c) => sum + c.count, 0);
}

/**
 * Pledge (`delta` +1) or withdraw (-1) one of a character's own boons on the
 * next roll, clamped to what they hold. Shared by the direct pledge route and
 * an accepted `pledge` proposal.
 */
export function applyPledge(
  state: GameState,
  slot: number,
  delta: number,
): GameState {
  const character = state.characters.find((c) => c.slot === slot);
  if (!character) return state;

  const current =
    state.committedBoons.find((c) => c.slot === slot)?.count ?? 0;
  const next = Math.max(0, Math.min(character.fate, current + delta));

  const committedBoons = state.committedBoons.filter((c) => c.slot !== slot);
  if (next > 0) {
    committedBoons.push({ slot, count: next });
  }
  committedBoons.sort((a, b) => a.slot - b.slot);
  return { ...state, committedBoons };
}

/**
 * Drop a slot's pledged boons and any proposal that points at it (as the
 * proposer's own slot or as a `suggest-compel` target). Called when a sheet
 * changes hands, so an accepted roll or proposal cannot spend or target the
 * wrong character's boons.
 */
export function clearSlotPendingState(
  state: GameState,
  slot: number,
): GameState {
  return {
    ...state,
    committedBoons: state.committedBoons.filter((c) => c.slot !== slot),
    proposals: state.proposals.filter(
      (p) => p.slot !== slot && p.targetSlot !== slot,
    ),
  };
}

/** Record `kind` as spent for `slot` this session; idempotent. */
export function markAbilityUsed(
  used: UsedAbilities[],
  slot: number,
  kind: AbilityKind,
): UsedAbilities[] {
  const row = used.find((u) => u.slot === slot);
  if (!row) return [...used, { slot, kinds: [kind] }];
  if (row.kinds.includes(kind)) return used;
  return used.map((u) =>
    u.slot === slot ? { ...u, kinds: [...u.kinds, kind] } : u,
  );
}
