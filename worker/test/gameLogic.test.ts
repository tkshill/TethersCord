import { describe, expect, it } from "vitest";
import {
  characterLabel,
  clearSlotPendingState,
  describeStones,
  pairKind,
  pickTwoRandom,
  removeStones,
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
    proposals: [],
    session: null,
    characters: [],
    sessionHistory: [],
    sessionAspects: [],
    overcome: null,
    npcs: [],
    locations: [],
    ...over,
  };
}

describe("clearSlotPendingState", () => {
  it("drops any proposal pointing at the slot, as its proposer or as its target", () => {
    const base = { proposerId: "u", proposerName: "U", sessionAspectId: null, text: null };
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
          // biome-ignore lint: legacy proposal shape has no sessionAspectId / targetSlot / text
          { id: "p", kind: "highlight", proposerId: "u", proposerName: "U", slot: 0, createdAt: 1 } as never,
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
    // The pre-23.1 `{ targetSlot }` overcome is not the current `Overcome`.
    expect(s.overcome).toBeNull();
    expect(s.proposals[0]).toMatchObject({ sessionAspectId: null, targetSlot: null, text: null });
    // Every session aspect on disk before 23.3 is implicitly a Boon.
    expect(s.sessionAspects[0]).toMatchObject({ kind: "Boon", text: "a note" });
    expect(s.session).toEqual({ id: "s", goal: "g" });
  });

  it("reads the pre-26.1 move names and floating-boon fields under their new names", () => {
    const s = migrateStoneState(
      {
        stonePool: ["Boon", "Bane"],
        floatingBoons: [{ id: "f", kind: "Bane", text: "n", createdByName: "Gm" } as never],
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
      { id: "f", kind: "Bane", text: "n", createdByName: "Gm", consumed: false },
    ]);
  });

  it("drops state retired by 26.2: once-per-session flags, highlighted boons, and proposals of retired kinds", () => {
    const s = migrateStoneState(
      {
        stonePool: ["Boon", "Bane"],
        committedBoons: [{ slot: 0, count: 2 }],
        usedAbilities: [{ slot: 0, kinds: ["add-detail"] }],
        proposals: [
          { id: "a", kind: "add-boon", proposerId: "u", proposerName: "U", slot: null, delta: 1, createdAt: 1 },
          { id: "b", kind: "gain-insight", proposerId: "u", proposerName: "U", slot: 0, delta: 0, createdAt: 1 },
          { id: "c", kind: "accept-compel", proposerId: "u", proposerName: "U", slot: 0, delta: 2, createdAt: 1 },
          { id: "d", kind: "pledge", proposerId: "u", proposerName: "U", slot: 0, delta: 3, createdAt: 1 },
          { id: "e", kind: "add-detail", proposerId: "u", proposerName: "U", slot: 0, delta: 0, createdAt: 1 },
        ] as never,
      },
      ["Boon", "Bane"],
    );
    expect(s).not.toHaveProperty("committedBoons");
    expect(s).not.toHaveProperty("usedAbilities");
    expect(s.proposals.map((p) => p.kind)).toEqual(["highlight", "add-detail"]);
    expect(s.proposals[0]).not.toHaveProperty("delta");
    expect(s.proposals[1]).toMatchObject({ text: null });
  });

  it("keeps a current pending Overcome and reads a pre-26.2 blob's session aspects as unconsumed", () => {
    const overcome = { rolledBy: "Ada", stones: ["Boon", "Bane"], rerolls: 1, alteredSlots: [0] };
    const s = migrateStoneState(
      {
        stonePool: ["Boon"],
        overcome: overcome as never,
        sessionAspects: [{ id: "f", kind: "Boon", text: "n", createdByName: "Gm" } as never],
      },
      ["Boon"],
    );
    expect(s.overcome).toEqual(overcome);
    expect(s.sessionAspects[0].consumed).toBe(false);
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
