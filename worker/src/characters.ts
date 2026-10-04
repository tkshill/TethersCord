// worker/src/characters.ts
//
// The `characters` D1 row shape and its mapping to a `CharacterSheet`. Rules
// core commands write sheets through `persist.ts`; `setFate` serves only the
// proposal accepts still on `GameTable`'s legacy path, and goes with them in
// 31.3.

import type { D1Database } from "@cloudflare/workers-types";
import type { CharacterSheet } from "./types";

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

/** Set a sheet's boon count outright, for a legacy proposal accept. */
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
