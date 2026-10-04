import { describe, expect, it } from "vitest";
import { migrateTableState } from "../src/migrateTableState";

describe("migrateTableState", () => {
  it("returns the base blob when nothing is stored", () => {
    expect(migrateTableState(undefined)).toEqual({
      die: 10,
      junction: null,
      contextAspects: [],
      moves: [],
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

  it("defaults every context aspect field a later feature added", () => {
    const s = migrateTableState({
      // biome-ignore lint: a pre-23.3 aspect has no kind, consumed or fromAspect
      floatingBoons: [{ id: "f", text: "a note", createdByName: "Gm", createdAt: 1 } as never],
    });
    // Every aspect on disk before 23.3 is implicitly a Boon.
    expect(s.contextAspects).toEqual([
      { id: "f", kind: "Boon", text: "a note", createdByName: "Gm", createdAt: 1, consumed: false, fromAspect: null },
    ]);
  });

  it("drops the proposal queue (31.3) and keeps the moves open to undo", () => {
    const move = {
      id: "m",
      kind: "highlight",
      actorId: "u",
      actorName: "U",
      slot: 0,
      aspect: "desire",
      effects: [{ type: "die", direction: "up" }],
      messageId: "x",
    };
    const s = migrateTableState({
      proposals: [{ id: "p", kind: "pledge", proposerId: "u", proposerName: "U", slot: 0, createdAt: 1 }],
      moves: [move as never],
    });
    expect(s).not.toHaveProperty("proposals");
    expect(s.moves).toEqual([move]);
  });

  it("drops state retired by 26.2: once-per-session flags and highlighted boons", () => {
    const s = migrateTableState({
      committedBoons: [{ slot: 0, count: 2 }],
      usedAbilities: [{ slot: 0, kinds: ["add-detail"] }],
    });
    expect(s).not.toHaveProperty("committedBoons");
    expect(s).not.toHaveProperty("usedAbilities");
  });

  it("reads the context aspects section 31.1 renamed under their new name", () => {
    const s = migrateTableState({
      sessionAspects: [{ id: "f", kind: "Boon", text: "n", createdByName: "Gm", createdAt: 1, consumed: true }],
    });
    expect(s.contextAspects).toEqual([
      { id: "f", kind: "Boon", text: "n", createdByName: "Gm", createdAt: 1, consumed: true, fromAspect: null },
    ]);
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
