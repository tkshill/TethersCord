-- Facilitator-owned reference data for a table: the cast and the map. Scoped by
-- `session_id` (the tableId), the same as `characters`. Broadcast to the whole
-- table, read-only for players. First cut is name + notes only; an NPC
-- `location_id`, a status field, and location nesting can come later.
CREATE TABLE npcs (
  id TEXT PRIMARY KEY,
  session_id TEXT NOT NULL,
  name TEXT NOT NULL DEFAULT '',
  notes TEXT NOT NULL DEFAULT '',
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);

CREATE INDEX idx_npcs_session_created_at
  ON npcs (session_id, created_at);

CREATE TABLE locations (
  id TEXT PRIMARY KEY,
  session_id TEXT NOT NULL,
  name TEXT NOT NULL DEFAULT '',
  notes TEXT NOT NULL DEFAULT '',
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);

CREATE INDEX idx_locations_session_created_at
  ON locations (session_id, created_at);
