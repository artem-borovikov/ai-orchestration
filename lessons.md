# Orchestrator lessons (legacy)

The source of truth is now the `errors` table in `orchestration.db`. This file is kept as a readable copy of the first entries; do not add new ones here.

Mistakes made by the orchestrator or its subagents, and the rule that prevents them.
One entry per lesson. Update an existing entry instead of adding a duplicate.

Format:

## <short title>
- **Mistake:** what went wrong
- **Rule:** what to do instead
- **Applies to:** which step types / models (search, edit, check, brief, verify)

## Verify tool claims by running them
- **Mistake:** a remote model reported "sqlite3 has no `readfile()`" as a high finding. It was false (works in sqlite3 3.54); the same review missed that `readfile()` returns a BLOB, which a subagent found.
- **Rule:** any finding of the form "X is impossible / does not exist" is checked by running the command before it enters a report or a fix list.
- **Applies to:** verify, external agents

## Scratch files go to the scratchpad
- **Mistake:** the orchestrator wrote a probe file to `/tmp` while testing the DB.
- **Rule:** temporary files go to the session scratchpad or the run directory `artifacts/`, never to `/tmp`; delete them after use.
- **Applies to:** orchestrator, all briefs
