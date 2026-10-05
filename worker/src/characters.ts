// worker/src/characters.ts
//
// The `characters` D1 row shape and its mapping to a `CharacterSheet`. Every
// sheet write goes through `persist.ts`.

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
