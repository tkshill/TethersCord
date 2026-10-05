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
  MoveKind,
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

/** The player-facing name of a move, for the log (CONTEXT.md, "Moves"). */
export function moveName(kind: MoveKind): string {
  switch (kind) {
    case "highlight":
      return "Highlight";
    case "highlight-context":
      return "Highlight Context";
    case "complicate":
      return "Complicate";
    case "create":
      return "Create";
    case "alter":
      return "Alter";
  }
}

/** A character's name for the log, falling back to its slot number. */
export function characterLabel(character: CharacterSheet): string {
  const name = character.name.trim();
  return name || `Character ${character.slot + 1}`;
}

/**
 * Close the undo window on every move made from `slot`. Called when a sheet
 * changes hands, so an undo cannot refund or take boons from whoever holds it
 * next.
 */
export function clearSlotPendingState<T extends Pick<GameState, "moves">>(
  state: T,
  slot: number,
): T {
  return { ...state, moves: state.moves.filter((m) => m.slot !== slot) };
}
