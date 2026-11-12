-- Apply once. Keep existing rows and avoid rebuilding executors.
PRAGMA foreign_keys = ON;
BEGIN;
ALTER TABLE executors ADD COLUMN probe_score_real REAL CHECK (probe_score_real BETWEEN 1 AND 10);
UPDATE executors SET probe_score_real = probe_score;
ALTER TABLE runs ADD COLUMN size TEXT CHECK (size IN ('S', 'M', 'L'));
ALTER TABLE steps ADD COLUMN writes INTEGER NOT NULL DEFAULT 0 CHECK (writes IN (0, 1));

DROP VIEW executor_stats;
CREATE VIEW executor_stats AS
SELECT s.executor,
       s.model,
       COUNT(DISTINCT s.id) AS steps,
       COUNT(DISTINCT CASE WHEN s.status = 'rejected' THEN s.id END) AS rejected,
       ROUND(AVG(CASE WHEN r.rater = 'orchestrator' THEN r.score END), 2) AS avg_score,
       ROUND(AVG(CASE WHEN r.rater = 'user' THEN r.score END), 2) AS avg_user_score
FROM steps s
LEFT JOIN ratings r ON r.step_id = s.id
GROUP BY s.executor, s.model;

DROP VIEW available_executors;
CREATE VIEW available_executors AS
SELECT id, name, provider, model, kind, run_command, can_write, sends_data_out,
       tier, strengths, limits, status, probe_score_real AS probe_score,
       probe_comment, onboarded_at, created_at, disabled, disabled_reason,
       disabled_at, approved_for_project_data, approved_note, probe_score_real
FROM executors WHERE disabled = 0 AND status <> 'blocked';

CREATE TRIGGER steps_writer_eligible_ins
BEFORE INSERT ON steps
WHEN NEW.writes = 1 AND NOT EXISTS (
  SELECT 1 FROM executors WHERE name = NEW.executor AND status = 'onboarded'
    AND disabled = 0 AND can_write = 1 AND approved_for_project_data = 1
)
BEGIN SELECT RAISE(ABORT, 'executor not eligible for a writing step'); END;

CREATE TRIGGER steps_writer_eligible_upd
BEFORE UPDATE ON steps
WHEN NEW.writes = 1 AND NOT EXISTS (
  SELECT 1 FROM executors WHERE name = NEW.executor AND status = 'onboarded'
    AND disabled = 0 AND can_write = 1 AND approved_for_project_data = 1
)
BEGIN SELECT RAISE(ABORT, 'executor not eligible for a writing step'); END;

CREATE TRIGGER steps_writer_approval_ins
BEFORE INSERT ON steps
WHEN NEW.writes = 1 AND NEW.status = 'running' AND NOT EXISTS (
  SELECT 1 FROM facts WHERE run_id = NEW.run_id
    AND substr(fact, 1, length('Approved by the user:')) = 'Approved by the user:'
)
BEGIN SELECT RAISE(ABORT, 'writing step needs a recorded user approval'); END;

CREATE TRIGGER steps_writer_approval_upd
BEFORE UPDATE ON steps
WHEN NEW.writes = 1 AND NEW.status = 'running' AND NOT EXISTS (
  SELECT 1 FROM facts WHERE run_id = NEW.run_id
    AND substr(fact, 1, length('Approved by the user:')) = 'Approved by the user:'
)
BEGIN SELECT RAISE(ABORT, 'writing step needs a recorded user approval'); END;

CREATE TRIGGER steps_writer_reviews_ins
BEFORE INSERT ON steps
WHEN NEW.writes = 1 AND NEW.verified = 1 AND EXISTS (
  SELECT 1 FROM runs WHERE id = NEW.run_id AND (
    (size = 'M' AND NOT EXISTS (SELECT 1 FROM reviews WHERE step_id = NEW.id))
    OR (size = 'L' AND (
      NOT EXISTS (SELECT 1 FROM reviews WHERE step_id = NEW.id AND role = 'architecture' AND verdict <> 'disputed')
      OR NOT EXISTS (SELECT 1 FROM reviews WHERE step_id = NEW.id AND role = 'errors' AND verdict <> 'disputed')
    ))
  )
)
BEGIN SELECT RAISE(ABORT, 'writing step needs the required reviews'); END;

CREATE TRIGGER steps_writer_reviews_upd
BEFORE UPDATE ON steps
WHEN NEW.writes = 1 AND NEW.verified = 1 AND EXISTS (
  SELECT 1 FROM runs WHERE id = NEW.run_id AND (
    (size = 'M' AND NOT EXISTS (SELECT 1 FROM reviews WHERE step_id = NEW.id))
    OR (size = 'L' AND (
      NOT EXISTS (SELECT 1 FROM reviews WHERE step_id = NEW.id AND role = 'architecture' AND verdict <> 'disputed')
      OR NOT EXISTS (SELECT 1 FROM reviews WHERE step_id = NEW.id AND role = 'errors' AND verdict <> 'disputed')
    ))
  )
)
BEGIN SELECT RAISE(ABORT, 'writing step needs the required reviews'); END;

CREATE TRIGGER runs_done_ratings_ins
BEFORE INSERT ON runs
WHEN NEW.status = 'done' AND NEW.size IN ('M', 'L') AND EXISTS (
  SELECT 1 FROM steps s WHERE s.run_id = NEW.id AND NOT EXISTS (
    SELECT 1 FROM ratings r WHERE r.step_id = s.id AND r.rater = 'orchestrator'
  )
)
BEGIN SELECT RAISE(ABORT, 'finished run needs orchestrator ratings for every step'); END;

CREATE TRIGGER runs_done_ratings_upd
BEFORE UPDATE ON runs
WHEN NEW.status = 'done' AND NEW.size IN ('M', 'L') AND EXISTS (
  SELECT 1 FROM steps s WHERE s.run_id = NEW.id AND NOT EXISTS (
    SELECT 1 FROM ratings r WHERE r.step_id = s.id AND r.rater = 'orchestrator'
  )
)
BEGIN SELECT RAISE(ABORT, 'finished run needs orchestrator ratings for every step'); END;

COMMIT;
