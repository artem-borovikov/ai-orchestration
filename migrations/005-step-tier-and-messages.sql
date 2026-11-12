-- steps get a required level; executor conversations are logged in messages. Apply once, then re-apply schema.sql.
ALTER TABLE steps ADD COLUMN tier TEXT CHECK (tier IN ('light', 'mid', 'strong'));
ALTER TABLE steps ADD COLUMN tier_reason TEXT;
