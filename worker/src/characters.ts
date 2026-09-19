// worker/src/characters.ts
//
// The raw `characters` D1 access, in one place. Every write goes through a
// named helper here rather than an inline `UPDATE characters SET …` in a
// GameTable handler — in particular the four sites that each spent boons with
// their own copy of `UPDATE characters SET fate = ?` now all call `setFate`.

import type { D1Database } from "@cloudflare/workers-types";
import type { AspectName, CharacterSheet } from "./types";

export type CharacterRow = {
  id: string;
  slot: number;
  name: string;
  notable_features: string;
  archetype: string;
  desire: string;
  quest: string;
  condition: string;
  notes: string;
  fate: number;
  discord_user_id: string | null;
  archetype_banes: number;
  desire_banes: number;
  quest_banes: number;
};

export function rowToCharacterSheet(row: CharacterRow): CharacterSheet {
  return {
    id: row.id,
    slot: row.slot,
    name: row.name,
    notableFeatures: row.notable_features,
    archetype: row.archetype,
    desire: row.desire,
    quest: row.quest,
    condition: row.condition,
    notes: row.notes,
    fate: row.fate,
    aspectBanes: {
      archetype: row.archetype_banes,
      desire: row.desire_banes,
      quest: row.quest_banes,
    },
    ownerId: row.discord_user_id,
  };
}

/** The Bane column for each aspect. Kept private so the aspect name never
 * reaches a SQL string except through `incrementAspectBane`. */
const ASPECT_BANE_COLUMNS: Record<AspectName, string> = {
  archetype: "archetype_banes",
  desire: "desire_banes",
  quest: "quest_banes",
};

/** Set a sheet's boon count outright. `/characters/:slot/fate` and the
 * Complicate / Accept Compel payouts each resolve their new total and call
 * this. */
export async function setFate(
  db: D1Database,
  id: string,
  fate: number,
  now: number,
): Promise<void> {
  await db
    .prepare(`UPDATE characters SET fate = ?, updated_at = ? WHERE id = ?`)
    .bind(fate, now, id)
    .run();
}

/** Bind a sheet to a Discord user, or clear it (`null`). */
export async function setOwner(
  db: D1Database,
  id: string,
  ownerId: string | null,
  now: number,
): Promise<void> {
  await db
    .prepare(
      `UPDATE characters SET discord_user_id = ?, updated_at = ? WHERE id = ?`,
    )
    .bind(ownerId, now, id)
    .run();
}

/** Add one Bane to a sheet's aspect (section 19's mixed overcome result). */
export async function incrementAspectBane(
  db: D1Database,
  id: string,
  aspect: AspectName,
  now: number,
): Promise<void> {
  const column = ASPECT_BANE_COLUMNS[aspect];
  await db
    .prepare(
      `UPDATE characters SET ${column} = ${column} + 1, updated_at = ? WHERE id = ?`,
    )
    .bind(now, id)
    .run();
}

/** Persist the free-text fields of a sheet (the facilitator / owner edit). */
export async function updateFields(
  db: D1Database,
  sheet: CharacterSheet,
  now: number,
): Promise<void> {
  await db
    .prepare(
      `
      UPDATE characters
      SET name = ?, notable_features = ?, archetype = ?, desire = ?, quest = ?, condition = ?, notes = ?, updated_at = ?
      WHERE id = ?
    `,
    )
    .bind(
      sheet.name,
      sheet.notableFeatures,
      sheet.archetype,
      sheet.desire,
      sheet.quest,
      sheet.condition,
      sheet.notes,
      now,
      sheet.id,
    )
    .run();
}
