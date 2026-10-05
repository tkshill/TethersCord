// worker/src/rules/sheets.ts
//
// Character sheets: text edits, the facilitator's direct boon edits, and who
// holds which sheet.

import { clearSlotPendingState } from "../gameLogic";
import type { CharacterSheet } from "../types";
import { applied, refuse, unchanged } from "./result";
import type { CommandOf as Of, Result, Table } from "./types";

function replaceSheet(table: Table, sheet: CharacterSheet): Table {
  return {
    ...table,
    characters: table.characters.map((c) => (c.slot === sheet.slot ? sheet : c)),
  };
}

export function updateSheet(table: Table, command: Of<"sheet/update">): Result {
  if (!command.fields) return refuse(400, "Invalid body");
  const sheet = table.characters.find((c) => c.slot === command.slot);
  if (!sheet) return refuse(404, "Not found");

  // The facilitator may edit any sheet; a player only their own, or one that
  // no one has claimed yet (setup before claiming).
  const { by } = command;
  const mayEdit =
    by.role === "facilitator" ||
    sheet.ownerId === null ||
    sheet.ownerId === by.userId;
  if (!mayEdit) return refuse(403, "Not your character sheet");

  return applied(replaceSheet(table, { ...sheet, ...command.fields }));
}

/** The facilitator adds or takes boons directly; boons floor at zero. */
export function adjustBoons(table: Table, command: Of<"sheet/boons">): Result {
  const { delta } = command;
  if (delta === null || !Number.isInteger(delta)) {
    return refuse(400, "delta must be an integer");
  }
  const sheet = table.characters.find((c) => c.slot === command.slot);
  if (!sheet) return refuse(404, "Not found");

  return applied(
    replaceSheet(table, { ...sheet, fate: Math.max(0, sheet.fate + delta) }),
  );
}

/**
 * Bind the caller to a sheet. Refused if someone else holds it; releases any
 * other sheet the caller already holds, so a player owns at most one.
 */
export function claimSheet(table: Table, command: Of<"sheet/claim">): Result {
  const target = table.characters.find((c) => c.slot === command.slot);
  if (!target) return refuse(404, "Not found");
  const userId = command.by.userId;
  if (target.ownerId && target.ownerId !== userId) {
    return refuse(409, "Sheet already claimed");
  }
  // Re-claiming a sheet the caller already holds is a no-op — don't close
  // that slot's own undo windows.
  if (target.ownerId === userId) return unchanged(table);

  const priorSlots = table.characters
    .filter((c) => c.ownerId === userId && c.slot !== target.slot)
    .map((c) => c.slot);

  let next: Table = {
    ...table,
    characters: table.characters.map((c) => {
      if (c.slot === target.slot) return { ...c, ownerId: userId };
      if (priorSlots.includes(c.slot)) return { ...c, ownerId: null };
      return c;
    }),
  };
  // Any sheet whose owner just changed must not keep moves its previous
  // holder could undo.
  for (const changed of [target.slot, ...priorSlots]) {
    next = clearSlotPendingState(next, changed);
  }
  return applied(next);
}

/** Release a sheet: its owner or the facilitator may. */
export function releaseSheet(
  table: Table,
  command: Of<"sheet/release">,
): Result {
  const target = table.characters.find((c) => c.slot === command.slot);
  if (!target) return refuse(404, "Not found");
  if (!target.ownerId) return unchanged(table);
  const { by } = command;
  if (target.ownerId !== by.userId && by.role !== "facilitator") {
    return refuse(403, "Not your character sheet");
  }

  return applied(
    clearSlotPendingState(
      replaceSheet(table, { ...target, ownerId: null }),
      target.slot,
    ),
  );
}
