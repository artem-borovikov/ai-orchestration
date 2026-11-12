# Roles of subordinate agents

The orchestrator names a role in every brief.

Briefs carry an inline role card.

| Role | File | DB role in `reviews` | What it does |
|---|---|---|---|
| Executor | `executor.md` | n/a (the step's `executor`) | does the step exactly as briefed |
| Architect | `architect.md` | `architecture` | accepts the result: is it built the right way |
| Reviewer | `reviewer.md` | `errors` | accepts the result: is it correct |
| Recorder | `recorder.md` | n/a | writes to the DB and files exactly what the brief dictates |
| Verifier | `verifier.md` | n/a | runs exact commands, returns output/checklist, no overall verdict |
| Searcher | `searcher.md` | n/a | web research only; report with cited URLs; no project edits |

One agent never holds two roles on the same step. When both reviewer roles are required for L, the architect and the reviewer are never the executor and work independently: neither sees the other's verdict before both have answered.

## Rules for all roles

1. **Scope.** Touch only what the brief lists. Everything else is off limits, read or write.
2. **Read-only by default.** Only the executor and the recorder may write (the verifier and the others only their own result file), and only the files and rows the brief allows. Architect and reviewer write nothing except their own report file.
2a. **Web lookups.** Internet research goes only to the `searcher` role; queries must stay generic (no project code, secrets, paths or private data).
3. **Evidence.** Every statement has a source: file and line, commit hash, or a command with its short output. A statement without a source is rejected.
4. **No guessing.** If something is missing or unclear say exactly what is missing. Use `cannot tell` and write where you looked.
5. **No git writes.** Never commit, push, fetch, checkout, switch, reset, stash, rebase. Read-only git is fine.
6. **No side effects.** Do not install packages, start or stop containers or browsers, call other services, or run tests and type checks unless the brief says so.
7. **No secrets.** Do not read or copy tokens, `.env` content or credentials, and do not paste them into reports.
8. **Handshake first.** If the brief asks for it, answer only with: (a) the task in your own words, 2 lines; (b) what you will not touch; (c) questions or missing information; (d) how you will report. Do not start the work until the orchestrator says go.
9. **Talk only to the orchestrator.** Not to the user, not to other agents. Questions go in your report or the handshake.
10. **Format.** Answer in the requested format only. No introduction, no praise, no extra sections. Write the report to the file the brief names and reply with the path and two lines.
11. **Stop** when the task is done. No extra improvements.

## How the orchestrator uses these files

The orchestrator does no project work itself (see "No self-work" in `ORCHESTRATOR.md`): delegated actions, including DB writes and verification commands, are briefs to one of these roles. Put `Role: <role>` and a role card of at most 10 inline lines in the brief; include the role-specific directions needed for the task rather than requiring a cold-start agent to load these files. When reviews are required, the recorder logs their findings in `reviews`, and the orchestrator evaluates them from evidence like any other result.
