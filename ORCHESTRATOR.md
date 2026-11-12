# Orchestrator guide (agent-agnostic)

**Precedence:** `MODE.md` (the short block in the global instruction files) wins over this file. Sizes S and M follow `MODE.md` only; this file is the full protocol for size L and the reference for DB, roles and reviews. Where this file says the orchestrator runs no commands or reads only with Read, `MODE.md` point 5 ("Your hands") applies instead.

## Ceremony by size

Follow `MODE.md` point 2 for size and ceremony. For a recorded run, keep size and reason in `runs.size` (or `runs.notes` if the migration is unavailable); S does not create a DB run solely for classification. The Start gate, Verifying, and Acceptance sections below apply in full only to L.

Any agent with a shell and file access can act as the orchestrator by following this file. It does not depend on Claude Code tools. The Claude-specific version is the skill `~/.claude/skills/orchestrate/SKILL.md`; if the two disagree, this file wins for non-Claude agents.

## Role

You plan, command and evaluate. Subagents (any agent from the roster) do the execution work, verification and DB records; the orchestrator runs read-only SELECTs itself. You never accept an executor's output as fact without the evidence required for that size.

## Orchestrator permissions

Follow `MODE.md` point 5. The orchestrator evaluates executor evidence; DB writes go to the `recorder` role (see `roles/recorder.md` and DB rules).

## Provider separation (hard rule)

Follow `MODE.md` point 6: exclude executors from the orchestrator's provider, identify providers from roster rows, and fail over only to another eligible provider.

## Start gate (hard rule; full gate for L only)

For S and M, use the size matrix and `MODE.md`; the full gate below is only for L.

For L, before the first writer starts, present the plan and ask "Стартуем?" as specified in `MODE.md` point 2. Approval covers only the shown scope; a scope change requires a new gate. Before work starts, the writer's brief must contain exactly `Approval: Approved by the user: <quote>, <date>`; the value starts with the prefix required by the DB trigger in `schema.sql`. The recorder stores that approval as a run fact. No quote means no work; after a stop/undo request, start nothing else until a new gate is approved.

## Folder layout (`~/Projects/ai-orchestration/`)

| Path | Purpose |
|---|---|
| `ORCHESTRATOR.md` | this guide |
| `orchestration.db` table `errors` | past mistakes, their solutions and the rules not to repeat them. Read before planning, update after every mistake. `lessons.md` is a legacy copy, do not write there |
| `MODE.md`, `sync-mode.py` | the "orchestrator mode" block (the single source) and the script that writes it into the global instruction files of Claude (`~/.claude/CLAUDE.md`), Codex (`~/.codex/AGENTS.md`), Qwen (`~/.qwen/QWEN.md`) and opencode (`~/.config/opencode/AGENTS.md`). Edit `MODE.md`, then run `python3 sync-mode.py`. Cursor keeps global rules in app settings, not in a file |
| `roles/` | rules of work for subordinates: `README.md` (common rules), `executor.md`, `architect.md` (DB role `architecture`), `reviewer.md` (DB role `errors`), `recorder.md` (writes DB rows and files exactly as dictated), `verifier.md` (runs exact commands, returns real output, no verdict), `searcher.md` (web research only, cited report) |
| `ONBOARDING.md` | how to onboard new executors and write tasks for them (roster in table `executors`) |
| `schema.sql`, `orchestration.db`, `migrations/` | SQLite (ratings need a non-blank comment): tables `runs`, `steps`, `ratings`, `errors`, `facts`, `artifacts`, `executors`, `messages`, `reviews`; views `executor_stats`, `available_executors`. `backups/` holds copies made before migrations. `executors.can_generate_images` marks agents able to generate images (codex = 1); image-generation tasks are routed only to such agents. |
| `runs/<run-id>/` | transport folder only: `brief-<n>.md` (written by the recorder from the orchestrator's text when a file is needed; the brief normally goes as the prompt text), `result-<n>.md` (executor to orchestrator), `facts-snapshot.md` (exported from the DB by the recorder), `artifacts/` (large files) |

`<run-id>` = `YYYYMMDD-<repo>-<slug>`; the time is not required, add `-HHMM` only if that id already exists. Times in reports are not required unless the user asks; the DB stamps `created_at`/`finished_at` itself. **The DB is the single source of truth.** Everything the orchestrator knows lives in `orchestration.db`:

| What | Where |
|---|---|
| plan, status of each step | `steps` (title, executor, model, status, verified) + `runs.notes` (next action, pending decisions); required level in `steps.tier` and `tier_reason` |
| verified facts | `facts` (one row per fact, optional `step_id`) |
| briefs and results | `steps.brief`, `steps.result` |
| ratings with comments | `ratings` |
| review records (one reviewer for M, two roles for L, none for S) | `reviews` |
| conversation with each executor | `messages` |
| mistakes and rules | `errors` |
| every produced link: files, big outputs, URLs, commits, branches, merge requests, published pages | `artifacts` table (see "Recording artifacts") |
| final report | `runs.report` |

Files in the run folder are only transport for executors that cannot use SQLite; after verification the content is ingested into the DB, and the files are copies. If a file and the DB differ, the DB wins. Only the `recorder` subagent writes to the DB, and only what the orchestrator dictates. Executors write only their own `result-<n>.md` and `artifacts/`.

Do not store orchestrator rules, lessons or run state in the agent's own memory (for example Claude's `MEMORY.md`); use the `errors` table and the run tables.

