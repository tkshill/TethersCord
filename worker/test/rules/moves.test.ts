import { describe, expect, it } from "vitest";
import { type Applied, type Result, type Table, logText, transition } from "../../src/rules";
import type { Junction } from "../../src/types";
import { alice, as, aspect, bob, facilitator, scripted, sheet, table } from "./fixtures";

function ok(result: Result): Applied {
  if (!result.ok) throw new Error(`refused ${result.status}: ${result.reason}`);
  return result;
}

function refusal(result: Result): { status: number; reason: string } {
  if (result.ok) throw new Error("expected a refusal");
  return { status: result.status, reason: result.reason };
}

function pending(over: Partial<Junction> = {}): Junction {
  return { rolledBy: "Alice", die: 10, face: 3, outcome: "friction", rerolls: 0, alteredSlots: [], ...over };
}

/** Alice holds slot 0 ("Ada"), Bob slot 1 ("Bo"); each starts with `fate` boons. */
function seated(fate = 3, over: Partial<Table> = {}): Table {
  const aspects = { archetype: "Smuggler", desire: "Freedom", quest: "Find the letter" };
  return table({
    characters: [
      sheet({ slot: 0, name: "Ada", ownerId: "alice", fate, ...aspects }),
      sheet({ slot: 1, name: "Bo", ownerId: "bob", fate, ...aspects }),
      sheet({ slot: 2 }),
    ],
    ...over,
  });
}

const fateOf = (t: Table, slot: number) => t.characters.find((c) => c.slot === slot)?.fate;

describe("Highlight", () => {
  it("pays a boon and steps the die up at once, recording the move against its log line", () => {
    const r = ok(transition(seated(), as(alice, { type: "move/highlight", aspect: "desire" }), scripted()));
    expect(r.next.die).toBe(12);
    expect(fateOf(r.next, 0)).toBe(2);
    expect(r.log.map((e) => e.event)).toEqual([
      { type: "highlighted", label: "Ada", aspect: "desire", from: 10, to: 12 },
    ]);
    expect(r.next.moves).toEqual([
      {
        id: "id-2",
        kind: "highlight",
        actorId: "alice",
        actorName: "Alice",
        slot: 0,
        aspect: "desire",
        effects: [
          { type: "boons", slot: 0, delta: -1 },
          { type: "die", direction: "up" },
        ],
        messageId: r.log[0].id,
      },
    ]);
  });

  it("stacks: three Highlights take a d10 to a d20, and a fourth is refused at the top, spending nothing", () => {
    let t = seated(4);
    for (let i = 0; i < 3; i++) {
      t = ok(transition(t, as(alice, { type: "move/highlight", aspect: "quest" }), scripted())).next;
    }
    expect(t.die).toBe(20);
    expect(refusal(transition(t, as(alice, { type: "move/highlight", aspect: "quest" }), scripted())))
      .toEqual({ status: 409, reason: "The die is already at d20" });
    expect(fateOf(t, 0)).toBe(1);
  });

  it("refuses without a sheet, during a Junction, on a bad or blank aspect, or without a boon", () => {
    const hl = (by = alice, aspectName: "desire" | null = "desire") =>
      as(by, { type: "move/highlight", aspect: aspectName });
    expect(refusal(transition(seated(), hl(facilitator), scripted())))
      .toEqual({ status: 400, reason: "Claim a character sheet first" });
    expect(refusal(transition(seated(3, { junction: pending() }), hl(), scripted())))
      .toEqual({ status: 409, reason: "Moves are locked once the Junction is rolled" });
    expect(refusal(transition(seated(), hl(alice, null), scripted())).status).toBe(400);
    const blank = table({ characters: [sheet({ slot: 0, ownerId: "alice", fate: 1 })] });
    expect(refusal(transition(blank, hl(), scripted()))).toEqual({ status: 400, reason: "That aspect is blank" });
    expect(refusal(transition(seated(0), hl(), scripted())))
      .toEqual({ status: 400, reason: "You need a boon to Highlight" });
  });
});

