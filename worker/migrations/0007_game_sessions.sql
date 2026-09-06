-- One row per game session (a session = one game day with a goal). `session_id`
-- is the tableId, matching the column's meaning elsewhere. The live session
-- stone pool lives in Durable Object storage, not here.
CREATE TABLE game_sessions (
  id TEXT PRIMARY KEY,
  session_id TEXT NOT NULL,
  goal TEXT NOT NULL,
  started_at INTEGER NOT NULL,
  ended_at INTEGER,
  outcome TEXT
);

CREATE INDEX idx_game_sessions_session_started_at
  ON game_sessions (session_id, started_at);
