// worker/src/rules/session.ts
//
// Sessions do nothing special (RULES.md, "Sessions and the goal"): starting one
// records the goal, ending one moves it into the history. Neither touches the
// die, context aspects, open moves or a pending Junction.

import { applied, entry, refuse, unchanged } from "./result";
import type { CommandOf as Of, Deps, Result, Table } from "./types";

/** How many completed sessions the table keeps in `sessionHistory`. */
export const SESSION_HISTORY_LIMIT = 20;

export function startSession(
  table: Table,
  command: Of<"session/start">,
  deps: Deps,
): Result {
  if (table.session) return refuse(409, "A session is already running");
  const goal = command.goal.trim();
  if (!goal) return refuse(400, "A session goal is required");

  return applied(
    { ...table, session: { id: deps.newId(), goal, startedAt: deps.now() } },
    [entry(command, deps, { type: "session-started", goal })],
  );
}

export function endSession(
  table: Table,
  command: Of<"session/end">,
  deps: Deps,
): Result {
  const session = table.session;
  if (!session) return refuse(400, "No session is running");

  const summary = {
    id: session.id,
    goal: session.goal,
    startedAt: session.startedAt,
    endedAt: deps.now(),
  };
  return applied(
    {
      ...table,
      session: null,
      sessionHistory: [summary, ...table.sessionHistory].slice(
        0,
        SESSION_HISTORY_LIMIT,
      ),
    },
    [entry(command, deps, { type: "session-ended", goal: session.goal })],
  );
}

export function updateGoal(
  table: Table,
  command: Of<"session/goal">,
  deps: Deps,
): Result {
  const session = table.session;
  if (!session) return refuse(400, "No session is running");
  const goal = command.goal.trim();
  if (!goal) return refuse(400, "A session goal is required");
  if (goal === session.goal) return unchanged(table);

  return applied({ ...table, session: { ...session, goal } }, [
    entry(command, deps, { type: "goal-updated", goal }),
  ]);
}
