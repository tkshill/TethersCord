// worker/src/rules/junction.ts
//
// The Junction (RULES.md "The junction"): anyone rolls the current die, the
// facilitator rerolls for free, then accepts or rejects. Accepting resets the
// die to the base and turns a critical into a context aspect; rejecting
// discards the roll and leaves the die. The facilitator also steps the die
// directly, at any time.

import type { ContextAspect, Polarity } from "../types";
import { BASE_DIE, type Outcome, rollDie, step } from "./dice";
import { outcomeLabel } from "./log";
import { applied, entry, refuse } from "./result";
import type { CommandOf as Of, Deps, Result, Table } from "./types";

/** The context aspect an accepted outcome adds, if any. */
function criticalPolarity(outcome: Outcome): Polarity | null {
  if (outcome === "critical-flow") return "Boon";
  if (outcome === "critical-friction") return "Bane";
  return null;
}

/** A queued Alter only means something during the Junction it was raised for. */
function withoutAlters(table: Table): Table["proposals"] {
  return table.proposals.filter((p) => p.kind !== "alter");
}

export function rollJunction(
  table: Table,
  command: Of<"junction/roll">,
  deps: Deps,
): Result {
  if (table.junction) return refuse(409, "A Junction is already pending");

  const roll = rollDie(table.die, deps.roll);
  const rolledBy = command.by.name;
  return applied(
    { ...table, junction: { rolledBy, ...roll, rerolls: 0, alteredSlots: [] } },
    [entry(command, deps, { type: "junction-rolled", rolledBy, roll })],
  );
}

/** The facilitator's free reroll, on the die the Junction was rolled on. */
export function rerollJunction(
  table: Table,
  command: Of<"junction/reroll">,
  deps: Deps,
): Result {
  const junction = table.junction;
  if (!junction) return refuse(409, "No Junction is pending");

  const roll = rollDie(junction.die, deps.roll);
  return applied(
    {
      ...table,
      junction: { ...junction, ...roll, rerolls: junction.rerolls + 1 },
    },
    [entry(command, deps, { type: "junction-rerolled", roll })],
  );
}

export function acceptJunction(
  table: Table,
  command: Of<"junction/accept">,
  deps: Deps,
): Result {
  const junction = table.junction;
  if (!junction) return refuse(409, "No Junction is pending");

  const added = criticalPolarity(junction.outcome);
  const aspects: ContextAspect[] = added
    ? [
        {
          id: deps.newId(),
          kind: added,
          text: `${outcomeLabel(junction.outcome)} from ${junction.rolledBy}'s Junction`,
          createdByName: junction.rolledBy,
          createdAt: deps.now(),
          consumed: false,
        },
      ]
    : [];
  const { rolledBy: _, rerolls: __, alteredSlots: ___, ...roll } = junction;

  return applied(
    {
      ...table,
      die: BASE_DIE,
      junction: null,
      proposals: withoutAlters(table),
      contextAspects: [...table.contextAspects, ...aspects],
    },
    [
      entry(command, deps, {
        type: "junction-accepted",
        roll,
        added,
        from: table.die,
        to: BASE_DIE,
      }),
    ],
  );
}

export function rejectJunction(
  table: Table,
  command: Of<"junction/reject">,
  deps: Deps,
): Result {
  if (!table.junction) return refuse(409, "No Junction is pending");

  return applied(
    { ...table, junction: null, proposals: withoutAlters(table) },
    [entry(command, deps, { type: "junction-rejected" })],
  );
}

/** The facilitator moves the die one rung. Allowed while a Junction is
 * pending: it is a correction, and the pending roll keeps its own die. */
export function stepDie(
  table: Table,
  command: Of<"die/step">,
  deps: Deps,
): Result {
  const to = step(table.die, command.direction);
  if (!to) return refuse(409, `The die is already at d${table.die}`);

  return applied({ ...table, die: to }, [
    entry(command, deps, {
      type: "die-stepped",
      direction: command.direction,
      from: table.die,
      to,
    }),
  ]);
}
