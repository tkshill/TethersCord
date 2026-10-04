import { describe, expect, it } from "vitest";
import {
  characterLabel,
  clearSlotPendingState,
  describeStones,
  pairKind,
  pickTwoRandom,
  removeStones,
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
    stonePool: [],
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

  it("describeStones joins with a comma", () => {
    expect(describeStones(["Boon", "Bane"])).toBe("Boon, Bane");
  });

  it("pickTwoRandom draws two and returns the rest, order-independent", () => {
    const { chosen, rest } = pickTwoRandom(["Boon", "Bane", "Boon", "Bane"]);
    expect(chosen).toHaveLength(2);
    expect(rest).toHaveLength(2);
    expect([...chosen, ...rest].sort()).toEqual(
      ["Bane", "Bane", "Boon", "Boon"],
    );
  });

  it("removeStones drops by count, not identity, and no-ops what isn't there", () => {
    expect(removeStones(["Boon", "Bane", "Boon"], ["Boon"])).toEqual([
      "Bane",
      "Boon",
    ]);
    expect(removeStones(["Boon"], ["Bane"])).toEqual(["Boon"]);
    expect(removeStones(["Boon", "Bane"], ["Boon", "Bane", "Boon"])).toEqual(
      [],
    );
  });
});

describe("pairKind", () => {
  it("names the kind of a matched pair and nothing for a mixed draw", () => {
    expect(pairKind(["Boon", "Boon"])).toBe("Boon");
    expect(pairKind(["Bane", "Bane"])).toBe("Bane");
    expect(pairKind(["Boon", "Bane"])).toBeNull();
    expect(pairKind(["Bane", "Boon"])).toBeNull();
  });
});
