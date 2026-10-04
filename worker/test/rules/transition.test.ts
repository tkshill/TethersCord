import { describe, expect, it } from "vitest";
import {
  type Applied,
  type Result,
  type Table,
  logText,
  SESSION_HISTORY_LIMIT,
  transition,
} from "../../src/rules";
import type { Proposal } from "../../src/types";
import { alice, as, bob, facilitator, scripted, sheet, table } from "./fixtures";

function ok(result: Result): Applied {
  if (!result.ok) throw new Error(`refused ${result.status}: ${result.reason}`);
  return result;
}

function refusal(result: Result): { status: number; reason: string } {
  if (result.ok) throw new Error("expected a refusal");
  return { status: result.status, reason: result.reason };
}

function proposal(over: Partial<Proposal>): Proposal {
  return {
    id: "p",
    kind: "highlight",
    proposerId: "x",
    proposerName: "X",
    slot: 0,
    contextAspectId: null,
    targetSlot: null,
    text: null,
    createdAt: 1,
    ...over,
  };
}

describe("transition", () => {
  describe("the facilitator gate", () => {
    it("refuses a player every facilitator-only command before any other rule", () => {
      const bodies = [
        { type: "log/clear" },
        { type: "session/start", goal: "" },
        { type: "session/end" },
        { type: "session/goal", goal: "" },
        { type: "sheet/boons", slot: 9, delta: null },
        { type: "entity/create", kind: "npcs", name: "", notes: "" },
        { type: "entity/update", kind: "npcs", id: "x", fields: null },
        { type: "entity/delete", kind: "npcs", id: "x" },
        { type: "context/add", kind: null, text: "" },
        { type: "context/update", id: "x", text: "" },
        { type: "context/delete", id: "x" },
      ] as const;
      for (const body of bodies) {
        expect(refusal(transition(table(), as(alice, body), scripted()))).toEqual({
          status: 403,
          reason: "Facilitator only",
        });
      }
    });
  });

  describe("chat and the log", () => {
    it("logs a chat line without changing the table, and refuses a blank one", () => {
      const t = table();
      const r = ok(transition(t, as(alice, { type: "chat/post", content: "hi" }), scripted()));
      expect(r.next).toBe(t);
      expect(r.log).toEqual([
        { id: "id-1", at: 1000, by: alice, event: { type: "chat", content: "hi" } },
      ]);
      expect(refusal(transition(t, as(alice, { type: "chat/post", content: "  " }), scripted())))
        .toEqual({ status: 400, reason: "Message content is required" });
    });

    it("clears the log as a flag, leaving the table alone", () => {
      const t = table();
      const r = ok(transition(t, as(facilitator, { type: "log/clear" }), scripted()));
      expect(r.clearLog).toBe(true);
      expect(r.next).toBe(t);
    });
  });

  describe("sessions", () => {
    it("starts a session with a trimmed goal, the clock's time and a fresh id", () => {
      const r = ok(
        transition(table(), as(facilitator, { type: "session/start", goal: " Reach it " }), scripted()),
      );
      expect(r.next.session).toEqual({ id: "id-1", goal: "Reach it", startedAt: 1000 });
      expect(r.log.map((e) => e.event)).toEqual([{ type: "session-started", goal: "Reach it" }]);
    });

    it("refuses a second session before checking the goal, and a blank goal", () => {
      const running = table({ session: { id: "s", goal: "g", startedAt: 1 } });
      expect(refusal(transition(running, as(facilitator, { type: "session/start", goal: "" }), scripted())))
        .toEqual({ status: 409, reason: "A session is already running" });
      expect(refusal(transition(table(), as(facilitator, { type: "session/start", goal: " " }), scripted())))
        .toEqual({ status: 400, reason: "A session goal is required" });
    });

    it("ends a session into the front of the history, capped, touching nothing else", () => {
      const history = Array.from({ length: SESSION_HISTORY_LIMIT }, (_, i) => ({
        id: `old-${i}`,
        goal: "",
        startedAt: 0,
        endedAt: 0,
      }));
      const t = table({
        session: { id: "s", goal: "g", startedAt: 5 },
        sessionHistory: history,
        stonePool: ["Boon"],
      });
      const r = ok(transition(t, as(facilitator, { type: "session/end" }), scripted({ now: 9 })));
      expect(r.next.session).toBeNull();
      expect(r.next.sessionHistory).toHaveLength(SESSION_HISTORY_LIMIT);
      expect(r.next.sessionHistory[0]).toEqual({ id: "s", goal: "g", startedAt: 5, endedAt: 9 });
      expect(r.next.stonePool).toEqual(["Boon"]);
      expect(r.log.map((e) => e.event)).toEqual([{ type: "session-ended", goal: "g" }]);
    });

    it("rewrites the goal, ignores an unchanged one, and needs a session", () => {
      const t = table({ session: { id: "s", goal: "g", startedAt: 1 } });
      const r = ok(transition(t, as(facilitator, { type: "session/goal", goal: "h" }), scripted()));
      expect(r.next.session).toEqual({ id: "s", goal: "h", startedAt: 1 });
      const same = ok(transition(t, as(facilitator, { type: "session/goal", goal: "g" }), scripted()));
      expect(same.next).toBe(t);
      expect(same.log).toEqual([]);
      expect(refusal(transition(table(), as(facilitator, { type: "session/goal", goal: "h" }), scripted())).status)
        .toBe(400);
    });
  });

  describe("sheets", () => {
    const owned = (): Table =>
      table({ characters: [sheet({ slot: 0, ownerId: "alice", name: "Ada" }), sheet({ slot: 1 })] });

    it("lets the owner, the facilitator, or anyone on an unclaimed sheet edit it", () => {
      const fields = { name: "Ada Two" };
      expect(ok(transition(owned(), as(alice, { type: "sheet/update", slot: 0, fields }), scripted()))
        .next.characters[0].name).toBe("Ada Two");
      expect(ok(transition(owned(), as(facilitator, { type: "sheet/update", slot: 0, fields }), scripted()))
        .next.characters[0].name).toBe("Ada Two");
      expect(ok(transition(owned(), as(bob, { type: "sheet/update", slot: 1, fields }), scripted()))
        .next.characters[1].name).toBe("Ada Two");
      expect(refusal(transition(owned(), as(bob, { type: "sheet/update", slot: 0, fields }), scripted())))
        .toEqual({ status: 403, reason: "Not your character sheet" });
    });

    it("keeps fields the edit leaves out, and refuses a bad body or slot", () => {
      const r = ok(transition(owned(), as(alice, { type: "sheet/update", slot: 0, fields: { quest: "Q" } }), scripted()));
      expect(r.next.characters[0]).toMatchObject({ name: "Ada", quest: "Q" });
      expect(refusal(transition(owned(), as(alice, { type: "sheet/update", slot: 0, fields: null }), scripted())).status)
        .toBe(400);
      expect(refusal(transition(owned(), as(alice, { type: "sheet/update", slot: 7, fields: {} }), scripted())).status)
        .toBe(404);
    });

    it("adjusts boons directly, flooring at zero", () => {
      const t = table({ characters: [sheet({ slot: 0, fate: 1 })] });
      expect(ok(transition(t, as(facilitator, { type: "sheet/boons", slot: 0, delta: 2 }), scripted()))
        .next.characters[0].fate).toBe(3);
      expect(ok(transition(t, as(facilitator, { type: "sheet/boons", slot: 0, delta: -5 }), scripted()))
        .next.characters[0].fate).toBe(0);
      expect(refusal(transition(t, as(facilitator, { type: "sheet/boons", slot: 0, delta: 1.5 }), scripted())))
        .toEqual({ status: 400, reason: "delta must be an integer" });
      expect(refusal(transition(t, as(facilitator, { type: "sheet/boons", slot: 4, delta: 1 }), scripted())).status)
        .toBe(404);
    });

    it("claims a sheet, releasing the caller's old one and dropping proposals on both", () => {
      const t = table({
        characters: [sheet({ slot: 0, ownerId: "alice" }), sheet({ slot: 1 }), sheet({ slot: 2, ownerId: "bob" })],
        proposals: [proposal({ id: "a", slot: 0 }), proposal({ id: "b", slot: 1 }), proposal({ id: "c", slot: 2 })],
      });
      const r = ok(transition(t, as(alice, { type: "sheet/claim", slot: 1 }), scripted()));
      expect(r.next.characters.map((c) => c.ownerId)).toEqual([null, "alice", "bob"]);
      expect(r.next.proposals.map((p) => p.id)).toEqual(["c"]);
    });

    it("treats re-claiming your own sheet as no change, and refuses someone else's", () => {
      const t = table({ characters: [sheet({ slot: 0, ownerId: "alice" })], proposals: [proposal({})] });
      expect(ok(transition(t, as(alice, { type: "sheet/claim", slot: 0 }), scripted())).next).toBe(t);
      expect(refusal(transition(t, as(bob, { type: "sheet/claim", slot: 0 }), scripted())))
        .toEqual({ status: 409, reason: "Sheet already claimed" });
    });

    it("releases for the owner or the facilitator only", () => {
      const t = table({ characters: [sheet({ slot: 0, ownerId: "alice" })], proposals: [proposal({})] });
      for (const by of [alice, facilitator]) {
        const r = ok(transition(t, as(by, { type: "sheet/release", slot: 0 }), scripted()));
        expect(r.next.characters[0].ownerId).toBeNull();
        expect(r.next.proposals).toEqual([]);
      }
      expect(refusal(transition(t, as(bob, { type: "sheet/release", slot: 0 }), scripted())).status).toBe(403);
      const free = table();
      expect(ok(transition(free, as(bob, { type: "sheet/release", slot: 0 }), scripted())).next).toBe(free);
    });
  });

  describe("NPCs and locations", () => {
    it("creates, updates and deletes a row in the named collection, silently", () => {
      const created = ok(
        transition(table(), as(facilitator, { type: "entity/create", kind: "locations", name: "Mill", notes: "" }), scripted()),
      );
      expect(created.next.locations).toEqual([
        { id: "id-1", name: "Mill", notes: "", createdAt: 1000, updatedAt: 1000 },
      ]);
      expect(created.next.npcs).toEqual([]);
      expect(created.log).toEqual([]);

      const updated = ok(
        transition(
          created.next,
          as(facilitator, { type: "entity/update", kind: "locations", id: "id-1", fields: { notes: "wet" } }),
          scripted({ now: 2000 }),
        ),
      );
      expect(updated.next.locations[0]).toMatchObject({ name: "Mill", notes: "wet", updatedAt: 2000 });

      const deleted = ok(
        transition(updated.next, as(facilitator, { type: "entity/delete", kind: "locations", id: "id-1" }), scripted()),
      );
      expect(deleted.next.locations).toEqual([]);
    });

    it("404s an unknown row, and 400s an update with no body", () => {
      const del = transition(table(), as(facilitator, { type: "entity/delete", kind: "npcs", id: "x" }), scripted());
      expect(refusal(del).status).toBe(404);
      const upd = transition(table(), as(facilitator, { type: "entity/update", kind: "npcs", id: "x", fields: null }), scripted());
      expect(refusal(upd).status).toBe(400);
    });
  });

  describe("context aspects", () => {
    it("adds either kind with trimmed text, logged with its author", () => {
      const r = ok(
        transition(table(), as(facilitator, { type: "context/add", kind: "Bane", text: " Smoke " }), scripted()),
      );
      expect(r.next.contextAspects).toEqual([
        { id: "id-1", kind: "Bane", text: "Smoke", createdByName: "Gm", createdAt: 1000, consumed: false },
      ]);
      expect(r.log.map((e) => e.event)).toEqual([{ type: "context-aspect-added", kind: "Bane", text: "Smoke" }]);
    });

    it("refuses a missing kind before blank text", () => {
      expect(refusal(transition(table(), as(facilitator, { type: "context/add", kind: null, text: "" }), scripted())))
        .toEqual({ status: 400, reason: "kind must be Boon or Bane" });
      expect(refusal(transition(table(), as(facilitator, { type: "context/add", kind: "Boon", text: " " }), scripted())))
        .toEqual({ status: 400, reason: "text is required" });
    });

    it("rewords silently and deletes with a log line; 404s an unknown one", () => {
      const aspect = { id: "a", kind: "Boon" as const, text: "Rope", createdByName: "Gm", createdAt: 1, consumed: true };
      const t = table({ contextAspects: [aspect] });
      const reworded = ok(transition(t, as(facilitator, { type: "context/update", id: "a", text: "Long rope" }), scripted()));
      expect(reworded.next.contextAspects[0]).toEqual({ ...aspect, text: "Long rope" });
      expect(reworded.log).toEqual([]);

      const deleted = ok(transition(t, as(facilitator, { type: "context/delete", id: "a" }), scripted()));
      expect(deleted.next.contextAspects).toEqual([]);
      expect(deleted.log.map((e) => e.event)).toEqual([
        { type: "context-aspect-removed", kind: "Boon", text: "Rope" },
      ]);
      expect(refusal(transition(t, as(facilitator, { type: "context/update", id: "b", text: "x" }), scripted())).status)
        .toBe(404);
    });
  });

  it("never mutates the table it is given", () => {
    const t = table({ session: { id: "s", goal: "g", startedAt: 1 } });
    const before = structuredClone(t);
    transition(t, as(facilitator, { type: "session/end" }), scripted());
    transition(t, as(alice, { type: "sheet/claim", slot: 0 }), scripted());
    transition(t, as(facilitator, { type: "context/add", kind: "Boon", text: "x" }), scripted());
    expect(t).toEqual(before);
  });
});

describe("logText", () => {
  it("writes each event as its stored line", () => {
    expect(logText({ type: "chat", content: "hi" })).toBe("hi");
    expect(logText({ type: "session-started", goal: "g" })).toBe("Session started — g");
    expect(logText({ type: "session-ended", goal: "g" })).toBe("Session ended — g");
    expect(logText({ type: "goal-updated", goal: "g" })).toBe("Goal updated — g");
    expect(logText({ type: "context-aspect-added", kind: "Bane", text: "t" }))
      .toBe("Session note added (Bane) — t");
    expect(logText({ type: "context-aspect-removed", kind: "Boon", text: "t" }))
      .toBe("Session note removed (Boon) — t");
  });
});
