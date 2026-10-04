import { describe, expect, it } from "vitest";
import { migrateTableState } from "../src/migrateTableState";

describe("migrateTableState", () => {
  it("returns the base blob when nothing is stored", () => {
    expect(migrateTableState(undefined)).toEqual({
      die: 10,
      junction: null,
      contextAspects: [],
      proposals: [],
      session: null,
    });
  });

  it("keeps a stored die and a pending die roll", () => {
    const junction = { rolledBy: "Ada", die: 12, face: 3, outcome: "friction", rerolls: 1, alteredSlots: [0] };
    const s = migrateTableState({ die: 16, junction: junction as never });
    expect(s.die).toBe(16);
    expect(s.junction).toEqual(junction);
  });

  it("starts at the base die when the stored one is missing or off the ladder", () => {
    expect(migrateTableState({}).die).toBe(10);
    expect(migrateTableState({ die: 7 }).die).toBe(10);
  });

  it("drops the stone pool, a pending stone draw, and every older stone field (31.2b)", () => {
    const s = migrateTableState({
      stonePool: ["WhiteStone", "BlackStone", "Boon"],
      pendingRoll: { chosen: ["WhiteStone"], rest: ["BlackStone"] },
      junction: { rolledBy: "Ada", stones: ["Boon", "Boon"], rerolls: 0, alteredSlots: [] },
      carriedBanes: 2,
      session: { id: "s", goal: "g", pool: ["Boon", "Bane"] },
    });
    expect(s.die).toBe(10);
    expect(s.junction).toBeNull();
    expect(s).not.toHaveProperty("stonePool");
    expect(s).not.toHaveProperty("pendingRoll");
    expect(s).not.toHaveProperty("carriedBanes");
    expect(s.session).toEqual({ id: "s", goal: "g", startedAt: 0 });
  });

  it("drops a pending Overcome under its pre-31.1 name, in either old shape", () => {
    for (const overcome of [
      { targetSlot: 1 },
      { rolledBy: "Ada", stones: ["Boon", "Bane"], rerolls: 1, alteredSlots: [0] },
    ]) {
      expect(migrateTableState({ overcome }).junction).toBeNull();
    }
  });

  it("defaults every context aspect and proposal field a later feature added", () => {
    const s = migrateTableState({
      proposals: [
        // biome-ignore lint: legacy proposal shape has no contextAspectId / targetSlot / text
        { id: "p", kind: "highlight", proposerId: "u", proposerName: "U", slot: 0, createdAt: 1 } as never,
      ],
      // biome-ignore lint: a pre-23.3 aspect has no kind
      floatingBoons: [{ id: "f", text: "a note", createdByName: "Gm", createdAt: 1 } as never],
    });
    expect(s.proposals[0]).toMatchObject({ contextAspectId: null, targetSlot: null, text: null });
    // Every aspect on disk before 23.3 is implicitly a Boon.
    expect(s.contextAspects[0]).toMatchObject({ kind: "Boon", text: "a note", consumed: false });
  });

  it("reads the pre-26.1 move names and floating-boon fields under their new names", () => {
    const s = migrateTableState({
      floatingBoons: [{ id: "f", kind: "Bane", text: "n", createdByName: "Gm" } as never],
      proposals: [
        { id: "a", kind: "pledge", proposerId: "u", proposerName: "U", slot: 1, delta: 1, createdAt: 1 },
        { id: "b", kind: "suggest-compel", proposerId: "u", proposerName: "U", slot: 1, delta: 0, targetSlot: 2, createdAt: 1 },
        { id: "c", kind: "help-out", proposerId: "u", proposerName: "U", slot: 1, delta: 0, createdAt: 1 },
        { id: "d", kind: "use-floating", proposerId: "u", proposerName: "U", slot: 1, delta: 0, floatingId: "f", createdAt: 1 },
      ] as never,
    });
    expect(s.proposals.map((p) => p.kind)).toEqual(["highlight", "complicate", "alter", "use-context-boon"]);
    expect(s.proposals[3]).toMatchObject({ contextAspectId: "f" });
    expect(s.proposals[3]).not.toHaveProperty("floatingId");
    expect(s.contextAspects).toEqual([
      { id: "f", kind: "Bane", text: "n", createdByName: "Gm", consumed: false },
    ]);
  });

  it("drops state retired by 26.2: once-per-session flags, highlighted boons, and proposals of retired kinds", () => {
    const s = migrateTableState({
      committedBoons: [{ slot: 0, count: 2 }],
      usedAbilities: [{ slot: 0, kinds: ["add-detail"] }],
      proposals: [
        { id: "a", kind: "add-boon", proposerId: "u", proposerName: "U", slot: null, delta: 1, createdAt: 1 },
        { id: "b", kind: "gain-insight", proposerId: "u", proposerName: "U", slot: 0, delta: 0, createdAt: 1 },
        { id: "c", kind: "accept-compel", proposerId: "u", proposerName: "U", slot: 0, delta: 2, createdAt: 1 },
        { id: "d", kind: "pledge", proposerId: "u", proposerName: "U", slot: 0, delta: 3, createdAt: 1 },
        { id: "e", kind: "add-detail", proposerId: "u", proposerName: "U", slot: 0, delta: 0, createdAt: 1 },
      ] as never,
    });
    expect(s).not.toHaveProperty("committedBoons");
    expect(s).not.toHaveProperty("usedAbilities");
    expect(s.proposals.map((p) => p.kind)).toEqual(["highlight", "add-detail"]);
    expect(s.proposals[0]).not.toHaveProperty("delta");
    expect(s.proposals[1]).toMatchObject({ text: null });
  });

  it("reads the context-aspect names section 31.1 retired under their new names", () => {
    const s = migrateTableState({
      sessionAspects: [{ id: "f", kind: "Boon", text: "n", createdByName: "Gm", createdAt: 1, consumed: true }],
      proposals: [
        { id: "a", kind: "use-session-boon", proposerId: "u", proposerName: "U", slot: 0, sessionAspectId: "f", targetSlot: null, text: null, createdAt: 1 },
      ],
    });
    expect(s.contextAspects).toEqual([
      { id: "f", kind: "Boon", text: "n", createdByName: "Gm", createdAt: 1, consumed: true },
    ]);
    expect(s.proposals[0]).toMatchObject({ kind: "use-context-boon", contextAspectId: "f" });
    expect(s.proposals[0]).not.toHaveProperty("sessionAspectId");
    expect(s).not.toHaveProperty("sessionAspects");
  });

  it("prefers the current names when a blob carries both", () => {
    const s = migrateTableState({
      contextAspects: [{ id: "new", kind: "Bane", text: "", createdByName: "Gm", createdAt: 1, consumed: false }],
      sessionAspects: [{ id: "old", kind: "Boon", text: "", createdByName: "Gm", createdAt: 1 }],
    });
    expect(s.contextAspects.map((a) => a.id)).toEqual(["new"]);
  });

  it("keeps a stored session's startedAt, and gives an older one 0 for GameTable to backfill", () => {
    expect(migrateTableState({ session: { id: "s", goal: "g", startedAt: 42 } }).session?.startedAt).toBe(42);
    expect(migrateTableState({ session: { id: "s", goal: "g" } }).session?.startedAt).toBe(0);
  });
});
