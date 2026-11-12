-- executors.approved_for_project_data: the user's permission for an agent to receive project code (0 = no, 1 = yes), applies to every agent the same way. Apply once, then re-apply schema.sql.
ALTER TABLE executors ADD COLUMN approved_for_project_data INTEGER NOT NULL DEFAULT 0 CHECK (approved_for_project_data IN (0, 1));
ALTER TABLE executors ADD COLUMN approved_note TEXT;
