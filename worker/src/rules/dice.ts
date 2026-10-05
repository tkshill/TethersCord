// worker/src/rules/dice.ts
//
// The die ladder (ADR 0001, RULES.md "The die"). One die decides every
// junction; its size is its rung. The thresholds are the same on every die:
// 1–2 Critical Friction, 3–4 Friction, 5 or more Flow, the top two faces
// Critical Flow — so on a d6 every Flow is a Critical Flow.
//
// The client keeps its own copy of the ladder to disable controls at the
// ends; a shared fixture test pins the two together (31.4).

export const LADDER = [6, 8, 10, 12, 16, 20] as const;

export type Die = (typeof LADDER)[number];

/** The die's rung whenever no junction has changed it. */
export const BASE_DIE: Die = 10;

export type Outcome =
  | "critical-friction"
  | "friction"
  | "flow"
  | "critical-flow";

export type Direction = "up" | "down";

/** A face on a die, and what it means. */
export type Roll = { die: Die; face: number; outcome: Outcome };

export function isDie(value: unknown): value is Die {
  return LADDER.includes(value as Die);
}

/** The next rung up or down, or `null` past either end of the ladder. */
export function step(die: Die, direction: Direction): Die | null {
  const index = LADDER.indexOf(die) + (direction === "up" ? 1 : -1);
  return LADDER[index] ?? null;
}

export function classify(die: Die, face: number): Outcome {
  if (face <= 2) return "critical-friction";
  if (face <= 4) return "friction";
  if (face >= die - 1) return "critical-flow";
  return "flow";
}

/** Roll `die` with `source`, which returns a face from 1 to its argument. */
export function rollDie(die: Die, source: (sides: number) => number): Roll {
  const face = source(die);
  if (!Number.isInteger(face) || face < 1 || face > die) {
    throw new Error(`A d${die} cannot show ${face}`);
  }
  return { die, face, outcome: classify(die, face) };
}
