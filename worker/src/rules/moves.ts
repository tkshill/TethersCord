// worker/src/rules/moves.ts
//
// The five moves and undo (RULES.md "Moves", ADR 0002). A move acts at once;
// there is no approval. Each move is a list of effects: applied now, stored on
// a `MoveRecord`, and inverted by undo — so undo reverses that move and
// nothing else, and moves made since survive.
//
// Every move but Alter is made during preparation: once a Junction is rolled
// they are refused, so boons cannot be spent only after seeing the result.
// Rolling closes every undo window; accepting or rejecting closes Alter's.

import { ASPECT_NAMES, characterLabel } from "../gameLogic";
import type {
  AspectName,
  CharacterSheet,
  ContextAspect,
  MoveEffect,
  MoveKind,
  MoveRecord,
} from "../types";
import { type Die, rollDie, step } from "./dice";
import type { LogEvent } from "./log";
import { applied, entry, refuse } from "./result";
import type {
  Actor,
  CommandOf as Of,
  Command,
  Deps,
  Refusal,
  Result,
  Table,
} from "./types";

export const HIGHLIGHT_COST = 1;
export const CREATE_COST = 1;
export const ALTER_COST = 2;
/** Boons a Complicate pays the mover's character. */
export const COMPLICATE_BOONS = 2;

/** The sheet the actor has claimed, if any. */
function sheetOf(table: Table, by: Actor): CharacterSheet | undefined {
  return table.characters.find((c) => c.ownerId === by.userId);
}

const NO_SHEET = refuse(400, "Claim a character sheet first");
const LOCKED = refuse(409, "Moves are locked once the Junction is rolled");

function atEnd(die: Die): Refusal {
  return refuse(409, `The die is already at d${die}`);
}

function aspectOf(
  sheet: CharacterSheet,
  aspect: AspectName | null,
): AspectName | Refusal {
  if (aspect === null || !ASPECT_NAMES.includes(aspect)) {
    return refuse(400, "aspect must be archetype, desire or quest");
  }
  if (!sheet[aspect].trim()) return refuse(400, "That aspect is blank");
  return aspect;
}

function setFate(table: Table, slot: number, delta: number): Table {
  return {
    ...table,
    characters: table.characters.map((c) =>
      c.slot === slot ? { ...c, fate: Math.max(0, c.fate + delta) } : c,
    ),
  };
}

/** Apply one effect. Moves check the ladder before they record a `die`
 * effect, so stepping here never runs off an end. */
export function applyEffect(table: Table, effect: MoveEffect): Table {
  switch (effect.type) {
    case "die":
      return { ...table, die: step(table.die, effect.direction) ?? table.die };
    case "boons":
      return setFate(table, effect.slot, effect.delta);
    case "aspect-added":
      return { ...table, contextAspects: [...table.contextAspects, effect.aspect] };
    case "aspect-consumed":
      return {
        ...table,
        contextAspects: table.contextAspects.map((a) =>
          a.id === effect.id ? { ...a, consumed: true } : a,
        ),
      };
    case "rerolled": {
      const junction = table.junction;
      if (!junction) return table;
      return {
        ...table,
        junction: {
          ...junction,
          ...effect.next,
          rerolls: effect.rerolls,
          alteredSlots: [...junction.alteredSlots, effect.slot],
        },
      };
    }
  }
}

/**
 * Reverse one effect, clamped: a step back past the end of the ladder stops
 * there, boons floor at zero, and an aspect deleted since is left deleted.
 * An Alter's roll is restored only if nothing has replaced it since.
 */
