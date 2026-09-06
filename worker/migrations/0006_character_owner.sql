-- A character sheet may be claimed by one Discord user; NULL means unclaimed.
ALTER TABLE characters ADD COLUMN discord_user_id TEXT;

-- One claimed sheet per user per table. Partial so multiple NULLs are allowed.
CREATE UNIQUE INDEX idx_characters_session_owner
  ON characters (session_id, discord_user_id)
  WHERE discord_user_id IS NOT NULL;
