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
  ProposalKind,
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
    case "use-context-boon":
      return "Use Context Boon";
  }
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
export function clearSlotPendingState<T extends Pick<GameState, "proposals">>(
  state: T,
  slot: number,
): T {
  return {
    ...state,
    proposals: state.proposals.filter(
      (p) => p.slot !== slot && p.targetSlot !== slot,
    ),
  };
}
