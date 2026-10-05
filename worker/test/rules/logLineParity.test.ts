import { describe, expect, it } from "vitest";
// The client reads marks, die changes and rolls back out of the stored log
// text (client/src/LogLine.elm, roadmap 32.6), and its LogLineTest pins that
// parser to literal lines. The Elm suite cannot call logText, so this side
// checks that every line logText writes for each event kind is one of those
// literals: rewording a line here fails until LogLine and its test follow.
import logLineTestElm from "../../../client/tests/LogLineTest.elm?raw";
import { type LogEvent, logText } from "../../src/rules/log";

type EventType = Exclude<LogEvent["type"], "chat">;

// One or more events of every kind but chat, matching the cases in
// LogLineTest.elm.
const samples: Record<EventType, LogEvent[]> = {
  "session-started": [{ type: "session-started", goal: "Get the child to the coast" }],
  "session-ended": [{ type: "session-ended", goal: "Get the child to the coast" }],
  "goal-updated": [{ type: "goal-updated", goal: "Get the child to the coast" }],
  "context-aspect-added": [
    { type: "context-aspect-added", kind: "Boon", text: "Oss keeps a ledger" },
    { type: "context-aspect-added", kind: "Bane", text: "Soldiers at the second well" },
  ],
  "context-aspect-removed": [
    { type: "context-aspect-removed", kind: "Bane", text: "Soldiers at the second well" },
  ],
  highlighted: [{ type: "highlighted", label: "Wren", aspect: "desire", from: 10, to: 12 }],
  "context-highlighted": [
    {
      type: "context-highlighted",
      label: "Halvard",
      kind: "Boon",
      text: "Captain Enna owes the ferryman",
      from: 12,
      to: 16,
    },
    {
      type: "context-highlighted",
      label: "Mara",
      kind: "Bane",
      text: "Soldiers at the well",
      from: 10,
      to: 8,
    },
  ],
  complicated: [{ type: "complicated", label: "Wren", aspect: "desire", boons: 2 }],
  created: [{ type: "created", label: "Mara", text: "The tide turns late tonight", cost: 1 }],
  altered: [
    {
      type: "altered",
      label: "Wren",
      cost: 2,
      roll: { die: 12, face: 12, outcome: "critical-flow" },
    },
  ],
  "move-undone": [
    { type: "move-undone", move: "highlight", label: "Wren", die: { from: 12, to: 10 } },
    { type: "move-undone", move: "create", label: "Mara", die: null },
  ],
  "junction-rolled": [
    { type: "junction-rolled", rolledBy: "Halvard", roll: { die: 16, face: 11, outcome: "flow" } },
    {
      type: "junction-rolled",
      rolledBy: "sam",
      roll: { die: 6, face: 1, outcome: "critical-friction" },
    },
  ],
  "junction-rerolled": [
    { type: "junction-rerolled", roll: { die: 12, face: 4, outcome: "friction" } },
  ],
  "junction-accepted": [
    {
      type: "junction-accepted",
      roll: { die: 16, face: 11, outcome: "flow" },
      added: null,
      from: 16,
      to: 10,
    },
    {
      type: "junction-accepted",
      roll: { die: 20, face: 20, outcome: "critical-flow" },
      added: "Boon",
      from: 20,
      to: 10,
    },
    {
      type: "junction-accepted",
      roll: { die: 10, face: 3, outcome: "friction" },
      added: null,
      from: 10,
      to: 10,
    },
  ],
  "junction-rejected": [{ type: "junction-rejected" }],
  "die-stepped": [
    { type: "die-stepped", direction: "up", from: 10, to: 12 },
    { type: "die-stepped", direction: "down", from: 8, to: 6 },
  ],
};

describe("log lines the client parses", () => {
  for (const [type, events] of Object.entries(samples)) {
    for (const event of events) {
      const line = logText(event);
      it(`${type}: ${line}`, () => {
        expect(
          logLineTestElm.includes(`"${line}"`),
          `client/tests/LogLineTest.elm has no case for ${JSON.stringify(line)}`,
        ).toBe(true);
      });
    }
  }
});
