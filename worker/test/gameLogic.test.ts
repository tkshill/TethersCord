import { describe, expect, it } from "vitest";
import {
  applyPledge,
  characterLabel,
  clearSlotPendingState,
  describeStones,
  markAbilityUsed,
  pickTwoRandom,
  removeStones,
  totalCommittedBoons,
} from "../src/gameLogic";
import { migrateStoneState } from "../src/migrateStoneState";
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
    committedBoons: [],
    proposals: [],
    session: null,
    characters: [],
    sessionHistory: [],
    floatingBoons: [],
    usedAbilities: [],
    npcs: [],
    locations: [],
    ...over,
  };
}

describe("applyPledge", () => {
  it("clamps a pledge to the character's boons and keeps committedBoons sorted", () => {
    const s = state({
      characters: [sheet({ slot: 1, fate: 3 }), sheet({ slot: 0, fate: 5 })],
      committedBoons: [{ slot: 1, count: 1 }],
    });
    const after = applyPledge(applyPledge(s, 1, 10), 0, 2);
    expect(after.committedBoons).toEqual([
      { slot: 0, count: 2 },
      { slot: 1, count: 3 },
    ]);
  });

  it("drops a slot's entry when a withdrawal takes it to zero, and no-ops an unknown slot", () => {
    const s = state({
      characters: [sheet({ slot: 0, fate: 2 })],
      committedBoons: [{ slot: 0, count: 1 }],
    });
    expect(applyPledge(s, 0, -5).committedBoons).toEqual([]);
    expect(applyPledge(s, 9, 1)).toBe(s);
  });
});

describe("clearSlotPendingState", () => {
  it("drops the slot's pledges and any proposal pointing at it as slot or targetSlot", () => {
    const s = state({
      committedBoons: [
        { slot: 0, count: 2 },
        { slot: 1, count: 1 },
      ],
      proposals: [
        { id: "a", kind: "pledge", proposerId: "u", proposerName: "U", slot: 0, delta: 1, floatingId: null, targetSlot: null, createdAt: 1 },
        { id: "b", kind: "suggest-compel", proposerId: "u", proposerName: "U", slot: 2, delta: 0, floatingId: null, targetSlot: 0, createdAt: 2 },
        { id: "c", kind: "add-boon", proposerId: "u", proposerName: "U", slot: 1, delta: 0, floatingId: null, targetSlot: null, createdAt: 3 },
      ],
    });
    const after = clearSlotPendingState(s, 0);
    expect(after.committedBoons).toEqual([{ slot: 1, count: 1 }]);
    expect(after.proposals.map((p) => p.id)).toEqual(["c"]);
  });
});

describe("markAbilityUsed", () => {
  it("adds a row, adds a kind to an existing row, and is idempotent", () => {
    let used = markAbilityUsed([], 0, "help-out");
    expect(used).toEqual([{ slot: 0, kinds: ["help-out"] }]);
    used = markAbilityUsed(used, 0, "add-detail");
    expect(used).toEqual([{ slot: 0, kinds: ["help-out", "add-detail"] }]);
    expect(markAbilityUsed(used, 0, "help-out")).toBe(used);
  });
});

describe("small helpers", () => {
  it("totalCommittedBoons sums counts", () => {
    expect(
      totalCommittedBoons([
        { slot: 0, count: 2 },
        { slot: 1, count: 3 },
      ]),
    ).toBe(5);
  });

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

describe("migrateStoneState", () => {
  it("returns the base blob when nothing is stored", () => {
    const s = migrateStoneState(undefined, ["Boon", "Bane", "Boon", "Bane"]);
    expect(s.stonePool).toEqual(["Boon", "Bane", "Boon", "Bane"]);
    expect(s).toMatchObject({ session: null });
  });

  it("folds colour-named stones, drops the retired pendingRoll/overcome fields, and defaults every field a later feature added", () => {
    const s = migrateStoneState(
      {
        stonePool: ["WhiteStone", "BlackStone"],
        // A pre-23.1 blob may still carry these; they are read without error
        // and simply dropped, like every other retired field.
        pendingRoll: { chosen: ["WhiteStone"], rest: ["BlackStone"] },
        overcome: { targetSlot: 1 },
        proposals: [
          // biome-ignore lint: legacy proposal shape has no floatingId / targetSlot
          { id: "p", kind: "add-boon", proposerId: "u", proposerName: "U", slot: null, delta: 0, createdAt: 1 } as never,
        ],
        session: { id: "s", goal: "g" },
      },
      ["Boon", "Bane"],
    );
    expect(s.stonePool).toEqual(["Boon", "Bane"]);
    expect(s).not.toHaveProperty("pendingRoll");
    expect(s).not.toHaveProperty("overcome");
    expect(s.proposals[0]).toMatchObject({ floatingId: null, targetSlot: null });
    expect(s.session).toEqual({ id: "s", goal: "g" });
  });

  it("folds a retired per-session pool and carried-Bane count into the shared pool", () => {
    const s = migrateStoneState(
      {
        stonePool: ["Boon", "Bane"],
        session: { id: "s", goal: "g", pool: ["Boon", "Bane", "Bane"] },
        carriedBanes: 2,
      },
      ["Boon", "Bane"],
    );
    expect(s.stonePool.filter((k) => k === "Boon")).toHaveLength(2);
    expect(s.stonePool.filter((k) => k === "Bane")).toHaveLength(5);
    expect(s.session).toEqual({ id: "s", goal: "g" });
  });
});
