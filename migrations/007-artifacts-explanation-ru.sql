-- artifacts.explanation_ru: last column, explanation in Russian. Apply once, then re-apply schema.sql.
ALTER TABLE artifacts ADD COLUMN explanation_ru TEXT;
