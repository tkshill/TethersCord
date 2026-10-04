import { describe, expect, it } from "vitest";
import {
  BASE_DIE,
  classify,
  isDie,
  LADDER,
  type Outcome,
  rollDie,
  step,
} from "../../src/rules/dice";

describe("the ladder", () => {
  it("runs d6, d8, d10, d12, d16, d20 with the d10 as the base", () => {
    expect(LADDER).toEqual([6, 8, 10, 12, 16, 20]);
    expect(BASE_DIE).toBe(10);
  });

  it("recognises only the ladder's sizes as dice", () => {
    for (const die of LADDER) expect(isDie(die)).toBe(true);
    for (const other of [0, 4, 7, 14, 100, "10", null, undefined]) {
      expect(isDie(other)).toBe(false);
    }
  });
});

describe("step", () => {
  it("moves one rung up or down", () => {
    expect(step(10, "up")).toBe(12);
    expect(step(12, "up")).toBe(16);
    expect(step(10, "down")).toBe(8);
    expect(step(8, "down")).toBe(6);
  });

  it("refuses to pass either end", () => {
    expect(step(20, "up")).toBeNull();
    expect(step(6, "down")).toBeNull();
  });
});

describe("classify", () => {
  it("reads the same thresholds on every die", () => {
    const read = (die: (typeof LADDER)[number]) =>
      Array.from({ length: die }, (_, i) => classify(die, i + 1));
    const cf: Outcome = "critical-friction";
    const f: Outcome = "friction";
    const fl: Outcome = "flow";
    const cfl: Outcome = "critical-flow";
    expect(read(10)).toEqual([cf, cf, f, f, fl, fl, fl, fl, cfl, cfl]);
    expect(read(8)).toEqual([cf, cf, f, f, fl, fl, cfl, cfl]);
    expect(read(6)).toEqual([cf, cf, f, f, cfl, cfl]);
    expect(read(20).slice(16)).toEqual([fl, fl, cfl, cfl]);
  });

  it("gives both criticals two faces on every die", () => {
    for (const die of LADDER) {
      const faces = Array.from({ length: die }, (_, i) => classify(die, i + 1));
      expect(faces.filter((o) => o === "critical-friction")).toHaveLength(2);
      expect(faces.filter((o) => o === "critical-flow")).toHaveLength(2);
    }
  });
});

describe("rollDie", () => {
  it("asks the source for a face on the die's size and classifies it", () => {
    const asked: number[] = [];
    const roll = rollDie(16, (sides) => {
      asked.push(sides);
      return 15;
    });
    expect(asked).toEqual([16]);
    expect(roll).toEqual({ die: 16, face: 15, outcome: "critical-flow" });
  });

  it("rejects a face the die cannot show", () => {
    expect(() => rollDie(6, () => 7)).toThrow();
    expect(() => rollDie(6, () => 0)).toThrow();
  });
});
