// worker/src/rules/index.ts
//
// The rules core (ADR 0003): every mutation the table supports, as one pure
// function. `transition` reads a table and a command and returns the next
// table and its log lines, or a refusal. It never awaits, writes, or reads the
// clock or randomness except through `deps`; `GameTable` persists the result.
//
// Not yet here (roadmap 31.2b, 31.3): the Junction, the stone pool, using or
// unconsuming a context aspect, and the proposal queue, which still run on
// `GameTable`'s legacy `commit` path.

import {
  addContextAspect,
  deleteContextAspect,
  updateContextAspect,
} from "./context";
import { createEntity, deleteEntity, updateEntity } from "./entities";
import { applied, entry, refuse } from "./result";
import { endSession, startSession, updateGoal } from "./session";
import { adjustBoons, claimSheet, releaseSheet, updateSheet } from "./sheets";
import type { Command, CommandType, Deps, Result, Table } from "./types";

export type {
  Actor,
  Applied,
  Command,
  CommandBody,
  CommandType,
  Deps,
  LogEntry,
  Refusal,
  Result,
  Table,
} from "./types";
export { type LogEvent, logText } from "./log";
export { SESSION_HISTORY_LIMIT } from "./session";

/** The commands only the facilitator may issue. Every other command is open
 * to any authenticated player, subject to its own rule. */
const FACILITATOR_ONLY: ReadonlySet<CommandType> = new Set<CommandType>([
  "log/clear",
  "session/start",
  "session/end",
  "session/goal",
  "sheet/boons",
  "entity/create",
  "entity/update",
  "entity/delete",
  "context/add",
  "context/update",
  "context/delete",
]);

export function transition(table: Table, command: Command, deps: Deps): Result {
  if (FACILITATOR_ONLY.has(command.type) && command.by.role !== "facilitator") {
    return refuse(403, "Facilitator only");
  }

  switch (command.type) {
    case "chat/post": {
      const { content } = command;
      if (!content.trim()) return refuse(400, "Message content is required");
      return applied(table, [entry(command, deps, { type: "chat", content })]);
    }
    case "log/clear":
      return { ...applied(table), clearLog: true };
    case "session/start":
      return startSession(table, command, deps);
    case "session/end":
      return endSession(table, command, deps);
    case "session/goal":
      return updateGoal(table, command, deps);
    case "sheet/update":
      return updateSheet(table, command);
    case "sheet/boons":
      return adjustBoons(table, command);
    case "sheet/claim":
      return claimSheet(table, command);
    case "sheet/release":
      return releaseSheet(table, command);
    case "entity/create":
      return createEntity(table, command, deps);
    case "entity/update":
      return updateEntity(table, command, deps);
    case "entity/delete":
      return deleteEntity(table, command);
    case "context/add":
      return addContextAspect(table, command, deps);
    case "context/update":
      return updateContextAspect(table, command);
    case "context/delete":
      return deleteContextAspect(table, command, deps);
    default:
      return assertNever(command);
  }
}

function assertNever(command: never): never {
  throw new Error(`Unhandled command ${JSON.stringify(command)}`);
}
