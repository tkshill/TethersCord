// worker/src/gameLogic.ts
//
// The pure rules helpers, pulled out of GameTable.ts so they can be unit-tested
// directly rather than only through SELF.fetch against the Durable Object.
// Nothing here touches storage, D1, the socket, or `this` — every function is a
// value in, a value out.

import type {
  AspectName,
  CharacterSheet,
  GameState,
  PendingRoll,
  ProposalKind,
  StoneKind,
} from "./types";

export const ASPECT_NAMES: readonly AspectName[] = [
  "archetype",
  "desire",
  "quest",
];

/**
 * Remove up to one occurrence of each stone in `toRemove` from `pool`. Stones
 * carry no identity beyond their kind, so removal is by count, not by index.
 * The facilitator-only `POST /stones/remove` route (23.2) is the one caller.
 */
export function removeStones(
  pool: StoneKind[],
  toRemove: StoneKind[],
): StoneKind[] {
  const result = [...pool];
  for (const stone of toRemove) {
    const index = result.indexOf(stone);
    if (index !== -1) result.splice(index, 1);
  }
  return result;
}

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
 * The kind a drawn pair names, when both stones match: two Boons give a Boon,
 * two Banes a Bane. A mixed draw names nothing. Decides which session aspect,
 * if any, an accepted Overcome creates.
 */
export function pairKind(stones: StoneKind[]): StoneKind | null {
  return stones.length === 2 && stones[0] === stones[1] ? stones[0] : null;
}

/** The player-facing name of a move, for the log. */
export function moveName(kind: ProposalKind): string {
  switch (kind) {
    case "highlight":
      return "Highlight";
    case "complicate":
      return "Complicate";
    case "add-detail":
      return "Add Detail";
    case "alter":
      return "Alter Fate";
    case "use-session-boon":
      return "Use Session Boon";
  }
}

export function describeStones(stones: StoneKind[]): string {
  return stones.join(", ");
}

/** A character's name for the log, falling back to its slot number. */
export function characterLabel(character: CharacterSheet): string {
  const name = character.name.trim();
  return name || `Character ${character.slot + 1}`;
}

/**
 * Drop any proposal that points at `slot` (as the proposer's own slot or as a
 * `complicate` target). Called when a sheet changes hands, so an accepted
 * proposal cannot spend or target the wrong character's boons.
 */
export function clearSlotPendingState(
  state: GameState,
  slot: number,
): GameState {
  return {
    ...state,
    proposals: state.proposals.filter(
      (p) => p.slot !== slot && p.targetSlot !== slot,
    ),
  };
}
