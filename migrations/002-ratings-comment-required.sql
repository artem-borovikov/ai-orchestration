-- ratings.comment becomes required and non-blank. Apply once, then re-apply schema.sql.
PRAGMA foreign_keys = ON;
BEGIN;
DROP VIEW IF EXISTS executor_stats;
CREATE TABLE ratings_new (
  id         INTEGER PRIMARY KEY,
  step_id    INTEGER NOT NULL REFERENCES steps(id) ON DELETE CASCADE,
  rater      TEXT NOT NULL CHECK (rater IN ('orchestrator', 'user')),
  score      INTEGER NOT NULL CHECK (score BETWEEN 1 AND 10),
  comment    TEXT NOT NULL CHECK (length(trim(comment)) > 0),
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);
INSERT INTO ratings_new(id, step_id, rater, score, comment, created_at)
  SELECT id, step_id, rater, score, COALESCE(NULLIF(trim(comment), ''), 'no comment (migrated)'), created_at FROM ratings;
DROP TABLE ratings;
ALTER TABLE ratings_new RENAME TO ratings;
CREATE INDEX IF NOT EXISTS idx_ratings_step ON ratings(step_id);
COMMIT;