describe("Highlight Context", () => {
  it("lets anyone, with or without a sheet, use a context boon or bane: the die steps its way and it is consumed", () => {
    const boon = ok(transition(
      seated(0, { contextAspects: [aspect()] }),
      as(facilitator, { type: "move/highlight-context", id: "a" }),
      scripted(),
    ));
    expect(boon.next.die).toBe(12);
    expect(boon.next.contextAspects[0].consumed).toBe(true);
    expect(boon.next.moves[0]).toMatchObject({ kind: "highlight-context", slot: null, actorId: "gm" });
    expect(boon.log.map((e) => e.event)).toEqual([
      { type: "context-highlighted", label: "Gm", kind: "Boon", text: "Rope", from: 10, to: 12 },
    ]);

    const bane = ok(transition(
      seated(0, { contextAspects: [aspect({ kind: "Bane" })] }),
      as(alice, { type: "move/highlight-context", id: "a" }),
      scripted(),
    ));
    expect(bane.next.die).toBe(8);
    expect(bane.next.moves[0]).toMatchObject({ slot: 0 });
    expect(bane.log[0].event).toMatchObject({ label: "Ada" });
  });

  it("refuses during a Junction, for an unknown or consumed aspect, and at the end of the ladder", () => {
    const use = as(alice, { type: "move/highlight-context", id: "a" });
    expect(refusal(transition(seated(0, { junction: pending(), contextAspects: [aspect()] }), use, scripted())).status).toBe(409);
    expect(refusal(transition(seated(), use, scripted()))).toEqual({ status: 404, reason: "No such context aspect" });
    expect(refusal(transition(seated(0, { contextAspects: [aspect({ consumed: true })] }), use, scripted())))
      .toEqual({ status: 409, reason: "That context boon is already consumed" });
    const atBottom = seated(0, { die: 6, contextAspects: [aspect({ kind: "Bane" })] });
    expect(refusal(transition(atBottom, use, scripted()))).toEqual({ status: 409, reason: "The die is already at d6" });
  });
});

describe("Complicate", () => {
  it("is free: the character gains two boons and a blank context bane tagged with the aspect appears", () => {
    const r = ok(transition(seated(0), as(alice, { type: "move/complicate", aspect: "archetype" }), scripted({ now: 7 })));
    expect(fateOf(r.next, 0)).toBe(2);
    expect(r.next.die).toBe(10);
    expect(r.next.contextAspects).toEqual([
      {
        id: "id-1",
        kind: "Bane",
        text: "",
        createdByName: "Alice",
        createdAt: 7,
        consumed: false,
        fromAspect: { slot: 0, aspect: "archetype" },
      },
    ]);
    expect(r.log.map((e) => e.event)).toEqual([
      { type: "complicated", label: "Ada", aspect: "archetype", boons: 2 },
    ]);
  });

  it("refuses without a sheet, during a Junction, or on a blank aspect", () => {
    const c = as(alice, { type: "move/complicate", aspect: "desire" });
    expect(refusal(transition(seated(), as(facilitator, { type: "move/complicate", aspect: "desire" }), scripted())).status).toBe(400);
    expect(refusal(transition(seated(3, { junction: pending() }), c, scripted())).status).toBe(409);
    const blank = table({ characters: [sheet({ slot: 0, ownerId: "alice" })] });
    expect(refusal(transition(blank, c, scripted())).status).toBe(400);
  });
});

describe("Create", () => {
  it("pays a boon for a context boon in the player's words, or a default when left blank", () => {
    const r = ok(transition(seated(1), as(alice, { type: "move/create", text: " The door is unlocked " }), scripted()));
    expect(fateOf(r.next, 0)).toBe(0);
    expect(r.next.contextAspects).toMatchObject([
      { kind: "Boon", text: "The door is unlocked", createdByName: "Alice", fromAspect: null },
    ]);
    expect(r.log[0].event).toEqual({ type: "created", label: "Ada", text: "The door is unlocked", cost: 1 });

    const blank = ok(transition(seated(1), as(alice, { type: "move/create", text: "  " }), scripted()));
    expect(blank.next.contextAspects[0].text).toBe("Detail from Alice");
  });

  it("refuses without a boon, or during a Junction", () => {
    expect(refusal(transition(seated(0), as(alice, { type: "move/create", text: "x" }), scripted())))
      .toEqual({ status: 400, reason: "You need a boon to Create" });
    expect(refusal(transition(seated(1, { junction: pending() }), as(alice, { type: "move/create", text: "x" }), scripted())).status)
      .toBe(409);
  });
});