export function invertEffect(table: Table, effect: MoveEffect): Table {
  switch (effect.type) {
    case "die": {
      const back = effect.direction === "up" ? "down" : "up";
      return { ...table, die: step(table.die, back) ?? table.die };
    }
    case "boons":
      return setFate(table, effect.slot, -effect.delta);
    case "aspect-added":
      return {
        ...table,
        contextAspects: table.contextAspects.filter(
          (a) => a.id !== effect.aspect.id,
        ),
      };
    case "aspect-consumed":
      return {
        ...table,
        contextAspects: table.contextAspects.map((a) =>
          a.id === effect.id ? { ...a, consumed: false } : a,
        ),
      };
    case "rerolled": {
      const junction = table.junction;
      if (!junction) return table;
      const current = junction.rerolls === effect.rerolls;
      return {
        ...table,
        junction: {
          ...junction,
          ...(current ? { ...effect.previous, rerolls: effect.rerolls - 1 } : {}),
          alteredSlots: junction.alteredSlots.filter((s) => s !== effect.slot),
        },
      };
    }
  }
}

/** Apply `effects`, record the move for undo, and log it. */
function makeMove(
  table: Table,
  command: Command,
  deps: Deps,
  move: { kind: MoveKind; slot: number | null; aspect: AspectName | null },
  effects: MoveEffect[],
  event: (next: Table) => LogEvent,
): Result {
  const after = effects.reduce(applyEffect, table);
  const line = entry(command, deps, event(after));
  const record: MoveRecord = {
    id: deps.newId(),
    ...move,
    actorId: command.by.userId,
    actorName: command.by.name,
    effects,
    messageId: line.id,
  };
  return applied({ ...after, moves: [...after.moves, record] }, [line]);
}

export function highlight(
  table: Table,
  command: Of<"move/highlight">,
  deps: Deps,
): Result {
  const sheet = sheetOf(table, command.by);
  if (!sheet) return NO_SHEET;
  if (table.junction) return LOCKED;
  const aspect = aspectOf(sheet, command.aspect);
  if (typeof aspect !== "string") return aspect;
  if (sheet.fate < HIGHLIGHT_COST) {
    return refuse(400, "You need a boon to Highlight");
  }
  if (!step(table.die, "up")) return atEnd(table.die);

  return makeMove(
    table,
    command,
    deps,
    { kind: "highlight", slot: sheet.slot, aspect },
    [
      { type: "boons", slot: sheet.slot, delta: -HIGHLIGHT_COST },
      { type: "die", direction: "up" },
    ],
    (next) => ({
      type: "highlighted",
      label: characterLabel(sheet),
      aspect,
      from: table.die,
      to: next.die,
    }),
  );
}

/** Anyone may Highlight Context, with or without a sheet. */
export function highlightContext(
  table: Table,
  command: Of<"move/highlight-context">,
  deps: Deps,
): Result {
  if (table.junction) return LOCKED;
  const target = table.contextAspects.find((a) => a.id === command.id);
  if (!target) return refuse(404, "No such context aspect");
  const name = `context ${target.kind.toLowerCase()}`;
  if (target.consumed) return refuse(409, `That ${name} is already consumed`);
  const direction = target.kind === "Boon" ? "up" : "down";
  if (!step(table.die, direction)) return atEnd(table.die);

  const sheet = sheetOf(table, command.by);
  return makeMove(
    table,
    command,
    deps,
    { kind: "highlight-context", slot: sheet?.slot ?? null, aspect: null },
    [
      { type: "aspect-consumed", id: target.id },
      { type: "die", direction },
    ],
    (next) => ({
      type: "context-highlighted",
      label: sheet ? characterLabel(sheet) : command.by.name,
      kind: target.kind,
      text: target.text,
      from: table.die,
      to: next.die,
    }),
  );
}

/** Free: the character gains boons, and a blank context bane tagged with the
 * aspect waits for the facilitator to word it. */
