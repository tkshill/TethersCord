import { describe, expect, it } from "vitest";
import { type Applied, type Result, logText, transition } from "../../src/rules";
import type { ContextAspect, Junction, Proposal } from "../../src/types";
import { alice, as, facilitator, scripted, table } from "./fixtures";

function ok(result: Result): Applied {
  if (!result.ok) throw new Error(`refused ${result.status}: ${result.reason}`);
  return result;
}

function refusal(result: Result): { status: number; reason: string } {
  if (result.ok) throw new Error("expected a refusal");
  return { status: result.status, reason: result.reason };
}

function pending(over: Partial<Junction> = {}): Junction {
  return { rolledBy: "Alice", die: 10, face: 7, outcome: "flow", rerolls: 0, alteredSlots: [], ...over };
}

function aspect(over: Partial<ContextAspect> = {}): ContextAspect {
  return { id: "a", kind: "Boon", text: "Rope", createdByName: "Gm", createdAt: 1, consumed: false, ...over };
}

const alterProposal: Proposal = {
  id: "alt",
  kind: "alter",
  proposerId: "alice",
  proposerName: "Alice",
  slot: 0,
  contextAspectId: null,
  targetSlot: null,
  text: null,
  createdAt: 1,
};
const highlightProposal: Proposal = { ...alterProposal, id: "hl", kind: "highlight" };

describe("rolling a Junction", () => {
  it("lets any player roll the current die, leaving the die where it is", () => {
    const r = ok(transition(table({ die: 16 }), as(alice, { type: "junction/roll" }), scripted({ faces: [15] })));
    expect(r.next.junction).toEqual({
      rolledBy: "Alice",
      die: 16,
      face: 15,
      outcome: "critical-flow",
      rerolls: 0,
      alteredSlots: [],
    });
    expect(r.next.die).toBe(16);
    expect(r.log.map((e) => e.event)).toEqual([
      { type: "junction-rolled", rolledBy: "Alice", roll: { die: 16, face: 15, outcome: "critical-flow" } },
    ]);
  });

  it("refuses a second roll while one is pending", () => {
    const t = table({ junction: pending() });
    expect(refusal(transition(t, as(alice, { type: "junction/roll" }), scripted())))
      .toEqual({ status: 409, reason: "A Junction is already pending" });
  });
});

describe("the facilitator's reroll", () => {
  it("rerolls on the Junction's own die, even after the die was stepped, and counts it", () => {
    const t = table({ die: 12, junction: pending({ die: 10, rerolls: 1, alteredSlots: [2] }) });
    const r = ok(transition(t, as(facilitator, { type: "junction/reroll" }), scripted({ faces: [2] })));
    expect(r.next.junction).toEqual(
      pending({ die: 10, face: 2, outcome: "critical-friction", rerolls: 2, alteredSlots: [2] }),
    );
    expect(r.log.map((e) => e.event)).toEqual([
      { type: "junction-rerolled", roll: { die: 10, face: 2, outcome: "critical-friction" } },
    ]);
  });

  it("needs a pending Junction", () => {
    expect(refusal(transition(table(), as(facilitator, { type: "junction/reroll" }), scripted())).status).toBe(409);
  });
});

