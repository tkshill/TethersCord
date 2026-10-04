import { describe, expect, it } from "vitest";
import { persistDiff } from "../../src/persist";
import type { Message } from "../../src/types";
import { sheet, table } from "./fixtures";

const message: Message = {
  id: "m",
  sessionId: "t",
  authorId: "u",
  authorName: "U",
  role: "player",
  kind: "chat",
  content: "hi",
  createdAt: 1,
};

describe("persistDiff", () => {
  it("writes nothing when the D1-mirrored parts are unchanged", () => {
    const t = table();
    expect(persistDiff(t, { ...t, stonePool: ["Boon"], junction: null }, [])).toEqual([]);
  });

  it("writes a sheet whenever any stored field changes", () => {
    const fields = [
      { name: "n" },
      { notableFeatures: "f" },
      { archetype: "a" },
      { desire: "d" },
      { quest: "q" },
      { condition: "c" },
      { notes: "x" },
      { fate: 3 },
      { ownerId: "u" },
    ];
    for (const change of fields) {
      const prev = table({ characters: [sheet({ slot: 0 })] });
      const next = table({ characters: [sheet({ slot: 0, ...change })] });
      expect(persistDiff(prev, next, [])).toEqual([{ type: "sheet", sheet: next.characters[0] }]);
    }
  });

  it("does not write a sheet for an unstored change", () => {
    const prev = table({ characters: [sheet({ slot: 0 })] });
    const next = table({
      characters: [sheet({ slot: 0, aspectBanes: { archetype: 1, desire: 0, quest: 0 } })],
    });
    expect(persistDiff(prev, next, [])).toEqual([]);
  });

  it("inserts, updates and deletes entities by id, per collection", () => {
    const e = (id: string, notes = "") => ({ id, name: "", notes, createdAt: 1, updatedAt: 1 });
    const prev = table({ npcs: [e("kept"), e("edited"), e("gone")], locations: [] });
    const next = table({
      npcs: [e("kept"), { ...e("edited", "new"), updatedAt: 2 }],
      locations: [e("added")],
    });
    expect(persistDiff(prev, next, [])).toEqual([
      { type: "entity-update", kind: "npcs", entity: next.npcs[1] },
      { type: "entity-delete", kind: "npcs", id: "gone" },
      { type: "entity-insert", kind: "locations", entity: next.locations[0] },
    ]);
  });

  it("inserts a started session, updates a rewritten goal, and ends a closed one", () => {
    const running = { id: "s", goal: "g", startedAt: 5 };
    expect(persistDiff(table(), table({ session: running }), [])).toEqual([
      { type: "session-insert", session: running },
    ]);
    expect(
      persistDiff(table({ session: running }), table({ session: { ...running, goal: "h" } }), []),
    ).toEqual([{ type: "session-goal", id: "s", goal: "h" }]);
    expect(
      persistDiff(
        table({ session: running }),
        table({ session: null, sessionHistory: [{ id: "s", goal: "g", startedAt: 5, endedAt: 9 }] }),
        [],
      ),
    ).toEqual([{ type: "session-end", id: "s", endedAt: 9 }]);
  });

  it("clears the log before inserting the new lines", () => {
    expect(persistDiff(table(), table(), [message], true)).toEqual([
      { type: "messages-clear" },
      { type: "message-insert", message },
    ]);
  });
});
