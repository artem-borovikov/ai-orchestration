-- executors.can_generate_images: allow image-generation tasks only on capable agents.
ALTER TABLE executors ADD COLUMN can_generate_images INTEGER NOT NULL DEFAULT 0 CHECK (can_generate_images IN (0, 1));
UPDATE executors SET can_generate_images = 1 WHERE name = 'codex';
DROP VIEW available_executors;
CREATE VIEW available_executors AS
SELECT id, name, provider, model, kind, run_command, can_write, sends_data_out,
       tier, strengths, limits, status, probe_score_real AS probe_score,
       probe_comment, onboarded_at, created_at, disabled, disabled_reason,
       disabled_at, approved_for_project_data, approved_note, probe_score_real,
       can_generate_images
FROM executors WHERE disabled = 0 AND status <> 'blocked'
/* available_executors(id,name,provider,model,kind,run_command,can_write,sends_data_out,tier,strengths,limits,status,probe_score,probe_comment,onboarded_at,created_at,disabled,disabled_reason,disabled_at,approved_for_project_data,approved_note,probe_score_real,can_generate_images) */;