describe("Alter", () => {
  it("pays two boons to reroll the pending Junction on its own die, once per character", () => {
    const t = seated(3, { die: 16, junction: pending({ die: 10 }) });
    const r = ok(transition(t, as(alice, { type: "move/alter" }), scripted({ faces: [9] })));
    expect(fateOf(r.next, 0)).toBe(1);
    expect(r.next.junction).toEqual(pending({ face: 9, outcome: "critical-flow", rerolls: 1, alteredSlots: [0] }));
    expect(r.log[0].event).toEqual({
      type: "altered",
      label: "Ada",
      cost: 2,
      roll: { die: 10, face: 9, outcome: "critical-flow" },
    });
    expect(refusal(transition(r.next, as(alice, { type: "move/alter" }), scripted())))
      .toEqual({ status: 409, reason: "You have already altered this Junction" });
    expect(ok(transition(r.next, as(bob, { type: "move/alter" }), scripted({ faces: [1] }))).next.junction)
      .toMatchObject({ face: 1, rerolls: 2, alteredSlots: [0, 1] });
  });

  it("needs a pending Junction, a sheet, and two boons", () => {
    expect(refusal(transition(seated(), as(alice, { type: "move/alter" }), scripted())))
      .toEqual({ status: 409, reason: "Alter needs a pending Junction" });
    expect(refusal(transition(seated(3, { junction: pending() }), as(facilitator, { type: "move/alter" }), scripted())).status)
      .toBe(400);
    expect(refusal(transition(seated(1, { junction: pending() }), as(alice, { type: "move/alter" }), scripted())))
      .toEqual({ status: 400, reason: "You need two boons to Alter" });
  });
});

