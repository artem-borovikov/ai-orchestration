CREATE TABLE runs (
  id          INTEGER PRIMARY KEY,
  run_id      TEXT NOT NULL UNIQUE,
  repo        TEXT,
  task        TEXT NOT NULL,
  status      TEXT NOT NULL DEFAULT 'running' CHECK (status IN ('running', 'done', 'failed', 'cancelled')),
  report      TEXT,
  created_at  TEXT NOT NULL DEFAULT (datetime('now')),
  finished_at TEXT
, notes TEXT, description_ru TEXT, size TEXT CHECK (size IN ('S', 'M', 'L')));
CREATE TABLE steps (
  id          INTEGER PRIMARY KEY,
  run_id      INTEGER NOT NULL REFERENCES runs(id) ON DELETE CASCADE,
  n           INTEGER NOT NULL,
  title       TEXT NOT NULL,
  executor    TEXT NOT NULL,
  model       TEXT,
  status      TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'running', 'done', 'rejected', 'failed')),
  brief       TEXT,
  result      TEXT,
  verified    INTEGER NOT NULL DEFAULT 0 CHECK (verified IN (0, 1)),
  created_at  TEXT NOT NULL DEFAULT (datetime('now')),
  finished_at TEXT, tier TEXT CHECK (tier IN ('light', 'mid', 'strong')), tier_reason TEXT, writes INTEGER NOT NULL DEFAULT 0 CHECK (writes IN (0, 1)),
  UNIQUE (run_id, n)
);
CREATE INDEX idx_steps_run ON steps(run_id);
CREATE TABLE errors (
  id          INTEGER PRIMARY KEY,
  title       TEXT NOT NULL UNIQUE,
  mistake     TEXT NOT NULL,
  cause       TEXT,
  solution    TEXT,
  rule        TEXT NOT NULL,
  applies_to  TEXT,
  status      TEXT NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'resolved')),
  run_id      INTEGER REFERENCES runs(id) ON DELETE SET NULL,
  step_id     INTEGER REFERENCES steps(id) ON DELETE SET NULL,
  created_at  TEXT NOT NULL DEFAULT (datetime('now')),
  resolved_at TEXT
);
CREATE TABLE "ratings" (
  id         INTEGER PRIMARY KEY,
  step_id    INTEGER NOT NULL REFERENCES steps(id) ON DELETE CASCADE,
  rater      TEXT NOT NULL CHECK (rater IN ('orchestrator', 'user')),
  score      INTEGER NOT NULL CHECK (score BETWEEN 1 AND 10),
  comment    TEXT NOT NULL CHECK (length(trim(comment)) > 0),
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX idx_ratings_step ON ratings(step_id);
CREATE TABLE facts (
  id         INTEGER PRIMARY KEY,
  run_id     INTEGER NOT NULL REFERENCES runs(id) ON DELETE CASCADE,
  step_id    INTEGER REFERENCES steps(id) ON DELETE SET NULL,
  fact       TEXT NOT NULL CHECK (length(trim(fact)) > 0),
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX idx_facts_run ON facts(run_id);
CREATE TABLE executors (
  id            INTEGER PRIMARY KEY,
  name          TEXT NOT NULL UNIQUE,
  provider      TEXT NOT NULL,
  model         TEXT,
  kind          TEXT NOT NULL CHECK (kind IN ('claude-subagent', 'cli', 'local')),
  run_command   TEXT,
  can_write     INTEGER NOT NULL DEFAULT 0 CHECK (can_write IN (0, 1)),
  sends_data_out INTEGER NOT NULL DEFAULT 1 CHECK (sends_data_out IN (0, 1)),
  tier          TEXT CHECK (tier IN ('light', 'mid', 'strong')),
  strengths     TEXT,
  limits        TEXT,
  status        TEXT NOT NULL DEFAULT 'candidate' CHECK (status IN ('candidate', 'onboarded', 'blocked')),
  probe_score   INTEGER CHECK (probe_score BETWEEN 1 AND 10),
  probe_comment TEXT,
  onboarded_at  TEXT,
  created_at    TEXT NOT NULL DEFAULT (datetime('now'))
, disabled INTEGER NOT NULL DEFAULT 0 CHECK (disabled IN (0, 1)), disabled_reason TEXT, disabled_at TEXT, approved_for_project_data INTEGER NOT NULL DEFAULT 0 CHECK (approved_for_project_data IN (0, 1)), approved_note TEXT, probe_score_real REAL CHECK (probe_score_real BETWEEN 1 AND 10), can_generate_images INTEGER NOT NULL DEFAULT 0 CHECK (can_generate_images IN (0, 1)));
CREATE TABLE messages (
  id         INTEGER PRIMARY KEY,
  step_id    INTEGER NOT NULL REFERENCES steps(id) ON DELETE CASCADE,
  direction  TEXT NOT NULL CHECK (direction IN ('to_executor', 'from_executor')),
  kind       TEXT NOT NULL CHECK (kind IN ('briefing', 'restatement', 'clarification', 'instruction', 'question', 'answer', 'report', 'feedback')),
  content    TEXT NOT NULL CHECK (length(trim(content)) > 0),
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX idx_messages_step ON messages(step_id);
CREATE TABLE "artifacts" (
  id          INTEGER PRIMARY KEY,
  run_id      INTEGER REFERENCES runs(id) ON DELETE CASCADE,
  step_id     INTEGER REFERENCES steps(id) ON DELETE SET NULL,
  kind        TEXT NOT NULL DEFAULT 'other' CHECK (kind IN ('file', 'doc', 'brief', 'result', 'report', 'log', 'script', 'migration', 'backup', 'db', 'commit', 'branch', 'merge-request', 'url', 'published-page', 'other')),
  location    TEXT NOT NULL UNIQUE CHECK (length(trim(location)) > 0),
  description TEXT,
  produced_by TEXT,
  created_at  TEXT NOT NULL DEFAULT (datetime('now'))
, explanation_ru TEXT);
CREATE INDEX idx_artifacts_run ON artifacts(run_id);
CREATE TRIGGER artifacts_explanation_required_ins
BEFORE INSERT ON artifacts
WHEN NEW.explanation_ru IS NULL OR length(trim(NEW.explanation_ru)) = 0
BEGIN SELECT RAISE(ABORT, 'artifacts.explanation_ru (Russian explanation) is required'); END;
CREATE TRIGGER artifacts_explanation_required_upd
BEFORE UPDATE OF explanation_ru ON artifacts
WHEN NEW.explanation_ru IS NULL OR length(trim(NEW.explanation_ru)) = 0
BEGIN SELECT RAISE(ABORT, 'artifacts.explanation_ru (Russian explanation) is required'); END;
CREATE TRIGGER runs_description_required_ins
BEFORE INSERT ON runs
WHEN NEW.description_ru IS NULL OR length(trim(NEW.description_ru)) = 0
BEGIN SELECT RAISE(ABORT, 'runs.description_ru (task description in Russian) is required'); END;
CREATE TRIGGER runs_description_required_upd
BEFORE UPDATE OF description_ru ON runs
WHEN NEW.description_ru IS NULL OR length(trim(NEW.description_ru)) = 0
BEGIN SELECT RAISE(ABORT, 'runs.description_ru (task description in Russian) is required'); END;
CREATE TABLE reviews (
  id         INTEGER PRIMARY KEY,
  step_id    INTEGER NOT NULL REFERENCES steps(id) ON DELETE CASCADE,
  role       TEXT NOT NULL CHECK (role IN ('architecture', 'errors')),
  reviewer   TEXT NOT NULL,
  verdict    TEXT NOT NULL CHECK (verdict IN ('confirmed', 'partly', 'disputed')),
  findings   TEXT NOT NULL CHECK (length(trim(findings)) > 0),
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  UNIQUE (step_id, role),
  UNIQUE (step_id, reviewer)
);
CREATE TRIGGER reviews_not_the_executor
BEFORE INSERT ON reviews
WHEN NEW.reviewer = (SELECT executor FROM steps WHERE id = NEW.step_id)
BEGIN SELECT RAISE(ABORT, 'reviewer must be a different agent than the executor of the step'); END;
CREATE INDEX idx_reviews_step ON reviews(step_id);
CREATE TRIGGER executors_disable_needs_reason
BEFORE UPDATE OF disabled ON executors
WHEN NEW.disabled = 1 AND (NEW.disabled_reason IS NULL OR length(trim(NEW.disabled_reason)) = 0)
BEGIN SELECT RAISE(ABORT, 'executors.disabled_reason is required when disabling an executor'); END;
CREATE TRIGGER steps_skip_disabled_executor_ins
BEFORE INSERT ON steps
WHEN EXISTS (SELECT 1 FROM executors WHERE name = NEW.executor AND disabled = 1)
BEGIN SELECT RAISE(ABORT, 'executor is disabled (executors.disabled = 1)'); END;
CREATE TRIGGER steps_skip_disabled_executor_upd
BEFORE UPDATE OF executor ON steps
WHEN EXISTS (SELECT 1 FROM executors WHERE name = NEW.executor AND disabled = 1)
BEGIN SELECT RAISE(ABORT, 'executor is disabled (executors.disabled = 1)'); END;
CREATE TRIGGER reviews_skip_disabled_reviewer
BEFORE INSERT ON reviews
WHEN EXISTS (SELECT 1 FROM executors WHERE name = NEW.reviewer AND disabled = 1)
BEGIN SELECT RAISE(ABORT, 'reviewer is disabled (executors.disabled = 1)'); END;
CREATE VIEW executor_stats AS
SELECT s.executor,
       s.model,
       COUNT(DISTINCT s.id) AS steps,
       COUNT(DISTINCT CASE WHEN s.status = 'rejected' THEN s.id END) AS rejected,
       ROUND(AVG(CASE WHEN r.rater = 'orchestrator' THEN r.score END), 2) AS avg_score,
       ROUND(AVG(CASE WHEN r.rater = 'user' THEN r.score END), 2) AS avg_user_score
FROM steps s
LEFT JOIN ratings r ON r.step_id = s.id
GROUP BY s.executor, s.model
/* executor_stats(executor,model,steps,rejected,avg_score,avg_user_score) */;
CREATE VIEW available_executors AS
SELECT id, name, provider, model, kind, run_command, can_write, sends_data_out,
       tier, strengths, limits, status, probe_score_real AS probe_score,
       probe_comment, onboarded_at, created_at, disabled, disabled_reason,
       disabled_at, approved_for_project_data, approved_note, probe_score_real,
       can_generate_images
FROM executors WHERE disabled = 0 AND status <> 'blocked'
/* available_executors(id,name,provider,model,kind,run_command,can_write,sends_data_out,tier,strengths,limits,status,probe_score,probe_comment,onboarded_at,created_at,disabled,disabled_reason,disabled_at,approved_for_project_data,approved_note,probe_score_real,can_generate_images) */;
CREATE TRIGGER steps_writer_eligible_ins
BEFORE INSERT ON steps
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
CREATE TRIGGER steps_writer_eligible_upd
BEFORE UPDATE OF executor, writes, status ON steps
WHEN NEW.writes = 1 AND NOT EXISTS (
  SELECT 1 FROM executors WHERE name = NEW.executor AND status = 'onboarded'
    AND disabled = 0 AND can_write = 1 AND approved_for_project_data = 1
)
BEGIN SELECT RAISE(ABORT, 'executor not eligible for a writing step'); END;
CREATE TRIGGER steps_writer_approval_upd
BEFORE UPDATE OF executor, writes, status ON steps
WHEN NEW.writes = 1 AND NEW.status = 'running' AND NOT EXISTS (
  SELECT 1 FROM facts WHERE run_id = NEW.run_id
    AND substr(fact, 1, length('Approved by the user:')) = 'Approved by the user:'
)
BEGIN SELECT RAISE(ABORT, 'writing step needs a recorded user approval'); END;
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
CREATE TRIGGER runs_done_ratings_ins
BEFORE INSERT ON runs
WHEN NEW.status = 'done' AND NEW.size IN ('M', 'L') AND EXISTS (
  SELECT 1 FROM steps s WHERE s.run_id = NEW.id AND NOT EXISTS (
    SELECT 1 FROM ratings r WHERE r.step_id = s.id AND r.rater IN ('orchestrator', 'user')
  )
)
BEGIN SELECT RAISE(ABORT, 'finished run needs orchestrator or user ratings for every step'); END;
CREATE TRIGGER runs_done_ratings_upd
BEFORE UPDATE OF status ON runs
WHEN NEW.status = 'done' AND NEW.size IN ('M', 'L') AND EXISTS (
  SELECT 1 FROM steps s WHERE s.run_id = NEW.id AND NOT EXISTS (
    SELECT 1 FROM ratings r WHERE r.step_id = s.id AND r.rater IN ('orchestrator', 'user')
  )
)
BEGIN SELECT RAISE(ABORT, 'finished run needs orchestrator or user ratings for every step'); END;
CREATE TRIGGER reviews_verified_frozen_del
BEFORE DELETE ON reviews
WHEN EXISTS (
  SELECT 1 FROM steps s JOIN runs r ON r.id = s.run_id
  WHERE s.id IN (OLD.step_id) AND s.verified = 1 AND r.size IN ('M', 'L')
)
BEGIN SELECT RAISE(ABORT, 'reviews of a verified step are frozen'); END;
CREATE TRIGGER reviews_verified_frozen_upd
BEFORE UPDATE OF verdict, role, step_id ON reviews
WHEN EXISTS (
  SELECT 1 FROM steps s JOIN runs r ON r.id = s.run_id
  WHERE s.id IN (OLD.step_id, NEW.step_id) AND s.verified = 1 AND r.size IN ('M', 'L')
)
BEGIN SELECT RAISE(ABORT, 'reviews of a verified step are frozen'); END;