export function complicate(
  table: Table,
  command: Of<"move/complicate">,
  deps: Deps,
): Result {
  const sheet = sheetOf(table, command.by);
  if (!sheet) return NO_SHEET;
  if (table.junction) return LOCKED;
  const aspect = aspectOf(sheet, command.aspect);
  if (typeof aspect !== "string") return aspect;

  const bane: ContextAspect = {
    id: deps.newId(),
    kind: "Bane",
    text: "",
    createdByName: command.by.name,
    createdAt: deps.now(),
    consumed: false,
    fromAspect: { slot: sheet.slot, aspect },
  };
  return makeMove(
    table,
    command,
    deps,
    { kind: "complicate", slot: sheet.slot, aspect },
    [
      { type: "boons", slot: sheet.slot, delta: COMPLICATE_BOONS },
      { type: "aspect-added", aspect: bane },
    ],
    () => ({
      type: "complicated",
      label: characterLabel(sheet),
      aspect,
      boons: COMPLICATE_BOONS,
    }),
  );
}

/** Pay a boon to establish something true: a context boon in the player's
 * words, or `Detail from <name>` when they leave it blank. */
export function create(
  table: Table,
  command: Of<"move/create">,
  deps: Deps,
): Result {
  const sheet = sheetOf(table, command.by);
  if (!sheet) return NO_SHEET;
  if (table.junction) return LOCKED;
  if (sheet.fate < CREATE_COST) return refuse(400, "You need a boon to Create");

  const text = command.text.trim() || `Detail from ${command.by.name}`;
  const boon: ContextAspect = {
    id: deps.newId(),
    kind: "Boon",
    text,
    createdByName: command.by.name,
    createdAt: deps.now(),
    consumed: false,
    fromAspect: null,
  };
  return makeMove(
    table,
    command,
    deps,
    { kind: "create", slot: sheet.slot, aspect: null },
    [
      { type: "boons", slot: sheet.slot, delta: -CREATE_COST },
      { type: "aspect-added", aspect: boon },
    ],
    () => ({ type: "created", label: characterLabel(sheet), text, cost: CREATE_COST }),
  );
}

/** Pay two boons to reroll the pending Junction on its own die. The only move
 * after the roll, once per character per Junction. */
export function alter(
  table: Table,
  command: Of<"move/alter">,
  deps: Deps,
): Result {
  const sheet = sheetOf(table, command.by);
  if (!sheet) return NO_SHEET;
  const junction = table.junction;
  if (!junction) return refuse(409, "Alter needs a pending Junction");
  if (junction.alteredSlots.includes(sheet.slot)) {
    return refuse(409, "You have already altered this Junction");
  }
  if (sheet.fate < ALTER_COST) return refuse(400, "You need two boons to Alter");

  const { die, face, outcome } = junction;
  const next = rollDie(die, deps.roll);
  return makeMove(
    table,
    command,
    deps,
    { kind: "alter", slot: sheet.slot, aspect: null },
    [
      { type: "boons", slot: sheet.slot, delta: -ALTER_COST },
      {
        type: "rerolled",
        slot: sheet.slot,
        previous: { die, face, outcome },
        next,
        rerolls: junction.rerolls + 1,
      },
    ],
    () => ({ type: "altered", label: characterLabel(sheet), cost: ALTER_COST, roll: next }),
  );
}

/** The facilitator may undo any move still in its window; a player only
 * their own. */
export function undo(
  table: Table,
  command: Of<"move/undo">,
  deps: Deps,
): Result {
  const record = table.moves.find((m) => m.id === command.id);
  if (!record) return refuse(404, "No such move to undo");
  const { by } = command;
  if (by.role !== "facilitator" && by.userId !== record.actorId) {
    return refuse(403, "Not your move");
  }

  const reverted = [...record.effects].reverse().reduce(invertEffect, table);
  const sheet = table.characters.find((c) => c.slot === record.slot);
  return applied(
    { ...reverted, moves: reverted.moves.filter((m) => m.id !== record.id) },
    [
      entry(command, deps, {
        type: "move-undone",
        move: record.kind,
        label: sheet ? characterLabel(sheet) : record.actorName,
        die:
          reverted.die === table.die ? null : { from: table.die, to: reverted.die },
      }),
    ],
  );
}
