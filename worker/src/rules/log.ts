// worker/src/rules/log.ts
//
// What the rules say happened, as data, and the one place that turns it into
// the line stored in `messages`. Tests assert events; only `logText`'s own
// tests match wording.

import type { Polarity } from "../types";
import type { Die, Direction, Outcome, Roll } from "./dice";

export type LogEvent =
  | { type: "chat"; content: string }
  | { type: "session-started"; goal: string }
  | { type: "session-ended"; goal: string }
  | { type: "goal-updated"; goal: string }
  | { type: "context-aspect-added"; kind: Polarity; text: string }
  | { type: "context-aspect-removed"; kind: Polarity; text: string }
  | {
      type: "context-aspect-used";
      kind: Polarity;
      text: string;
      from: Die;
      to: Die;
    }
  | { type: "context-aspect-unconsumed"; kind: Polarity; text: string }
  | { type: "junction-rolled"; rolledBy: string; roll: Roll }
  | { type: "junction-rerolled"; roll: Roll }
  | {
      type: "junction-accepted";
      roll: Roll;
      /** The context aspect a critical added, if any. */
      added: Polarity | null;
      from: Die;
      to: Die;
    }
  | { type: "junction-rejected" }
  | { type: "die-stepped"; direction: Direction; from: Die; to: Die };

export function outcomeLabel(outcome: Outcome): string {
  switch (outcome) {
    case "critical-friction":
      return "Critical Friction";
    case "friction":
      return "Friction";
    case "flow":
      return "Flow";
    case "critical-flow":
      return "Critical Flow";
  }
}

/** `Flow — 7 on d10`. */
export function rollText(roll: Roll): string {
  return `${outcomeLabel(roll.outcome)} — ${roll.face} on d${roll.die}`;
}

/** `d10 → d12`, the trailer of every line that changes the die. */
export function dieChange(from: Die, to: Die): string {
  return `d${from} → d${to}`;
}

/** `context boon` / `context bane`. */
function contextName(kind: Polarity): string {
  return `context ${kind.toLowerCase()}`;
}

/** The stored text of a log line. */
export function logText(event: LogEvent): string {
  switch (event.type) {
    case "chat":
      return event.content;
    case "session-started":
      return `Session started — ${event.goal}`;
    case "session-ended":
      return `Session ended — ${event.goal}`;
    case "goal-updated":
      return `Goal updated — ${event.goal}`;
    case "context-aspect-added":
      return `Session note added (${event.kind}) — ${event.text}`;
    case "context-aspect-removed":
      return `Session note removed (${event.kind}) — ${event.text}`;
    case "context-aspect-used":
      return `${capitalise(contextName(event.kind))} used — ${event.text} — ${dieChange(event.from, event.to)}`;
    case "context-aspect-unconsumed":
      return `${capitalise(contextName(event.kind))} unconsumed — ${event.text}`;
    case "junction-rolled":
      return `Junction — ${event.rolledBy} rolled: ${rollText(event.roll)}`;
    case "junction-rerolled":
      return `Reroll — ${rollText(event.roll)}`;
    case "junction-accepted": {
      const added = event.added ? ` (${contextName(event.added)} added)` : "";
      const reset =
        event.from === event.to ? "" : ` — ${dieChange(event.from, event.to)}`;
      return `Junction accepted — ${rollText(event.roll)}${added}${reset}`;
    }
    case "junction-rejected":
      return "Junction rejected — the roll is discarded";
    case "die-stepped":
      return `Die stepped ${event.direction} — ${dieChange(event.from, event.to)}`;
  }
}

function capitalise(text: string): string {
  return text.charAt(0).toUpperCase() + text.slice(1);
}
