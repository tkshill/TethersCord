// worker/src/rules/result.ts
//
// Small constructors shared by the rule modules, so each arm reads as the rule
// it states rather than as object literals.

import type { LogEvent } from "./log";
import type { Applied, Command, Deps, LogEntry, Refusal, Table } from "./types";

export function refuse(status: Refusal["status"], reason: string): Refusal {
  return { ok: false, status, reason };
}

export function applied(next: Table, log: LogEntry[] = []): Applied {
  return { ok: true, next, log };
}

/** The command changes nothing: no write, no log line, no broadcast. */
export function unchanged(table: Table): Applied {
  return applied(table);
}

/** A log line written by the command's actor. */
export function entry(command: Command, deps: Deps, event: LogEvent): LogEntry {
  return { id: deps.newId(), at: deps.now(), by: command.by, event };
}
