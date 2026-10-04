import { describe, expect, it } from "vitest";
import { migrateTableState } from "../src/migrateTableState";

describe("migrateTableState", () => {
  it("returns the base blob when nothing is stored", () => {
    const s = migrateTableState(undefined, ["Boon", "Bane", "Boon", "Bane"]);
    expect(s.stonePool).toEqual(["Boon", "Bane", "Boon", "Bane"]);
    expect(s).toMatchObject({ session: null });
  });

  it("folds colour-named stones, drops the retired pendingRoll/overcome fields, and defaults every field a later feature added", () => {
    const s = migrateTableState(
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
    expect(s.junction).toBeNull();
    expect(s.proposals[0]).toMatchObject({ contextAspectId: null, targetSlot: null, text: null });
    // Every session aspect on disk before 23.3 is implicitly a Boon.
    expect(s.contextAspects[0]).toMatchObject({ kind: "Boon", text: "a note" });
    expect(s.session).toEqual({ id: "s", goal: "g" });
  });

  it("reads the pre-26.1 move names and floating-boon fields under their new names", () => {
    const s = migrateTableState(
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
      "use-context-boon",
    ]);
    expect(s.proposals[3]).toMatchObject({ contextAspectId: "f" });
    expect(s.proposals[3]).not.toHaveProperty("floatingId");
    expect(s.contextAspects).toEqual([
      { id: "f", kind: "Bane", text: "n", createdByName: "Gm", consumed: false },
    ]);
  });

  it("drops state retired by 26.2: once-per-session flags, highlighted boons, and proposals of retired kinds", () => {
    const s = migrateTableState(
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

  it("keeps a pending Overcome as the Junction and reads a pre-26.2 blob's session aspects as unconsumed", () => {
    const overcome = { rolledBy: "Ada", stones: ["Boon", "Bane"], rerolls: 1, alteredSlots: [0] };
    const s = migrateTableState(
      {
        stonePool: ["Boon"],
        overcome: overcome as never,
        sessionAspects: [{ id: "f", kind: "Boon", text: "n", createdByName: "Gm" } as never],
      },
      ["Boon"],
    );
    expect(s.junction).toEqual(overcome);
    expect(s.contextAspects[0].consumed).toBe(false);
  });

  it("folds a retired per-session pool and carried-Bane count into the shared pool", () => {
    const s = migrateTableState(
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

  it("reads the names section 31.1 retired under their new names", () => {
    const junction = { rolledBy: "Ada", stones: ["Bane", "Bane"], rerolls: 0, alteredSlots: [] };
    const s = migrateTableState(
      {
        stonePool: ["Boon", "Bane"],
        overcome: junction as never,
        sessionAspects: [{ id: "f", kind: "Boon", text: "n", createdByName: "Gm", createdAt: 1, consumed: true }],
        proposals: [
          { id: "a", kind: "use-session-boon", proposerId: "u", proposerName: "U", slot: 0, sessionAspectId: "f", targetSlot: null, text: null, createdAt: 1 },
        ],
      },
      ["Boon", "Bane"],
    );
    expect(s.junction).toEqual(junction);
    expect(s.contextAspects).toEqual([
      { id: "f", kind: "Boon", text: "n", createdByName: "Gm", createdAt: 1, consumed: true },
    ]);
    expect(s.proposals[0]).toMatchObject({ kind: "use-context-boon", contextAspectId: "f" });
    expect(s.proposals[0]).not.toHaveProperty("sessionAspectId");
    expect(s).not.toHaveProperty("overcome");
    expect(s).not.toHaveProperty("sessionAspects");
  });

  it("prefers the current names when a blob carries both", () => {
    const s = migrateTableState(
      {
        stonePool: [],
        junction: null,
        overcome: { rolledBy: "Old", stones: ["Boon"], rerolls: 0, alteredSlots: [] } as never,
        contextAspects: [{ id: "new", kind: "Bane", text: "", createdByName: "Gm", createdAt: 1, consumed: false }],
        sessionAspects: [{ id: "old", kind: "Boon", text: "", createdByName: "Gm", createdAt: 1 }],
      },
      [],
    );
    expect(s.junction).toBeNull();
    expect(s.contextAspects.map((a) => a.id)).toEqual(["new"]);
  });
});
