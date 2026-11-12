-- Existing writing steps keep their executor if it is later changed to candidate.
PRAGMA foreign_keys = ON;
BEGIN;

DROP TRIGGER IF EXISTS steps_writer_eligible_upd;
CREATE TRIGGER steps_writer_eligible_upd
BEFORE UPDATE OF executor, writes, status ON steps
WHEN NEW.writes = 1 AND NOT EXISTS (
  SELECT 1 FROM executors WHERE name = NEW.executor AND status = 'onboarded'
    AND disabled = 0 AND can_write = 1 AND approved_for_project_data = 1
)
BEGIN SELECT RAISE(ABORT, 'executor not eligible for a writing step'); END;

DROP TRIGGER IF EXISTS steps_writer_approval_upd;
CREATE TRIGGER steps_writer_approval_upd
BEFORE UPDATE OF executor, writes, status ON steps
WHEN NEW.writes = 1 AND NEW.status = 'running' AND NOT EXISTS (
  SELECT 1 FROM facts WHERE run_id = NEW.run_id
    AND substr(fact, 1, length('Approved by the user:')) = 'Approved by the user:'
)
BEGIN SELECT RAISE(ABORT, 'writing step needs a recorded user approval'); END;

DROP TRIGGER IF EXISTS steps_writer_reviews_upd;
CREATE TRIGGER steps_writer_reviews_upd
BEFORE UPDATE OF verified ON steps
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

DROP TRIGGER IF EXISTS runs_done_ratings_ins;
CREATE TRIGGER runs_done_ratings_ins
BEFORE INSERT ON runs
WHEN NEW.status = 'done' AND NEW.size IN ('M', 'L') AND EXISTS (
  SELECT 1 FROM steps s WHERE s.run_id = NEW.id AND NOT EXISTS (
    SELECT 1 FROM ratings r WHERE r.step_id = s.id AND r.rater IN ('orchestrator', 'user')
  )
)
BEGIN SELECT RAISE(ABORT, 'finished run needs orchestrator or user ratings for every step'); END;

DROP TRIGGER IF EXISTS runs_done_ratings_upd;
CREATE TRIGGER runs_done_ratings_upd
BEFORE UPDATE OF status ON runs
WHEN NEW.status = 'done' AND NEW.size IN ('M', 'L') AND EXISTS (
  SELECT 1 FROM steps s WHERE s.run_id = NEW.id AND NOT EXISTS (
    SELECT 1 FROM ratings r WHERE r.step_id = s.id AND r.rater IN ('orchestrator', 'user')
  )
)
BEGIN SELECT RAISE(ABORT, 'finished run needs orchestrator or user ratings for every step'); END;

DROP TRIGGER IF EXISTS reviews_verified_frozen_del;
CREATE TRIGGER reviews_verified_frozen_del
BEFORE DELETE ON reviews
WHEN EXISTS (
  SELECT 1 FROM steps s JOIN runs r ON r.id = s.run_id
  WHERE s.id IN (OLD.step_id) AND s.verified = 1 AND r.size IN ('M', 'L')
)
BEGIN SELECT RAISE(ABORT, 'reviews of a verified step are frozen'); END;

DROP TRIGGER IF EXISTS reviews_verified_frozen_upd;
CREATE TRIGGER reviews_verified_frozen_upd
BEFORE UPDATE OF verdict, role, step_id ON reviews
WHEN EXISTS (
  SELECT 1 FROM steps s JOIN runs r ON r.id = s.run_id
  WHERE s.id IN (OLD.step_id, NEW.step_id) AND s.verified = 1 AND r.size IN ('M', 'L')
)
BEGIN SELECT RAISE(ABORT, 'reviews of a verified step are frozen'); END;

COMMIT;
