-- run state moves into the DB: runs.notes (plan notes, next action, pending decisions). Apply once, then re-apply schema.sql.
ALTER TABLE runs ADD COLUMN notes TEXT;
