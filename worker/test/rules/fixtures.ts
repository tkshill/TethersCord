// Builders for the rules-core tests: a table, sheets, actors, and scripted
// dependencies, so a test states only what it is about.

import type { Actor, Command, CommandBody, Deps, Table } from "../../src/rules";
import type { CharacterSheet, ContextAspect, MoveRecord } from "../../src/types";

export const facilitator: Actor = { userId: "gm", name: "Gm", role: "facilitator" };
export const alice: Actor = { userId: "alice", name: "Alice", role: "player" };
export const bob: Actor = { userId: "bob", name: "Bob", role: "player" };

export function sheet(over: Partial<CharacterSheet> = {}): CharacterSheet {
  const slot = over.slot ?? 0;
  return {
    id: `c${slot}`,
    slot,
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

export function table(over: Partial<Table> = {}): Table {
  return {
    sessionId: "t",
    die: 10,
    junction: null,
    contextAspects: [],
    moves: [],
    session: null,
    sessionHistory: [],
    characters: [sheet({ slot: 0 }), sheet({ slot: 1 }), sheet({ slot: 2 })],
    npcs: [],
    locations: [],
    ...over,
  };
}

/** A fixed clock at `now`, ids `<prefix>1`, `<prefix>2`, … (`id-` by
 * default), and rolls taken in order from `faces` (a test that rolls more than
 * it scripted fails loudly). */
export function scripted(
  {
    now = 1000,
    faces = [],
    prefix = "id-",
  }: { now?: number; faces?: number[]; prefix?: string } = {},
): Deps {
  let next = 0;
  const queue = [...faces];
  return {
    roll: () => {
      const face = queue.shift();
      if (face === undefined) throw new Error("unscripted roll");
      return face;
    },
    now: () => now,
    newId: () => `${prefix}${++next}`,
  };
}

export function as(by: Actor, body: CommandBody): Command {
  return { ...body, by } as Command;
}

export function aspect(over: Partial<ContextAspect> = {}): ContextAspect {
  return {
    id: "a",
    kind: "Boon",
    text: "Rope",
    createdByName: "Gm",
    createdAt: 1,
    consumed: false,
    fromAspect: null,
    ...over,
  };
}

/** An open move, for tests about what closes or keeps undo windows. */
export function moveRecord(over: Partial<MoveRecord> = {}): MoveRecord {
  return {
    id: "m",
    kind: "highlight",
    actorId: "alice",
    actorName: "Alice",
    slot: 0,
    aspect: "desire",
    effects: [],
    messageId: "msg",
    ...over,
  };
}
