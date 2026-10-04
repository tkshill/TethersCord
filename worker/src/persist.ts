// worker/src/persist.ts
//
// What a rules-core transition means for D1 (ADR 0003). The rules never say
// what to write: `persistDiff` compares the D1-mirrored parts of the table
// before and after — character sheets, NPCs and locations, the running
// session — and adds a row per new log line. `toStatements` is the one place
// those rows become SQL, flushed by `GameTable` in a single `DB.batch`.
//
// A field D1 mirrors but this diff does not compare is silently lost on the
// next cold start, so every mirrored field is listed here and tested in
// `test/rules/persist.test.ts`.

import type {
  D1Database,
  D1PreparedStatement,
} from "@cloudflare/workers-types";
import type { Table } from "./rules";
import type {
  CharacterSheet,
  EntityKind,
  Message,
  SessionState,
  TableEntity,
} from "./types";

export type RowWrite =
  | { type: "sheet"; sheet: CharacterSheet }
  | { type: "entity-insert"; kind: EntityKind; entity: TableEntity }
  | { type: "entity-update"; kind: EntityKind; entity: TableEntity }
  | { type: "entity-delete"; kind: EntityKind; id: string }
  | { type: "session-insert"; session: SessionState }
  | { type: "session-goal"; id: string; goal: string }
  | { type: "session-end"; id: string; endedAt: number }
  | { type: "messages-clear" }
  | { type: "message-insert"; message: Message };

/** The sheet columns D1 stores and a rule may change. `aspectBanes` is not
 * among them: nothing has written it since 23.1. */
const SHEET_FIELDS = [
  "name",
  "notableFeatures",
  "archetype",
  "desire",
  "quest",
  "condition",
  "notes",
  "fate",
  "ownerId",
] as const satisfies readonly (keyof CharacterSheet)[];

const ENTITY_KINDS: readonly EntityKind[] = ["npcs", "locations"];

export function persistDiff(
  prev: Table,
  next: Table,
  messages: Message[],
  clearLog = false,
): RowWrite[] {
  const writes: RowWrite[] = [];

  for (const sheet of next.characters) {
    const before = prev.characters.find((c) => c.id === sheet.id);
    if (before && SHEET_FIELDS.some((f) => before[f] !== sheet[f])) {
      writes.push({ type: "sheet", sheet });
    }
  }

  for (const kind of ENTITY_KINDS) {
    const before = new Map(prev[kind].map((e) => [e.id, e]));
    const after = new Set(next[kind].map((e) => e.id));
    for (const entity of next[kind]) {
      const old = before.get(entity.id);
      if (!old) {
        writes.push({ type: "entity-insert", kind, entity });
      } else if (
        old.name !== entity.name ||
        old.notes !== entity.notes ||
        old.updatedAt !== entity.updatedAt
      ) {
        writes.push({ type: "entity-update", kind, entity });
      }
    }
    for (const id of before.keys()) {
      if (!after.has(id)) writes.push({ type: "entity-delete", kind, id });
    }
  }

  const was = prev.session;
  const now = next.session;
  if (was && was.id !== now?.id) {
    // Ending a session moves it into the history, which carries its end time.
    const ended = next.sessionHistory.find((s) => s.id === was.id);
    if (ended) {
      writes.push({ type: "session-end", id: was.id, endedAt: ended.endedAt });
    }
  }
  if (now && now.id !== was?.id) {
    writes.push({ type: "session-insert", session: now });
  } else if (now && was && now.goal !== was.goal) {
    writes.push({ type: "session-goal", id: now.id, goal: now.goal });
  }

  if (clearLog) writes.push({ type: "messages-clear" });
  for (const message of messages) {
    writes.push({ type: "message-insert", message });
  }

  return writes;
}

export function toStatements(
  db: D1Database,
  sessionId: string,
  writes: RowWrite[],
  now: number,
): D1PreparedStatement[] {
  return writes.map((write) => {
    switch (write.type) {
      case "sheet": {
        const s = write.sheet;
        return db
          .prepare(
            `UPDATE characters
             SET name = ?, notable_features = ?, archetype = ?, desire = ?, quest = ?,
                 condition = ?, notes = ?, fate = ?, discord_user_id = ?, updated_at = ?
             WHERE id = ?`,
          )
          .bind(
            s.name,
            s.notableFeatures,
            s.archetype,
            s.desire,
            s.quest,
            s.condition,
            s.notes,
            s.fate,
            s.ownerId,
            now,
            s.id,
          );
      }
      case "entity-insert": {
        const e = write.entity;
        return db
          .prepare(
            `INSERT INTO ${entityTable(write.kind)} (id, session_id, name, notes, created_at, updated_at)
             VALUES (?, ?, ?, ?, ?, ?)`,
          )
          .bind(e.id, sessionId, e.name, e.notes, e.createdAt, e.updatedAt);
      }
      case "entity-update": {
        const e = write.entity;
        return db
          .prepare(
            `UPDATE ${entityTable(write.kind)} SET name = ?, notes = ?, updated_at = ? WHERE id = ?`,
          )
          .bind(e.name, e.notes, e.updatedAt, e.id);
      }
      case "entity-delete":
        return db
          .prepare(`DELETE FROM ${entityTable(write.kind)} WHERE id = ?`)
          .bind(write.id);
      case "session-insert":
        return db
          .prepare(
            `INSERT INTO game_sessions (id, session_id, goal, started_at) VALUES (?, ?, ?, ?)`,
          )
          .bind(
            write.session.id,
            sessionId,
            write.session.goal,
            write.session.startedAt,
          );
      case "session-goal":
        return db
          .prepare(`UPDATE game_sessions SET goal = ? WHERE id = ?`)
          .bind(write.goal, write.id);
      case "session-end":
        return db
          .prepare(`UPDATE game_sessions SET ended_at = ? WHERE id = ?`)
          .bind(write.endedAt, write.id);
      case "messages-clear":
        return db
          .prepare(`DELETE FROM messages WHERE session_id = ?`)
          .bind(sessionId);
      case "message-insert": {
        const m = write.message;
        return db
          .prepare(
            `INSERT INTO messages (id, session_id, author_id, author_name, role, kind, content, created_at)
             VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
          )
          .bind(
            m.id,
            m.sessionId,
            m.authorId,
            m.authorName,
            m.role,
            m.kind,
            m.content,
            m.createdAt,
          );
      }
    }
  });
}

/**
 * The D1 table backing an entity kind. An explicit allowlist so the name is
 * never anything but one of these two literals when it reaches a SQL string.
 */
export function entityTable(kind: EntityKind): "npcs" | "locations" {
  return kind === "npcs" ? "npcs" : "locations";
}
