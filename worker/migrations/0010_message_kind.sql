-- Separate chat a player typed from the lines the table writes when something
-- happens (a roll, an accepted proposal, a session starting), so the log can
-- style them apart. Existing rows default to 'chat'; older event lines keep the
-- chat styling until the 30-day prune drops them.
ALTER TABLE messages ADD COLUMN kind TEXT NOT NULL DEFAULT 'chat';
