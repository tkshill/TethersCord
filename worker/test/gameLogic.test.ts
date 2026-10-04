import { describe, expect, it } from "vitest";
import {
  characterLabel,
  clearSlotPendingState,
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
    proposals: [],
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
  it("drops any proposal pointing at the slot, as its proposer or as its target", () => {
    const base = { proposerId: "u", proposerName: "U", contextAspectId: null, text: null };
    const s = state({
      proposals: [
        { ...base, id: "a", kind: "highlight", slot: 0, targetSlot: null, createdAt: 1 },
        { ...base, id: "b", kind: "complicate", slot: 2, targetSlot: 0, createdAt: 2 },
        { ...base, id: "c", kind: "highlight", slot: 1, targetSlot: null, createdAt: 3 },
      ],
    });
    expect(clearSlotPendingState(s, 0).proposals.map((p) => p.id)).toEqual(["c"]);
  });
});

describe("small helpers", () => {
  it("characterLabel falls back to a 1-based slot number", () => {
    expect(characterLabel(sheet({ slot: 2, name: "  " }))).toBe("Character 3");
    expect(characterLabel(sheet({ name: "Bea" }))).toBe("Bea");
  });

  it("randomInt stays in [0, max)", () => {
    for (let i = 0; i < 200; i++) {
      const n = randomInt(6);
      expect(n).toBeGreaterThanOrEqual(0);
      expect(n).toBeLessThan(6);
    }
  });
});
