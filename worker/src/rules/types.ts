// worker/src/rules/types.ts
//
// The vocabulary of the rules core (ADR 0003): the table a rule reads, the
// command it is asked to apply, the dependencies it may call, and what it
// returns. Nothing here touches storage, D1 or the socket.

import type {
  CharacterSheetFields,
  EntityKind,
  GameState,
  Role,
  Polarity,
} from "../types";
import type { Direction } from "./dice";
import type { LogEvent } from "./log";

/**
 * The state a rule reads and returns: everything the table holds except the
 * message window, which belongs to `GameTable` (no rule reads it).
 */
export type Table = Omit<GameState, "messages">;

/** Who is issuing a command, as `GameTable` authenticated them. */
export type Actor = {
  userId: string;
  name: string;
  role: Role;
};

/**
 * What the rules may ask of the world. Production uses crypto randomness, the
 * wall clock and random UUIDs; tests script all three.
 */
export type Deps = {
  /** A uniformly random face from 1 to `sides`. */
  roll(sides: number): number;
  now(): number;
  newId(): string;
};

/**
 * One mutation, as parsed from a route. Parsing never refuses: a body field
 * that is missing or of the wrong type arrives as `null` (or is left out of
 * `fields`), so every refusal, and the order refusals are checked in, lives in
 * the rules.
 */
export type CommandBody =
  | { type: "chat/post"; content: string }
  | { type: "log/clear" }
  | { type: "session/start"; goal: string }
  | { type: "session/end" }
  | { type: "session/goal"; goal: string }
  | {
      type: "sheet/update";
      slot: number;
      /** `null` when the body was not a JSON object. */
      fields: Partial<CharacterSheetFields> | null;
    }
  | { type: "sheet/boons"; slot: number; delta: number | null }
  | { type: "sheet/claim"; slot: number }
  | { type: "sheet/release"; slot: number }
  | { type: "entity/create"; kind: EntityKind; name: string; notes: string }
  | {
      type: "entity/update";
      kind: EntityKind;
      id: string;
      fields: { name?: string; notes?: string } | null;
    }
  | { type: "entity/delete"; kind: EntityKind; id: string }
  | { type: "context/add"; kind: Polarity | null; text: string }
  | { type: "context/update"; id: string; text: string }
  | { type: "context/delete"; id: string }
  | { type: "context/use"; id: string }
  | { type: "context/unconsume"; id: string }
  | { type: "junction/roll" }
  | { type: "junction/reroll" }
  | { type: "junction/accept" }
  | { type: "junction/reject" }
  | { type: "die/step"; direction: Direction };

export type Command = CommandBody & { by: Actor };

export type CommandType = CommandBody["type"];

/** The command of one type, narrowed. */
export type CommandOf<T extends CommandType> = Extract<Command, { type: T }>;

/** One line the table writes to the log, before it is stored as a message. */
export type LogEntry = {
  id: string;
  at: number;
  by: Actor;
  event: LogEvent;
};

export type Refusal = {
  ok: false;
  status: 400 | 403 | 404 | 409;
  reason: string;
};

export type Applied = {
  ok: true;
  next: Table;
  log: LogEntry[];
  /** Set by `log/clear`: drop every stored message before writing `log`. */
  clearLog?: true;
};

export type Result = Applied | Refusal;
