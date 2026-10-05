// worker/src/rules/entities.ts
//
// The facilitator's reference rows: NPCs and locations. Silent edits, never
// logged.

import { applied, refuse } from "./result";
import type { CommandOf as Of, Deps, Result, Table } from "./types";

export function createEntity(
  table: Table,
  command: Of<"entity/create">,
  deps: Deps,
): Result {
  const now = deps.now();
  const entity = {
    id: deps.newId(),
    name: command.name,
    notes: command.notes,
    createdAt: now,
    updatedAt: now,
  };
  return applied({
    ...table,
    [command.kind]: [...table[command.kind], entity],
  });
}

export function updateEntity(
  table: Table,
  command: Of<"entity/update">,
  deps: Deps,
): Result {
  if (!command.fields) return refuse(400, "Invalid body");
  const rows = table[command.kind];
  const entity = rows.find((e) => e.id === command.id);
  if (!entity) return refuse(404, "Not found");

  const updated = { ...entity, ...command.fields, updatedAt: deps.now() };
  return applied({
    ...table,
    [command.kind]: rows.map((e) => (e.id === command.id ? updated : e)),
  });
}

export function deleteEntity(
  table: Table,
  command: Of<"entity/delete">,
): Result {
  const rows = table[command.kind];
  if (!rows.some((e) => e.id === command.id)) return refuse(404, "Not found");

  return applied({
    ...table,
    [command.kind]: rows.filter((e) => e.id !== command.id),
  });
}