describe("undo", () => {
  /** Make `body` as `by` and return the next table with its new move's id. */
  let made = 0;
  function make(t: Table, by: typeof alice, body: Parameters<typeof as>[1], faces: number[] = []) {
    const r = ok(transition(t, as(by, body), scripted({ faces, prefix: `m${++made}-` })));
    return { next: r.next, id: r.next.moves.at(-1)?.id ?? "" };
  }
  const undo = (t: Table, by: typeof alice, id: string) =>
    transition(t, as(by, { type: "move/undo", id }), scripted());

  it("reverses a Highlight: the die steps down and the boon comes back", () => {
    const { next, id } = make(seated(), alice, { type: "move/highlight", aspect: "desire" });
    const r = ok(undo(next, alice, id));
    expect(r.next.die).toBe(10);
    expect(fateOf(r.next, 0)).toBe(3);
    expect(r.next.moves).toEqual([]);
    expect(r.log.map((e) => e.event)).toEqual([
      { type: "move-undone", move: "highlight", label: "Ada", die: { from: 12, to: 10 } },
    ]);
  });

  it("reverses only that move, so moves made since survive", () => {
    const a = make(seated(), alice, { type: "move/highlight", aspect: "desire" });
    const b = make(a.next, bob, { type: "move/highlight", aspect: "quest" });
    expect(b.next.die).toBe(16);
    const r = ok(undo(b.next, facilitator, a.id));
    expect(r.next.die).toBe(12);
    expect(fateOf(r.next, 0)).toBe(3);
    expect(fateOf(r.next, 1)).toBe(2);
    expect(r.next.moves.map((m) => m.id)).toEqual([b.id]);
  });

  it("stops a reverse step at the end of the ladder", () => {
    const { next, id } = make(seated(), alice, { type: "move/highlight", aspect: "desire" });
    const atBottom = { ...next, die: 6 as const };
    const r = ok(undo(atBottom, alice, id));
    expect(r.next.die).toBe(6);
    expect(fateOf(r.next, 0)).toBe(3);
    expect(r.log[0].event).toMatchObject({ die: null });
  });

  it("reverses a Highlight Context: the aspect is unconsumed and the die steps back", () => {
    const { next, id } = make(seated(0, { contextAspects: [aspect({ kind: "Bane" })] }), bob, {
      type: "move/highlight-context",
      id: "a",
    });
    const r = ok(undo(next, bob, id));
    expect(r.next.die).toBe(10);
    expect(r.next.contextAspects[0].consumed).toBe(false);
  });

  it("reverses a Complicate: the two boons are taken back and its bane deleted", () => {
    const { next, id } = make(seated(1), alice, { type: "move/complicate", aspect: "quest" });
    const r = ok(undo(next, alice, id));
    expect(fateOf(r.next, 0)).toBe(1);
    expect(r.next.contextAspects).toEqual([]);
  });

  it("floors boons at zero when a Complicate's boons were spent before its undo", () => {
    const { next, id } = make(seated(0), alice, { type: "move/complicate", aspect: "quest" });
    const spent = ok(transition(next, as(alice, { type: "move/highlight", aspect: "desire" }), scripted())).next;
    const r = ok(undo(spent, facilitator, id));
    expect(fateOf(r.next, 0)).toBe(0);
  });

  it("reverses a Create: its boon is deleted and the boon refunded", () => {
    const { next, id } = make(seated(1), alice, { type: "move/create", text: "x" });
    const r = ok(undo(next, alice, id));
    expect(fateOf(r.next, 0)).toBe(1);
    expect(r.next.contextAspects).toEqual([]);
  });

  it("reverses an Alter: the previous roll returns, two boons are refunded, and the character may Alter again", () => {
    const { next, id } = make(seated(3, { junction: pending() }), alice, { type: "move/alter" }, [9]);
    const r = ok(undo(next, alice, id));
    expect(r.next.junction).toEqual(pending());
    expect(fateOf(r.next, 0)).toBe(3);
    expect(ok(transition(r.next, as(alice, { type: "move/alter" }), scripted({ faces: [5] }))).next.junction?.face).toBe(5);
  });

  it("keeps a roll that replaced the Alter's since, but still refunds and frees the Alter", () => {
    const altered = make(seated(3, { junction: pending() }), alice, { type: "move/alter" }, [9]);
    const rerolled = ok(transition(altered.next, as(facilitator, { type: "junction/reroll" }), scripted({ faces: [6] }))).next;
    const r = ok(undo(rerolled, alice, altered.id));
    expect(r.next.junction).toMatchObject({ face: 6, rerolls: 2, alteredSlots: [] });
    expect(fateOf(r.next, 0)).toBe(3);
  });

  it("is the facilitator's for any move and a player's for their own", () => {
    const { next, id } = make(seated(), alice, { type: "move/highlight", aspect: "desire" });
    expect(refusal(undo(next, bob, id))).toEqual({ status: 403, reason: "Not your move" });
    expect(ok(undo(next, facilitator, id)).next.moves).toEqual([]);
    expect(refusal(undo(next, alice, "nope"))).toEqual({ status: 404, reason: "No such move to undo" });
  });

  it("closes for preparation moves when the Junction is rolled", () => {
    const { next, id } = make(seated(), alice, { type: "move/highlight", aspect: "desire" });
    const rolled = ok(transition(next, as(alice, { type: "junction/roll" }), scripted({ faces: [4] }))).next;
    expect(refusal(undo(rolled, facilitator, id)).status).toBe(404);
    expect(rolled.die).toBe(12);
  });
});

describe("logText for moves", () => {
  it("names the mover and carries every die change", () => {
    expect(logText({ type: "highlighted", label: "Ada", aspect: "desire", from: 10, to: 12 }))
      .toBe("Highlight — Ada: Desire — d10 → d12");
    expect(logText({ type: "context-highlighted", label: "Gm", kind: "Bane", text: "Smoke", from: 10, to: 8 }))
      .toBe("Highlight Context — Gm: Smoke (context bane) — d10 → d8");
    expect(logText({ type: "complicated", label: "Ada", aspect: "quest", boons: 2 }))
      .toBe("Complicate — Ada: Quest — gains 2 boons, a context bane is added");
    expect(logText({ type: "created", label: "Ada", text: "A ladder", cost: 1 })).toBe("Create — Ada pays 1 boon: A ladder");
    expect(logText({ type: "altered", label: "Ada", cost: 2, roll: { die: 10, face: 7, outcome: "flow" } }))
      .toBe("Alter — Ada pays 2 boons, rerolled: Flow — 7 on d10");
    expect(logText({ type: "move-undone", move: "highlight", label: "Ada", die: { from: 12, to: 10 } }))
      .toBe("Highlight undone — Ada — d12 → d10");
    expect(logText({ type: "move-undone", move: "create", label: "Ada", die: null })).toBe("Create undone — Ada");
  });
});
