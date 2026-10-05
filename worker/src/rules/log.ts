// worker/src/rules/log.ts
//
// What the rules say happened, as data, and the one place that turns it into
// the line stored in `messages`. Tests assert events; only `logText`'s own
// tests match wording.

import { moveName } from "../gameLogic";
import type { AspectName, MoveKind, Polarity } from "../types";
import type { Die, Direction, Outcome, Roll } from "./dice";

export type LogEvent =
  | { type: "chat"; content: string }
  | { type: "session-started"; goal: string }
  | { type: "session-ended"; goal: string }
  | { type: "goal-updated"; goal: string }
  | { type: "context-aspect-added"; kind: Polarity; text: string }
  | { type: "context-aspect-removed"; kind: Polarity; text: string }
  | { type: "highlighted"; label: string; aspect: AspectName; from: Die; to: Die }
  | {
      type: "context-highlighted";
      label: string;
      kind: Polarity;
      text: string;
      from: Die;
      to: Die;
    }
  | { type: "complicated"; label: string; aspect: AspectName; boons: number }
  | { type: "created"; label: string; text: string; cost: number }
  | { type: "altered"; label: string; cost: number; roll: Roll }
  | {
      type: "move-undone";
      move: MoveKind;
      label: string;
      /** Set when undoing moved the die. */
      die: { from: Die; to: Die } | null;
    }
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
    case "highlighted":
      return `Highlight — ${event.label}: ${aspectLabel(event.aspect)} — ${dieChange(event.from, event.to)}`;
    case "context-highlighted":
      return `Highlight Context — ${event.label}: ${event.text} (${contextName(event.kind)}) — ${dieChange(event.from, event.to)}`;
    case "complicated":
      return `Complicate — ${event.label}: ${aspectLabel(event.aspect)} — gains ${event.boons} boons, a context bane is added`;
    case "created":
      return `Create — ${event.label} pays ${event.cost} boon: ${event.text}`;
    case "altered":
      return `Alter — ${event.label} pays ${event.cost} boons, rerolled: ${rollText(event.roll)}`;
    case "move-undone": {
      const die = event.die ? ` — ${dieChange(event.die.from, event.die.to)}` : "";
      return `${moveName(event.move)} undone — ${event.label}${die}`;
    }
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

/** `Archetype`, `Desire`, `Quest`. */
function aspectLabel(aspect: AspectName): string {
  return aspect.charAt(0).toUpperCase() + aspect.slice(1);
}
