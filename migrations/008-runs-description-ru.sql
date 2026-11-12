-- runs.description_ru: last column, task description in Russian. Apply once, then re-apply schema.sql.
ALTER TABLE runs ADD COLUMN description_ru TEXT;
