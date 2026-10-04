// worker/src/rules/context.ts
//
// The facilitator's direct edits to context aspects: add one of either kind,
// reword one, delete one, use one to step the die, clear a consumed mark.

import type { ContextAspect } from "../types";
import { step } from "./dice";
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

/**
 * The facilitator uses a context aspect directly: a boon steps the die up, a
 * bane steps it down, and the aspect is marked consumed — kept, visibly, so it
 * cannot be used twice. Refused at the end of the ladder, spending nothing.
 */
export function useContextAspect(
  table: Table,
  command: Of<"context/use">,
  deps: Deps,
): Result {
  const aspect = table.contextAspects.find((a) => a.id === command.id);
  if (!aspect) return refuse(404, "No such context aspect");
  const name = `context ${aspect.kind.toLowerCase()}`;
  if (aspect.consumed) return refuse(409, `That ${name} is already consumed`);
  const to = step(table.die, aspect.kind === "Boon" ? "up" : "down");
  if (!to) return refuse(409, `The die is already at d${table.die}`);

  return applied(
    {
      ...table,
      die: to,
      contextAspects: table.contextAspects.map((a) =>
        a.id === aspect.id ? { ...a, consumed: true } : a,
      ),
    },
    [
      entry(command, deps, {
        type: "context-aspect-used",
        kind: aspect.kind,
        text: aspect.text,
        from: table.die,
        to,
      }),
    ],
  );
}

/**
 * Clear a consumed mark: a correction for a table miscommunication, so it does
 * not touch the die. (31.3's undo may make it unnecessary.)
 */
export function unconsumeContextAspect(
  table: Table,
  command: Of<"context/unconsume">,
  deps: Deps,
): Result {
  const aspect = table.contextAspects.find((a) => a.id === command.id);
  if (!aspect) return refuse(404, "No such context aspect");
  const name = `context ${aspect.kind.toLowerCase()}`;
  if (!aspect.consumed) return refuse(409, `That ${name} is not consumed`);

  return applied(
    {
      ...table,
      contextAspects: table.contextAspects.map((a) =>
        a.id === aspect.id ? { ...a, consumed: false } : a,
      ),
    },
    [
      entry(command, deps, {
        type: "context-aspect-unconsumed",
        kind: aspect.kind,
        text: aspect.text,
      }),
    ],
  );
}