describe("accepting a Junction", () => {
  it("resets the die to the base and clears the roll", () => {
    const r = ok(transition(table({ die: 16, junction: pending({ die: 16 }) }), as(facilitator, { type: "junction/accept" }), scripted()));
    expect(r.next.die).toBe(10);
    expect(r.next.junction).toBeNull();
    expect(r.next.contextAspects).toEqual([]);
    expect(r.log.map((e) => e.event)).toEqual([
      { type: "junction-accepted", roll: { die: 16, face: 7, outcome: "flow" }, added: null, from: 16, to: 10 },
    ]);
  });

  it("adds a context boon from a Critical Flow and a context bane from a Critical Friction, credited to the roller", () => {
    const flow = ok(transition(
      table({ junction: pending({ face: 10, outcome: "critical-flow" }) }),
      as(facilitator, { type: "junction/accept" }),
      scripted({ now: 5 }),
    ));
    expect(flow.next.contextAspects).toEqual([
      { id: "id-1", kind: "Boon", text: "Critical Flow from Alice's Junction", createdByName: "Alice", createdAt: 5, consumed: false },
    ]);
    const friction = ok(transition(
      table({ junction: pending({ face: 1, outcome: "critical-friction" }) }),
      as(facilitator, { type: "junction/accept" }),
      scripted(),
    ));
    expect(friction.next.contextAspects.map((a) => [a.kind, a.text])).toEqual([
      ["Bane", "Critical Friction from Alice's Junction"],
    ]);
  });

  it("adds nothing for a plain Flow or Friction", () => {
    for (const outcome of ["flow", "friction"] as const) {
      const r = ok(transition(table({ junction: pending({ outcome }) }), as(facilitator, { type: "junction/accept" }), scripted()));
      expect(r.next.contextAspects).toEqual([]);
    }
  });

  it("withdraws a queued Alter, and only that", () => {
    const t = table({ junction: pending(), proposals: [alterProposal, highlightProposal] });
    for (const type of ["junction/accept", "junction/reject"] as const) {
      const r = ok(transition(t, as(facilitator, { type }), scripted()));
      expect(r.next.proposals.map((p) => p.id)).toEqual(["hl"]);
    }
  });

  it("needs a pending Junction", () => {
    expect(refusal(transition(table(), as(facilitator, { type: "junction/accept" }), scripted())).status).toBe(409);
  });
});

describe("rejecting a Junction", () => {
  it("discards the roll and leaves the die, adding nothing", () => {
    const r = ok(transition(
      table({ die: 16, junction: pending({ die: 16, face: 16, outcome: "critical-flow" }) }),
      as(facilitator, { type: "junction/reject" }),
      scripted(),
    ));
    expect(r.next.junction).toBeNull();
    expect(r.next.die).toBe(16);
    expect(r.next.contextAspects).toEqual([]);
    expect(r.log.map((e) => e.event)).toEqual([{ type: "junction-rejected" }]);
  });

  it("needs a pending Junction", () => {
    expect(refusal(transition(table(), as(facilitator, { type: "junction/reject" }), scripted())).status).toBe(409);
  });
});

describe("the facilitator stepping the die", () => {
  it("moves one rung and logs the change", () => {
    const r = ok(transition(table(), as(facilitator, { type: "die/step", direction: "up" }), scripted()));
    expect(r.next.die).toBe(12);
    expect(r.log.map((e) => e.event)).toEqual([{ type: "die-stepped", direction: "up", from: 10, to: 12 }]);
  });

  it("refuses to pass either end of the ladder", () => {
    expect(refusal(transition(table({ die: 20 }), as(facilitator, { type: "die/step", direction: "up" }), scripted())))
      .toEqual({ status: 409, reason: "The die is already at d20" });
    expect(refusal(transition(table({ die: 6 }), as(facilitator, { type: "die/step", direction: "down" }), scripted())))
      .toEqual({ status: 409, reason: "The die is already at d6" });
  });

  it("stays open while a Junction is pending, which keeps its own die", () => {
    const r = ok(transition(table({ junction: pending() }), as(facilitator, { type: "die/step", direction: "down" }), scripted()));
    expect(r.next.die).toBe(8);
    expect(r.next.junction?.die).toBe(10);
  });
});

