-- artifacts: any produced link (file path, URL, commit, branch, MR, published page), run is optional, producer recorded.
-- Apply once, then re-apply schema.sql.
PRAGMA foreign_keys = ON;
BEGIN;
CREATE TABLE artifacts_new (
  id          INTEGER PRIMARY KEY,
  run_id      INTEGER REFERENCES runs(id) ON DELETE CASCADE,
  step_id     INTEGER REFERENCES steps(id) ON DELETE SET NULL,
  kind        TEXT NOT NULL DEFAULT 'other' CHECK (kind IN ('file', 'doc', 'brief', 'result', 'report', 'log', 'script', 'migration', 'backup', 'db', 'commit', 'branch', 'merge-request', 'url', 'published-page', 'other')),
  location    TEXT NOT NULL UNIQUE CHECK (length(trim(location)) > 0),
  description TEXT,
  produced_by TEXT,
  created_at  TEXT NOT NULL DEFAULT (datetime('now'))
);
INSERT INTO artifacts_new(id, run_id, step_id, kind, location, description, created_at)
  SELECT id, run_id, step_id, CASE WHEN kind IN ('log') THEN kind ELSE 'other' END, path, description, created_at FROM artifacts;
DROP TABLE artifacts;
ALTER TABLE artifacts_new RENAME TO artifacts;
CREATE INDEX IF NOT EXISTS idx_artifacts_run ON artifacts(run_id);
COMMIT;
