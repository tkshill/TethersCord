import { describe, expect, it } from "vitest";
import {
  characterLabel,
  clearSlotPendingState,
  moveName,
  randomInt,
} from "../src/gameLogic";
import type { CharacterSheet, GameState } from "../src/types";

function sheet(over: Partial<CharacterSheet> = {}): CharacterSheet {
  return {
    id: `c${over.slot ?? 0}`,
    slot: 0,
    name: "",
    notableFeatures: "",
    archetype: "",
    desire: "",
    quest: "",
    condition: "",
    notes: "",
    fate: 0,
    aspectBanes: { archetype: 0, desire: 0, quest: 0 },
    ownerId: null,
    ...over,
  };
}

function state(over: Partial<GameState> = {}): GameState {
  return {
    sessionId: "t",
    messages: [],
    die: 10,
    moves: [],
    session: null,
    characters: [],
    sessionHistory: [],
    contextAspects: [],
    junction: null,
    npcs: [],
    locations: [],
    ...over,
  };
}

describe("clearSlotPendingState", () => {
  it("closes undo on every move made from the slot", () => {
    const move = { kind: "highlight" as const, actorId: "u", actorName: "U", aspect: null, effects: [], messageId: "x" };
    const s = state({
      moves: [
        { ...move, id: "a", slot: 0 },
        { ...move, id: "b", slot: null },
        { ...move, id: "c", slot: 1 },
      ],
    });
    expect(clearSlotPendingState(s, 0).moves.map((m) => m.id)).toEqual(["b", "c"]);
  });
});

describe("small helpers", () => {
  it("characterLabel falls back to a 1-based slot number", () => {
    expect(characterLabel(sheet({ slot: 2, name: "  " }))).toBe("Character 3");
    expect(characterLabel(sheet({ name: "Bea" }))).toBe("Bea");
  });

  it("moveName gives each move its glossary name", () => {
    expect(["highlight", "highlight-context", "complicate", "create", "alter"].map((k) => moveName(k as never)))
      .toEqual(["Highlight", "Highlight Context", "Complicate", "Create", "Alter"]);
  });

  it("randomInt stays in [0, max)", () => {
    for (let i = 0; i < 200; i++) {
      const n = randomInt(6);
      expect(n).toBeGreaterThanOrEqual(0);
      expect(n).toBeLessThan(6);
    }
  });
});
