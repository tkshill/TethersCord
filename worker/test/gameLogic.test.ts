import { describe, expect, it } from "vitest";
import {
  applyHighlight,
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
    sessionAspects: [],
    usedAbilities: [],
    npcs: [],
    locations: [],
    ...over,
  };
}

describe("applyHighlight", () => {
  it("clamps a highlight to the character's boons and keeps committedBoons sorted", () => {
    const s = state({
      characters: [sheet({ slot: 1, fate: 3 }), sheet({ slot: 0, fate: 5 })],
      committedBoons: [{ slot: 1, count: 1 }],
    });
    const after = applyHighlight(applyHighlight(s, 1, 10), 0, 2);
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
    expect(applyHighlight(s, 0, -5).committedBoons).toEqual([]);
    expect(applyHighlight(s, 9, 1)).toBe(s);
  });
});

describe("clearSlotPendingState", () => {
  it("drops the slot's highlights and any proposal pointing at it as slot or targetSlot", () => {
    const s = state({
      committedBoons: [
        { slot: 0, count: 2 },
        { slot: 1, count: 1 },
      ],
      proposals: [
        { id: "a", kind: "highlight", proposerId: "u", proposerName: "U", slot: 0, delta: 1, sessionAspectId: null, targetSlot: null, createdAt: 1 },
        { id: "b", kind: "complicate", proposerId: "u", proposerName: "U", slot: 2, delta: 0, sessionAspectId: null, targetSlot: 0, createdAt: 2 },
        { id: "c", kind: "add-boon", proposerId: "u", proposerName: "U", slot: 1, delta: 0, sessionAspectId: null, targetSlot: null, createdAt: 3 },
      ],
    });
    const after = clearSlotPendingState(s, 0);
    expect(after.committedBoons).toEqual([{ slot: 1, count: 1 }]);
    expect(after.proposals.map((p) => p.id)).toEqual(["c"]);
  });
});

describe("markAbilityUsed", () => {
  it("adds a row, adds a kind to an existing row, and is idempotent", () => {
    let used = markAbilityUsed([], 0, "alter");
    expect(used).toEqual([{ slot: 0, kinds: ["alter"] }]);
    used = markAbilityUsed(used, 0, "add-detail");
    expect(used).toEqual([{ slot: 0, kinds: ["alter", "add-detail"] }]);
    expect(markAbilityUsed(used, 0, "alter")).toBe(used);
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
          // biome-ignore lint: legacy proposal shape has no sessionAspectId / targetSlot
          { id: "p", kind: "add-boon", proposerId: "u", proposerName: "U", slot: null, delta: 0, createdAt: 1 } as never,
        ],
        // biome-ignore lint: a pre-23.3 session aspect has no kind
        floatingBoons: [
          { id: "f", text: "a note", createdByName: "Gm", createdAt: 1 } as never,
        ],
        session: { id: "s", goal: "g" },
      },
      ["Boon", "Bane"],
    );
    expect(s.stonePool).toEqual(["Boon", "Bane"]);
    expect(s).not.toHaveProperty("pendingRoll");
    expect(s).not.toHaveProperty("overcome");
    expect(s.proposals[0]).toMatchObject({ sessionAspectId: null, targetSlot: null });
    // Every session aspect on disk before 23.3 is implicitly a Boon.
    expect(s.sessionAspects[0]).toMatchObject({ kind: "Boon", text: "a note" });
    expect(s.session).toEqual({ id: "s", goal: "g" });
  });

  it("reads the pre-26.1 move names and floating-boon fields under their new names", () => {
    const s = migrateStoneState(
      {
        stonePool: ["Boon", "Bane"],
        floatingBoons: [{ id: "f", kind: "Bane", text: "n", createdByName: "Gm" } as never],
        usedAbilities: [{ slot: 1, kinds: ["help-out", "suggest-compel", "add-detail"] }],
        proposals: [
          { id: "a", kind: "pledge", proposerId: "u", proposerName: "U", slot: 1, delta: 1, createdAt: 1 },
          { id: "b", kind: "suggest-compel", proposerId: "u", proposerName: "U", slot: 1, delta: 0, targetSlot: 2, createdAt: 1 },
          { id: "c", kind: "help-out", proposerId: "u", proposerName: "U", slot: 1, delta: 0, createdAt: 1 },
          { id: "d", kind: "use-floating", proposerId: "u", proposerName: "U", slot: 1, delta: 0, floatingId: "f", createdAt: 1 },
        ] as never,
      },
      ["Boon", "Bane"],
    );
    expect(s.proposals.map((p) => p.kind)).toEqual([
      "highlight",
      "complicate",
      "alter",
      "use-session-boon",
    ]);
    expect(s.proposals[3]).toMatchObject({ sessionAspectId: "f" });
    expect(s.proposals[3]).not.toHaveProperty("floatingId");
    expect(s.sessionAspects).toEqual([
      { id: "f", kind: "Bane", text: "n", createdByName: "Gm" },
    ]);
    expect(s.usedAbilities).toEqual([
      { slot: 1, kinds: ["alter", "complicate", "add-detail"] },
    ]);
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