describe("the facilitator using a context aspect", () => {
  it("steps up for a boon and down for a bane, marking it consumed", () => {
    const boon = ok(transition(table({ contextAspects: [aspect()] }), as(facilitator, { type: "context/use", id: "a" }), scripted()));
    expect(boon.next.die).toBe(12);
    expect(boon.next.contextAspects[0].consumed).toBe(true);
    expect(boon.log.map((e) => e.event)).toEqual([
      { type: "context-aspect-used", kind: "Boon", text: "Rope", from: 10, to: 12 },
    ]);
    const bane = ok(transition(
      table({ contextAspects: [aspect({ kind: "Bane" })] }),
      as(facilitator, { type: "context/use", id: "a" }),
      scripted(),
    ));
    expect(bane.next.die).toBe(8);
  });

  it("refuses a consumed one, one at the end of the ladder (spending nothing), and an unknown one", () => {
    expect(refusal(transition(
      table({ contextAspects: [aspect({ consumed: true })] }),
      as(facilitator, { type: "context/use", id: "a" }),
      scripted(),
    ))).toEqual({ status: 409, reason: "That context boon is already consumed" });
    expect(refusal(transition(
      table({ die: 6, contextAspects: [aspect({ kind: "Bane" })] }),
      as(facilitator, { type: "context/use", id: "a" }),
      scripted(),
    ))).toEqual({ status: 409, reason: "The die is already at d6" });
    expect(refusal(transition(table(), as(facilitator, { type: "context/use", id: "a" }), scripted())).status).toBe(404);
  });

  it("unconsumes one without touching the die, and refuses one not consumed", () => {
    const r = ok(transition(
      table({ die: 12, contextAspects: [aspect({ consumed: true })] }),
      as(facilitator, { type: "context/unconsume", id: "a" }),
      scripted(),
    ));
    expect(r.next.contextAspects[0].consumed).toBe(false);
    expect(r.next.die).toBe(12);
    expect(refusal(transition(table({ contextAspects: [aspect()] }), as(facilitator, { type: "context/unconsume", id: "a" }), scripted())))
      .toEqual({ status: 409, reason: "That context boon is not consumed" });
  });
});

it("keeps every Junction and die command but the roll facilitator-only", () => {
  const t = table({ junction: pending(), contextAspects: [aspect()] });
  for (const body of [
    { type: "junction/reroll" },
    { type: "junction/accept" },
    { type: "junction/reject" },
    { type: "die/step", direction: "up" },
    { type: "context/use", id: "a" },
    { type: "context/unconsume", id: "a" },
  ] as const) {
    expect(refusal(transition(t, as(alice, body), scripted())).status).toBe(403);
  }
});

describe("logText for the Junction and the die", () => {
  const roll = { die: 10, face: 7, outcome: "flow" } as const;
  it("names the outcome, face and die, and every die change as from → to", () => {
    expect(logText({ type: "junction-rolled", rolledBy: "Alice", roll })).toBe("Junction — Alice rolled: Flow — 7 on d10");
    expect(logText({ type: "junction-rerolled", roll: { die: 6, face: 2, outcome: "critical-friction" } }))
      .toBe("Reroll — Critical Friction — 2 on d6");
    expect(logText({ type: "junction-accepted", roll, added: null, from: 10, to: 10 })).toBe("Junction accepted — Flow — 7 on d10");
    expect(logText({ type: "junction-accepted", roll: { die: 16, face: 15, outcome: "critical-flow" }, added: "Boon", from: 16, to: 10 }))
      .toBe("Junction accepted — Critical Flow — 15 on d16 (context boon added) — d16 → d10");
    expect(logText({ type: "junction-rejected" })).toBe("Junction rejected — the roll is discarded");
    expect(logText({ type: "die-stepped", direction: "down", from: 10, to: 8 })).toBe("Die stepped down — d10 → d8");
    expect(logText({ type: "context-aspect-used", kind: "Bane", text: "Smoke", from: 10, to: 8 }))
      .toBe("Context bane used — Smoke — d10 → d8");
    expect(logText({ type: "context-aspect-unconsumed", kind: "Boon", text: "Rope" })).toBe("Context boon unconsumed — Rope");
  });
});