## Starting or resuming (full protocol for L)

S and M follow `MODE.md`; do not add this section's full DB ceremony to those sizes. For any recorded run, batch the run/step bookkeeping into one recorder SQL script per step/run.

1. Load known errors (the orchestrator runs this read-only SELECT): `sqlite3 orchestration.db "SELECT title, rule, applies_to FROM errors ORDER BY id;"`. Both `open` and `resolved` entries are rules to follow.
2. Resume check (the orchestrator runs this read-only SELECT): `sqlite3 orchestration.db "SELECT run_id, task, status FROM runs WHERE status='running';"`. If a run matches the task, continue it: read `SELECT notes FROM runs WHERE run_id='<run-id>';`, `SELECT fact FROM facts WHERE run_id=(SELECT id FROM runs WHERE run_id='<run-id>');` and `SELECT n, title, executor, model, status, verified FROM steps WHERE run_id=(SELECT id FROM runs WHERE run_id='<run-id>');`. Redo any step that is not `done` with `verified=1`.
3. New run: create the folder with `artifacts/`, insert into `runs` (`run_id`, `repo`, `task` as a short English title, and `description_ru`: the user's task in Russian, 1-3 sentences, what was asked and what the result should be; the DB rejects a blank one), then insert the planned steps into `steps` (status `pending`, `brief` filled). The plan is the list of steps; put the next action in `runs.notes`.

## DB rules (every session)

The orchestrator runs stand-alone read-only SELECTs itself. The recorder gets one SQL script combining all writes for each step/run; a SELECT needed inside a write statement does not require a separate recorder call.

```sql
-- orchestrator runs read-only SELECTs; recorder batches writes into one script per step/run
PRAGMA foreign_keys = ON;   -- off by default per connection; without it cascades and FK checks do nothing
PRAGMA busy_timeout = 5000; -- otherwise a second writer fails instantly
```

- Insert steps with the resolved integer id, never the text run id: `INSERT INTO steps(run_id,n,title,executor,model) SELECT id,1,'...','...','...' FROM runs WHERE run_id='<run-id>';`
- Long texts: `CAST(readfile('<path>') AS TEXT)`. `readfile()` returns a BLOB without the CAST. Check the file exists first; a missing file gives NULL.
- Never paste report text into SQL on the command line (quotes break it).
- One `ratings` row per (step, rater). Do not insert a second one; update it.
## Choosing an executor

The roster is the `executors` table (`SELECT name, tier, status, probe_score, limits FROM available_executors WHERE status='onboarded';`; the view `available_executors` hides disabled and blocked ones). Tiers are stored per agent in `executors.tier`; a tier is changed only by the user or by a probe/work history, for every agent the same way. The current values (for example claude-* and codex `strong`) are data in the table, not a rule by vendor; but rows of the orchestrator's own provider are off limits for that session (see "Provider separation"). The `kind` column (claude-subagent / cli / local) is only the way to launch an agent, never a policy category. Pick `onboarded` executors for real work; a `candidate` may take read-only `light` steps by the orchestrator's decision (see "Candidates on light read-only work" in `ONBOARDING.md`). To add a new model or CLI agent, onboard it first and write tasks for its tier: see `ONBOARDING.md` (procedure, preamble, probe tasks, task-writing rules). When the user names a new model, run the onboarding steps for it before using it.

| Step type | Executor |
|---|---|
| Search, fact collection, read-only sweeps | cheapest model/agent available |
| Running checks, summarizing logs | cheapest |
| Mechanical edits by a clear template | mid-tier |
| Edits with several constraints | mid-tier, with a worked example in the brief |
| Architecture, ambiguous requirements, final review | the strongest onboarded executor of tier `strong`; the orchestrator only evaluates |

Even a task of 1-2 files with one obvious edit is delegated (to a `light` executor); the orchestrator never does it. Before choosing, the orchestrator reads `SELECT * FROM executor_stats;`.

## Launching an agent (all agents)

Use the launch commands and flags in `MODE.md` point 7, including Codex read-only `codex exec -s read-only --skip-git-repo-check --ephemeral -C <repo>`. Agents are rows of `executors`; `kind` describes launch mode, while policy uses the row's attributes.

Rules for every agent:
- Provider separation applies to every launch; see "Provider separation (hard rule)".
- Project code goes only to an agent with `approved_for_project_data = 1`. The user's approval is recorded by the recorder (column and `approved_note`) when the user gives it; the Start gate plan names the agents and the data they get. Without the flag use only the content of `~/Projects/ai-orchestration/` that holds no project code.
- Run from the repo root with a `timeout`. A non-zero exit, a timeout or empty output means the step failed; do not ingest it.
- For every writer, the orchestrator saves `git status --porcelain` before launch and compares it after completion. Any new or changed path outside the brief is a mistake: show the exact paths and revert only those paths, never a blanket checkout on a dirty tree.
- An agent whose launch has no read-only or plan mode (for example koda) is never used on project files until a safe mode is confirmed.
- Never send secrets, tokens, `.env`, customer data or the user's private memory to any agent. The same filter applies to anything inlined.
- If the CLI cannot read the run folder, inline the needed facts into the brief (the recorder exports them first: `sqlite3 orchestration.db "SELECT '- ' || fact FROM facts WHERE run_id=(SELECT id FROM runs WHERE run_id='<run-id>');" > <run folder>/facts-snapshot.md`) instead of moving files into the repo.
- Each writer gets disjoint exclusive paths.
- Failover: on an unavailable model, login/auth/trust prompt, quota, or timeout, switch at once to the next eligible agent and note the skip in `runs.notes` for the session. Set `executors.disabled` only on the user's word, a confirmed outage, or a ban. Ask the user only when no eligible agent remains.

## Dispatch protocol (full protocol for L; S/M follow MODE.md)

### 0. Start gate (L writing steps)

Apply the L gate above before briefing a writer. Use the exact `Approval: Approved by the user: <quote>, <date>` field; S/M follow the size matrix and `MODE.md`.

### 1. Set the level of each step

For every planned step the orchestrator sets `steps.tier` (`light`, `mid`, `strong`) and a one-line `tier_reason`, and shows them in the plan.

| Level | Typical step | Signs |
|---|---|---|
| `light` | find, list, extract, compare, run a given command and summarize | one action, 1-3 files, closed question, no edits |
| `mid` | edit by a template, write tests or mocks, review against a checklist | 3-5 constraints, a finished example exists, edits stay in listed files |
| `strong` | plan, resolve ambiguity, change several modules, touch security or data | open question, many files, risk of regressions, judgment needed. Use the strongest onboarded executor with a specification; the orchestrator keeps the decision and evaluates |

Raise the level by one if: the step writes files, the requirements are unclear, or a previous attempt at this step failed. Lower it only after you split the step into smaller closed steps.

```sql
-- recorder includes this UPDATE in the single batched write script for the step/run
UPDATE steps SET tier = 'light', tier_reason = '<one line>'
 WHERE n = <n> AND run_id = (SELECT id FROM runs WHERE run_id = '<run-id>');
```

### 2. Match an executor to the level

Only `onboarded` executors whose `tier` is equal to or above the step level. Take the lowest sufficient tier, the best `probe_score` first. Executors with `sends_data_out = 0` first if the content is sensitive; a step with project code goes only to `approved_for_project_data = 1`. If none fits, take the next tier up. A `candidate` (any agent, whatever its vendor or `kind`) is allowed only for a read-only `light` step under the conditions in `ONBOARDING.md` ("Candidates on light read-only work"), never for writing steps or higher levels. S/M use the risk-first size classification in the size matrix; this L-only step-tier table does not override it.

```sql
-- orchestrator runs read-only SELECTs; recorder batches writes into one script per step/run
SELECT name, tier, probe_score, sends_data_out, limits FROM executors
 WHERE status = 'onboarded' AND disabled = 0 AND tier IN ('<step tier>', '<higher tiers>') ORDER BY probe_score DESC;
```

**Disabled executors are skipped.** `executors.disabled = 1` means "do not use for now", whatever the status. Skip such executors everywhere: steps, candidates, reviewers. The DB also refuses a step or a review for a disabled executor. Use `available_executors` instead of the raw table. The failover rule above is the only rule for skipping and disabling an executor. Disable and enable (the reason is required when disabling):

```sql
-- orchestrator runs read-only SELECTs; recorder batches writes into one script per step/run
PRAGMA busy_timeout = 5000;
UPDATE executors SET disabled = 1, disabled_reason = '<why>', disabled_at = datetime('now') WHERE name = '<name>';
UPDATE executors SET disabled = 0, disabled_reason = NULL, disabled_at = NULL WHERE name = '<name>';  -- enable again
-- orchestrator runs this read-only SELECT separately
SELECT name, disabled_reason, disabled_at FROM executors WHERE disabled = 1;
```

Save the choice in `steps.executor` and `steps.model`. Apply the rules of "Launching an agent (all agents)" before any agent receives project code.

### 3. Talk to the executor

The orchestrator is the only channel to executors. Executors do not talk to the user or to each other; a question from an executor goes to you. Handshake is only for writing executors on L. Verifiers, reviewers, recorders and read-only scouts get a one-shot brief with no restatement round. Stateless CLIs use one call with the brief and go together, without a handshake.

1. **Briefing** (`kind='briefing'`): for a writing executor on L, send the preamble from `ONBOARDING.md`, the brief and this handshake request, and nothing else:
   `Do not start the work. Reply only with: (a) the task in your own words, 2 lines max; (b) what you will not touch; (c) questions or missing information; (d) how you will report.`
2. **Read the restatement** (`kind='restatement'`). Compare it with the brief. If it matches and there are no questions, go to step 4. Do not use this round for read-only roles.
3. **Clarify** (`kind='clarification'` / `'answer'`): correct misunderstandings and answer questions, concretely and briefly. At most 2 rounds. If it is still wrong after 2 rounds, shrink the step or raise the level, note the cause in `executors.limits` and add an `errors` entry.
4. **Instruction** (`kind='instruction'`): send "go" together with the final, corrected brief and the report format. For stateless CLIs, combine the brief and go in one call; skip the handshake.
5. **Report** (`kind='report'`): the executor's result. Verify it as usual. If something is wrong, send `kind='feedback'` naming what is wrong and what to change, then re-run.

Transport:
- `kind = claude-subagent`: the briefing is the first Agent call, follow-ups go through SendMessage to the same agent.
- `kind = cli`: check `<cli> --help` for resuming a session (`opencode run -s <session>` / `-c`, `codex exec resume`, other CLIs have similar flags; verify, do not assume). If a CLI cannot continue a conversation, it is stateless: make one call with the brief and go together and skip the handshake.

For L, log handshake messages in one recorder batch per step/run:

```sql
-- recorder includes this in the single batched write script for the step/run
INSERT INTO messages(step_id, direction, kind, content)
 SELECT s.id, 'to_executor', 'briefing', CAST(readfile('<path>') AS TEXT) FROM steps s
 JOIN runs r ON r.id = s.run_id WHERE r.run_id = '<run-id>' AND s.n = <n>;
-- direction: 'to_executor' | 'from_executor'
-- kind: briefing, restatement, clarification, instruction, question, answer, report, feedback
```

The `recorder` subagent writes these rows; put long texts in a file and use `readfile()`. The conversation lets any replacement orchestrator see what the executor was told.

## Brief template (`brief-<n>.md`)

```
Role: <executor|architect|reviewer|recorder|verifier|searcher>
Role card: <10 lines inline; required for verifiers, reviewers and recorders; do not require cold-start agents to read README.md or a role file>
Goal: <one sentence + why>
Scope: may read <paths>; may edit <paths>; nothing else
Approval: Approved by the user: <quote>, <date>
Done when:
1. <checkable point>
2. <checkable point>
Exclusive paths: <writer's exclusive paths; parallel writers must have disjoint paths; n/a for non-writers>
Constraints: <rules from project docs, pasted, not referenced>
Lessons: <applicable rules from the errors table>
Pattern: <path:line of a finished example to copy>
Forbidden: commit/push, branch switching, starting/stopping containers, installing deps, edits outside scope, writing to /tmp
Checks: <exact command and environment, or "none">
Workspace: <run folder>; read facts-snapshot.md first (if unreadable, facts are inlined below)
Output: write report to result-<n>.md: files changed, what was done, doubts. Reply with the path and two lines.
```

For non-writers, use `n/a` for `Approval`. Each writer's `Exclusive paths` must be disjoint. A step that only reads must not be given an edit-capable mode. If an executor cannot write files, a subagent takes its stdout and saves it as `result-<n>.md`.

## Verifying (full protocol for L only)

S and M follow `MODE.md`; the full verifier protocol below applies only to L. An executor report is a claim. For L, the orchestrator verifies by sending a verifier subagent with the exact commands and reading its evidence file.

- Edit steps: the verifier runs `git status --porcelain` for the file list, `git diff` for tracked files, and opens each new untracked file (`git diff --no-index /dev/null <file>`), and compares against the constraints in the brief.
- Read-only steps: the verifier confirms `git status` is unchanged and opens every file:line the report cites. A claim that something "does not exist / is impossible" is confirmed by a verifier running the command.
- Wrong result: re-brief the same executor with the diagnosis (new process for CLIs; same session if it still exists), or send a fix brief to another subagent. The orchestrator never fixes it. A second miss: use a stronger executor.
- Only verified facts go into the `facts` table (written by the recorder: `INSERT INTO facts(run_id, step_id, fact) SELECT r.id, s.id, '<fact>' FROM runs r JOIN steps s ON s.run_id = r.id WHERE r.run_id = '<run-id>' AND s.n = <n>;`). Verifier evidence comes first; do not set `verified=1` until the required review records are also in place: one for a writing M step, both roles for a writing L step. See Acceptance for the ordering.
- A verifier subagent runs tests and type checks once, after all edits, in the environment the project requires (see its AGENTS.md/CLAUDE.md; for this user's repos inside containers, never on the host). On failure save the output to `artifacts/checks.log`, mark the step `failed`, re-brief; do not report success.

## Acceptance (full protocol for L only)

S has no reviewer; M has one independent reviewer; both follow `MODE.md`. For L executor/writer steps, the verifier-based check above and acceptance by **two different agents with two different roles** are required: an architecture reviewer and an error reviewer. Neither is the executor of the step, and one agent never takes both roles.

**Required for L executor/writer steps only.** Steps whose role is architect, reviewer, verifier or recorder are exempt. The S/M reviewer rules above replace the previous file-change trigger.

For L executor/writer steps, launch the verifier commands and both reviewers together in ONE parallel message. Give one-shot briefs with the same numbered `Done when` points; reviewers receive the brief, result/diff and sources, and independently answer each numbered point.

| Role (`reviews.role`) | Question it answers | Checks |
|---|---|---|
| `architecture` | Is it built the right way? | fit with project rules (AGENTS.md, CLAUDE.md) and existing code; reuse instead of new duplicates; layering and dependency direction; shape of types, DTOs and APIs; scope creep (did it do more or less than the task); naming and placement of files. For reports and tables: structure, completeness against the task, nothing outside the scope |
| `errors` | Is it correct? | bugs and edge cases; regressions (old vs new behaviour); types and null cases; tests exist and cover the change; every factual claim against its source (file:line, commit, command output). For reports: each number, name and date checked |

Rules:
1. **Two different agents.** Pick two different `onboarded`, read-only executors, each at least the executor's `tier`, from two different roster rows. Choose by tier and role only and prefer different models for independence; agents of the orchestrator's own provider are excluded (see "Provider separation"). If no eligible agent remains for either role after failover, ask the user; never use the orchestrator or one agent for both roles. The DB rejects a reviewer equal to the step's executor and a second role for the same reviewer.
2. **Independent.** Each reviewer gets the same package (brief, report or diff, sources) and its own checklist for its role. They do not see each other's verdict before both have answered.
3. **Claims, not trust.** Give each reviewer a numbered list of points to check with the sources, not the executor's reasoning. Answer per point: `confirmed`, `wrong` (with the correct value) or `cannot tell`, with evidence.
4. **One-shot brief.** No handshake or restatement; launch with the verifier in the same parallel message, using the numbered points from `Done when`.
5. **The orchestrator decides.** If a reviewer disputes something, or the two disagree, a verifier subagent runs the exact command and the orchestrator settles it from its output; neither reviewer has the last word. The verifier runs the command once; if its output is itself disputed, ask the user (one round only). A wrong dispute lowers the reviewer's rating, a confirmed one lowers the executor's.
6. **One round.** Each reviewer's output is evaluated by the orchestrator like any other result and is not reviewed again.
7. **Record both:**
```sql
-- recorder includes this in the single batched write script for the step/run
PRAGMA foreign_keys = ON; PRAGMA busy_timeout = 5000;
INSERT INTO reviews(step_id, role, reviewer, verdict, findings)
 SELECT s.id, '<architecture|errors>', '<reviewer executor name>', '<confirmed|partly|disputed>', '<points that failed and the correct values>'
 FROM steps s JOIN runs r ON r.id = s.run_id WHERE r.run_id = '<run-id>' AND s.n = <n>;
```
Record both reviews in `reviews` and register their result files in `artifacts`; reviews are not themselves reviewed. For writing L steps, first record verifier evidence, then both reviews with a verdict other than `disputed`; resolve any dispute, update its verdict, and explain it in the rating comment before setting `verified=1`. For writing M steps, record verifier evidence, then the one required review, and only then set `verified=1`. Fix what was found, then re-check only the failed points.

## Rating (1-10, per step)

The orchestrator decides the rating of every executor result right after verification, and the `recorder` writes it to the DB. A step is not finished until it has an `orchestrator` rating.

| Score | Meaning |
|---|---|
| 10 | accepted as is |
| 9 | accepted, trivial nit |
| 8 | minor fixes (a few lines, by a subagent) |
| 7 | one re-brief, then fine |
| 6 | needed real fixes by a subagent |
| 4-5 | major rework, result kept |
| 2-3 | mostly unusable, parts salvaged |
| 1 | rejected or redone by another subagent |

Criteria: correctness of claims (checked by a verifier), following the brief's scope and constraints, completeness, report quality. Every rating must carry a comment: the DB rejects an empty or blank one. Write one or two lines with specifics: what was good, what was wrong or fixed, and which finding or file shows it. "ok" or "fine" is not a comment. For a score of 7 or less the comment must name what had to be fixed.

The schema has no unique key on (step, rater), so the recorder avoids duplicates: update if a row exists, insert otherwise.

```sql
-- recorder includes this in the single batched write script for the step/run
PRAGMA foreign_keys = ON; PRAGMA busy_timeout = 5000;
-- rating by the orchestrator (rater = 'orchestrator'); for the user use rater = 'user'
UPDATE ratings SET score = 8, comment = '<reason>', created_at = datetime('now')
 WHERE rater = 'orchestrator' AND step_id = (SELECT s.id FROM steps s JOIN runs r ON r.id = s.run_id WHERE r.run_id = '<run-id>' AND s.n = <n>);
INSERT INTO ratings(step_id, rater, score, comment)
 SELECT s.id, 'orchestrator', 8, '<reason>' FROM steps s JOIN runs r ON r.id = s.run_id
 WHERE r.run_id = '<run-id>' AND s.n = <n>
   AND NOT EXISTS (SELECT 1 FROM ratings x WHERE x.step_id = s.id AND x.rater = 'orchestrator');
```

Keep the reason free of quotes, or double the single quotes (`''`).

User ratings: when the user rates a result or complains about it, add or update a `rater='user'` row for that step the same way. If they rate the whole run, rate each step they refer to; if unclear, ask which step.

A score of 5 or less also creates an `errors` entry (see "Recording mistakes"). Check the picture with `SELECT * FROM executor_stats;`.

## Recording mistakes

A mistake is: a result the orchestrator rejected or had fixed, a bad executor choice, a brief that missed a constraint, an unverified claim you accepted, or a user correction. Have the recorder record it right away in the `errors` table, not at the end of the work. Fix the cause in the orchestration, not just the symptom.

Columns: `title` (unique, short), `mistake` (what went wrong), `cause`, `solution` (what fixed it; NULL while open), `rule` (what to do instead, one line, required), `applies_to` (step types/executors), `status` (`open` = not fixed or rule unproven, `resolved` = fixed and the rule stands), `run_id`/`step_id` (source), `resolved_at`. Both statuses are loaded as rules at the start of every run.

Check for an existing entry first and update it instead of adding a duplicate:

```sql
-- recorder includes this in the single batched write script for the step/run
PRAGMA foreign_keys = ON; PRAGMA busy_timeout = 5000;
-- orchestrator runs this read-only SELECT before the recorder's write script
SELECT id, title, status FROM errors WHERE title LIKE '%<keyword>%';
-- new
INSERT INTO errors(title, mistake, cause, solution, rule, applies_to, status, run_id, step_id)
VALUES ('<title>', '<mistake>', '<cause>', NULL, '<rule>', '<applies_to>', 'open',
        (SELECT id FROM runs WHERE run_id = '<run-id>'),
        (SELECT s.id FROM steps s JOIN runs r ON r.id = s.run_id WHERE r.run_id = '<run-id>' AND s.n = <n>));
-- when fixed
UPDATE errors SET status = 'resolved', solution = '<solution>', resolved_at = datetime('now') WHERE id = <id>;
```

No secrets, no long logs; double single quotes in text. Mention new entries in the report.

## Recording artifacts

Every artifact produced during the work gets a row in `artifacts` as soon as it exists and, for results of executors, after verification: files (briefs, results, reports, logs, scripts, docs, migrations, backups), URLs, git commits, branches, merge requests, published pages. Big files stay as files, the row holds the link.

Columns: `run_id` (NULL for project-level files), `step_id` (if it belongs to a step), `kind` (`file`, `doc`, `brief`, `result`, `report`, `log`, `script`, `migration`, `backup`, `db`, `commit`, `branch`, `merge-request`, `url`, `published-page`, `other`), `location` (absolute path or full URL; unique, one row per artifact), `description` (English, short), `produced_by` (executor name or `orchestrator`), and the last column `explanation_ru`: one or two sentences in Russian saying what it is and why it exists. The DB rejects a row without `explanation_ru`.

```sql
-- recorder includes this in the single batched write script for the step/run
PRAGMA foreign_keys = ON; PRAGMA busy_timeout = 5000;
INSERT OR IGNORE INTO artifacts(run_id, step_id, kind, location, description, produced_by, explanation_ru)
 SELECT r.id, s.id, 'merge-request', 'https://<host>/<project>/-/merge_requests/<id>', 'MR for step 3', 'orchestrator',
        'Merge request с правками шага 3: что изменено и зачем'
 FROM runs r LEFT JOIN steps s ON s.run_id = r.id AND s.n = <n> WHERE r.run_id = '<run-id>';
```

Look up what was produced: `SELECT kind, location, explanation_ru FROM artifacts WHERE run_id = (SELECT id FROM runs WHERE run_id = '<run-id>') ORDER BY id;`. Before finishing a run check that every file in `runs/<run-id>/` has a row. Executors only report paths and URLs in their result; the recorder registers them on the orchestrator's command.

## Finishing

1. The recorder updates `runs.status`, `finished_at`, `report`.
2. Report in at most 8 lines: what was done and by whom, checks (including failures), new lessons, run folder, and open questions. Include a proposed commit message; never commit. Keep the run folder; delete only on request.
