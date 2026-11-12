-- executors.disabled: temporary "do not use" flag with a reason. Apply once, then re-apply schema.sql.
ALTER TABLE executors ADD COLUMN disabled INTEGER NOT NULL DEFAULT 0 CHECK (disabled IN (0, 1));
ALTER TABLE executors ADD COLUMN disabled_reason TEXT;
ALTER TABLE executors ADD COLUMN disabled_at TEXT;
