// worker/src/rules/log.ts
//
// What the rules say happened, as data, and the one place that turns it into
// the line stored in `messages`. Tests assert events; only `logText`'s own
// tests match wording.

import type { StoneKind } from "../types";

export type LogEvent =
  | { type: "chat"; content: string }
  | { type: "session-started"; goal: string }
  | { type: "session-ended"; goal: string }
  | { type: "goal-updated"; goal: string }
  | { type: "context-aspect-added"; kind: StoneKind; text: string }
  | { type: "context-aspect-removed"; kind: StoneKind; text: string };

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
  }
}
