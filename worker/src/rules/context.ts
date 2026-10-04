// worker/src/rules/context.ts
//
// The facilitator's direct edits to context aspects: add one of either kind,
// reword one, delete one. Using one into the pool and clearing a consumed mark
// stay on `GameTable` until 31.2b and 31.3 rework them.

import type { ContextAspect } from "../types";
import { applied, entry, refuse } from "./result";
import type { CommandOf as Of, Deps, Result, Table } from "./types";

export function addContextAspect(
  table: Table,
  command: Of<"context/add">,
  deps: Deps,
): Result {
  const { kind } = command;
  if (kind === null) return refuse(400, "kind must be Boon or Bane");
  const text = command.text.trim();
  if (!text) return refuse(400, "text is required");

  const aspect: ContextAspect = {
    id: deps.newId(),
    kind,
    text,
    createdByName: command.by.name,
    createdAt: deps.now(),
    consumed: false,
  };
  return applied(
    { ...table, contextAspects: [...table.contextAspects, aspect] },
    [entry(command, deps, { type: "context-aspect-added", kind, text })],
  );
}

/** Reword a context aspect. Silent, like a typo fix. */
export function updateContextAspect(
  table: Table,
  command: Of<"context/update">,
): Result {
  if (!table.contextAspects.some((a) => a.id === command.id)) {
    return refuse(404, "No such context boon");
  }
  const text = command.text.trim();
  if (!text) return refuse(400, "text is required");

  return applied({
    ...table,
    contextAspects: table.contextAspects.map((a) =>
      a.id === command.id ? { ...a, text } : a,
    ),
  });
}

export function deleteContextAspect(
  table: Table,
  command: Of<"context/delete">,
  deps: Deps,
): Result {
  const aspect = table.contextAspects.find((a) => a.id === command.id);
  if (!aspect) return refuse(404, "No such context boon");

  return applied(
    {
      ...table,
      contextAspects: table.contextAspects.filter((a) => a.id !== command.id),
    },
    [
      entry(command, deps, {
        type: "context-aspect-removed",
        kind: aspect.kind,
        text: aspect.text,
      }),
    ],
  );
}
