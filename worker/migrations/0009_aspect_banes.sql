-- Section 19: an aspect accumulates Banes. A mixed overcome roll marks one of
-- the acting character's three aspects (Archetype / Desire / Quest) with a Bane;
-- Banes carry between sessions until a failed session goal untethers the
-- character, at which point all three counts clear. Aspects only ever gain
-- Banes, never lose them one at a time.
ALTER TABLE characters ADD COLUMN archetype_banes INTEGER NOT NULL DEFAULT 0;
ALTER TABLE characters ADD COLUMN desire_banes INTEGER NOT NULL DEFAULT 0;
ALTER TABLE characters ADD COLUMN quest_banes INTEGER NOT NULL DEFAULT 0;
