-- reviews: two reviewer roles (architecture, errors), different agents. The table was empty. Apply once, then re-apply schema.sql.
PRAGMA foreign_keys = ON;
BEGIN;
DROP TABLE reviews;
COMMIT;
