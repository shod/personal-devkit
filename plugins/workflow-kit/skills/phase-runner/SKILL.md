---
name: phase-runner
description: >-
  Phase orchestrator from tasks.md: automatically determines which phase tasks
  to run in parallel ([P]-marker) and which sequentially — and calls
  the corresponding agents (task-runner-parallel or task-runner).
  Use /phase-runner 4 or /phase-runner "Phase 4" for full execution
  of all phase tasks with correct parallelism. Indispensable when you need to run
  an entire phase with one command without manually parsing tasks.
argument-hint: "<phase-number-or-name>"
allowed-tools: Agent Read Grep Glob Skill AskUserQuestion Edit Bash PowerShell TodoWrite
model: haiku
metadata:
  author: speckit
  version: "1.0"
  category: task-orchestration
---

# Phase Runner — Task Phase Orchestrator

Reads tasks.md, determines which tasks belong to the requested phase, and runs the whole
phase on **ONE phase branch** (`{phase_branch_prefix}{N}`, e.g. `phase/3`):
- Create the phase branch **once** (from the feature branch).
- Run all phase tasks ON it — one commit per task (traceability preserved):
  - **In parallel** (`[P]`-marked tasks) → `task-runner-parallel` (isolated worktrees, each fast-merged back into the phase branch, serialized)
  - **Sequentially** (tasks without `[P]`) → `task-runner`
- Run **Pint + PHPStan + Tests ONCE** for the whole phase (CHECKS), then **ONE `--no-ff`
  merge** of the phase branch into the feature branch.

This replaces the old branch-per-task model (one branch + one merge + one full check run
per task) — collapsing N×(branch+merge+checks) into 1×(branch+merge) + 1×(checks) per phase.
Checks are deferred to phase level via `--defer-checks` on each task and run via
`task-finish --scope=phase --phase-action=CHECKS`.

## Required argument

`$ARGUMENTS` **MUST** contain a phase number or name.

Accepted formats:
- `4`
- `Phase 4`
- `phase 4`

If `$ARGUMENTS` is empty — **STOP** and ask the user:
> Specify the phase number: `/phase-runner 4`

---

## Algorithm

### Step 1: Parse the argument

1. Extract the phase number from `$ARGUMENTS` (first digit or number)
2. If not found — stop and ask the user to specify

### Step 2: Load tasks.md (resolve the ACTIVE spec — there are usually many)

1. Find all `specs/*/tasks.md` via Glob. **There will normally be several** (each completed feature keeps its tasks.md). Do NOT assume the first/only one.
2. **Pick the ACTIVE spec** — the one this run targets — by this precedence:
   a. If `$ARGUMENTS` names a spec (e.g. `/phase-runner 4 007` or `/phase-runner 4 bookings-export`), use that spec.
   b. Otherwise, match the **current git branch** to a spec: run `git branch --show-current`, and prefer a `specs/NNN-*/tasks.md` whose number/slug the branch name references, OR whose recent commits (`git log --oneline -5`) reference task IDs (`T\d+`) that live in that file.
   c. Otherwise, among the spec files that still have **open tasks** (lines `- [ ]`), pick the one whose phase `{N}` contains unchecked tasks. Run `grep -c '\- \[ \]' specs/*/tasks.md` to see which specs are live.
   d. If still ambiguous (e.g. multiple live specs have an unchecked Phase {N}) → **STOP** and ask the user via AskUserQuestion which spec to run, listing the candidate paths.
3. **Save the chosen path** as `$TASKS_PATH` (e.g. `specs/007-bookings-export-fields/tasks.md`) — used in all agent prompts below. State the resolved spec to the user before proceeding.
4. Read the file in full
5. Find the phase section matching:
   - `## Phase {N}:` — e.g. `## Phase 4:`   
6. If not found → **STOP**: "Phase {N} not found in {$TASKS_PATH}"

### Step 3: Extract phase tasks

From the phase section extract all tasks in the format:
```
- [ ] T025 [P] [US2] Description...
- [x] T026 [US2] Description...  ← already done
- [ ] T027 [US2] Description...
```

For each task determine:
- **TASK_ID**: pattern `T\d+`
- **is_parallel**: `[P]` marker present in the task line
- **is_done**: task is marked `[x]` or `[X]`

### Step 4: Analyse completed tasks

Exclude tasks marked `[x]`/`[X]` from the execution list.

If **all phase tasks are already done** → print:
```
✓ Phase {N} is already fully complete (all tasks [x])
  Tasks: {TASK_ID list}
```
and exit.

### Step 4.5: Flag manual / non-automatable tasks

Some tasks cannot be done by a `task-runner` agent — they require a human (browser UI, visual inspection, external dashboards). Detect these by keywords in the task text: **"manual"**, **"smoke test"**, **"log in to admin"**, **"open the file"**, **"click Export"**, **"verify against contracts"** by eye, **"browser"**, **"screenshot"**, anything describing UI interaction or visual confirmation (e.g. the typical `T022` quickstart smoke test).

For each such task:
- Mark it `⊘ MANUAL` in the plan; do NOT delegate it to an agent and do NOT mark it `[x]`.
- Leave its checkbox `[ ]` and surface it to the user in the final report with the exact manual steps and any context they need (e.g. the local dev URL).
- If the user's confirmation in Step 5 chooses to attempt it via a browser MCP (Playwright/Chrome DevTools), do so directly from phase-runner — not via task-runner — and only mark `[x]` if it genuinely passes.

### Step 5: Show execution plan

Build the execution schedule by walking tasks in **tasks.md order** and grouping consecutive `[P]` tasks into a single parallel batch. Manual tasks (Step 4.5) are listed separately as `⊘ MANUAL` and excluded from the agent batches. Sequential tasks that appear before, between, or after a parallel group run in their natural order. Example:

```
T009 (sequential) → [T010, T011] (parallel batch) → T012 (sequential)
```

Show the user the plan before starting:

```
═══════════════════════════════════════════════════
  Phase Runner: Phase {N}   →   branch {phase_branch_prefix}{N}
═══════════════════════════════════════════════════
  Model: 1 phase branch → {pending} tasks → 1 CHECKS → 1 merge
  Total tasks: {total}  |  Skipped (done): {done}
  To run: {pending}

  ▶ Parallel [P]:
    {parallel_tasks list with descriptions}

  ▶ Sequential:
    {sequential_tasks list with descriptions}

  Execution order (tasks.md order, [P] groups fire simultaneously):
    0. Create branch {phase_branch_prefix}{N}
    1. {T009} — sequential       (commit onto phase branch)
    2. {T010, T011} — parallel batch (worktrees → merged back into phase branch)
    3. {T012} — sequential       (commit onto phase branch)
    4. CHECKS: Pint + PHPStan + Tests (ONCE)
    5. Merge {phase_branch_prefix}{N} → {current_branch} (--no-ff, ONCE)
═══════════════════════════════════════════════════
Start? (yes/no)
```

If the phase has **only parallel** or **only sequential** tasks — show the appropriate simplified plan.

Ask for confirmation via **AskUserQuestion** before starting.

### Step 5.5: Pre-flight git health + resolve the feature branch & task-branch naming

Before starting any tasks:

1. **Git health:**
   ```
   git config --list > /dev/null
   ```
   If this fails with `fatal: bad config line`, `.git/config` is corrupted. **STOP** immediately and report — do not attempt any task.

2. **Resolve `{current_branch}` from git, NOT from config.** Run `git branch --show-current` and use that as `{current_branch}`. ⚠️ Do **not** trust the `feature_branch` key in `.claude-project.json` — it is frequently STALE (e.g. it may name an old feature branch while the real working branch differs). The branch you are checked out on is the source of truth. Pass this resolved branch to every agent.
3. **Resolve the phase-branch name and the (ephemeral) task-branch prefix.**
   - Read `phase_branch_prefix` from `.claude-project.json` `paths` (e.g. `phase/`). Set **`PHASE_BRANCH = {phase_branch_prefix}{N}`** (e.g. `phase/3`). This is the ONE branch that holds the whole phase. The flat form avoids the nested-ref problem (git cannot create `{current_branch}/...` under an existing `{current_branch}` ref).
   - Read `task_branch_prefix` (e.g. `task/`). It is still needed for `[P]` **worktree** branches: parallel tasks branch off `PHASE_BRANCH` HEAD as `{task_branch_prefix}{TASK_ID}` and merge **back into `PHASE_BRANCH`** (not the feature branch).
   - Pass both `PHASE_BRANCH` and `task_branch_prefix` explicitly to every agent.

### Step 5.6: Create the phase branch (ONCE)

Before running any task, create the phase branch from the feature branch:

```
Skill: task-finish "{N} --scope=phase --phase-action=CREATE --auto"
```

Then verify: `git branch --show-current` **MUST** equal `PHASE_BRANCH`. If not → **STOP**
and report (do not run any task off the wrong branch). From here on, `PHASE_BRANCH` — not
the feature branch — is the integration target for every task in this phase.

### Step 6: Parallel batch (if [P] tasks exist)

If `parallel_tasks` is not empty:

```
═══════════════════════════════════════════════════
  [1/2] Parallel batch: {TASK_ID list}
═══════════════════════════════════════════════════
```

**Before delegating — check for a shared-file hazard.** Extract the file paths from each parallel task's text. If two `[P]` tasks in the batch reference the **same file** (common with TDD pairs where one writes a test the other also edits, or Pint vs PHPStan on the same source), they will race on the shared `PHASE_BRANCH`: one agent self-merges from the main worktree while the other correctly stops, often leaving a stray working-tree edit you must reconcile by hand. When you detect overlap, instruct the parallel agent in the prompt to: (a) run the overlapping tasks in **isolated worktrees**, (b) keep edits minimal/non-overlapping, and (c) **merge them back into `PHASE_BRANCH` sequentially and reconcile** rather than letting both self-merge from the shared checkout.

Delegate to a `task-runner-parallel` agent. The integration target is **`PHASE_BRANCH`**, NOT the feature branch:
```
Agent(
  subagent_type: "task-runner-parallel",
  prompt: "{TASK_ID1} {TASK_ID2} {TASK_ID3} --scope=phase --defer-checks\n\n{context block: cwd, current_branch, PHASE_BRANCH, task_branch_prefix, AUTO_MODE, MCP tools, per-task SCOPE files, and the shared-file reconciliation note if overlap detected. KEY RULES: each task's ephemeral worktree branch is {task_branch_prefix}{TASK_ID} off PHASE_BRANCH HEAD; commit feat({TASK_ID}): ...; MERGE BACK INTO PHASE_BRANCH (--no-ff), NEVER into the feature branch and NEVER into development; checks are deferred (--defer-checks) — do NOT run Pint/PHPStan/Tests; serialize the merge-backs into PHASE_BRANCH.}"
)
```

Wait for the batch to complete.

**After the agent returns — mandatory verification and cleanup:**

First, verify git is still healthy: `git config --list > /dev/null`. If this fails, **STOP** and report `.git/config` corruption to the user before doing anything else.

For each task in the batch, in order:

1. **Check for stray changes to out-of-scope files:**
   ```
   git status --short
   ```
   Ignore untracked agent scratch paths — lines containing `.claude/worktrees/` or `.claude/agent-memory/` (these are agent working dirs, never project scope; leave them untouched). For any tracked file (lines `M` or `A`) that is **not** listed in the task's "Related files" — restore it immediately and log a warning:
   ```
   git checkout HEAD -- <out-of-scope-file>
   ```
   Then restore any remaining uncommitted changes to in-scope files as well (agents should have committed everything).

2. **Verify each task's commit landed on `PHASE_BRANCH`** (do NOT merge into the feature branch yet — that happens once at Step 7.5):
   ```
   git checkout {PHASE_BRANCH}   # ensure we are on the phase branch
   git log {current_branch}..{PHASE_BRANCH} --oneline   # must contain a feat({TASK_ID}): ... commit for each task
   ```
   For each parallel task, confirm a `feat({TASK_ID})` commit is present on `PHASE_BRANCH` (the agent's worktree branch `{task_branch_prefix}{TASK_ID}` should already have been merged back into `PHASE_BRANCH`).
   If a worktree branch exists but was **not merged back** into `PHASE_BRANCH` — merge it now (NOT into the feature branch):
   ```
   git branch | grep {TASK_ID}   # find the exact ephemeral branch name (agents use varied naming)
   git merge {exact-branch} --no-ff -m "feat({TASK_ID}): merge into {PHASE_BRANCH}"
   ```
   If **no branch and no commit** matches `{TASK_ID}` AND the task was supposed to create a new file — check if that file exists; if it exists uncommitted, commit it onto `PHASE_BRANCH`. If neither commit nor file exists, mark as `✗ INCOMPLETE`.

3. **Do NOT mark `[x]` yet.** Tasks are marked complete in tasks.md only after the phase CHECKS pass and the phase branch is merged (Step 7.5). This keeps a failed CHECKS from leaving tasks falsely marked done.

Print the result:
```
  ✓ Parallel batch complete: {N_ok}/{N_total} successful
```

If any tasks failed:
- Print the error list with details
- **STOP**: do not proceed to sequential tasks without user confirmation
  > "Parallel batch finished with errors. Continue with sequential tasks?"

### Step 7: Sequential tasks (tasks without [P])

If `sequential_tasks` is not empty:

```
═══════════════════════════════════════════════════
  [2/2] Sequential tasks: {TASK_ID list}
═══════════════════════════════════════════════════
```

For each task in **tasks.md order**:

1. Print: `  ▶ Running {TASK_ID}...`
2. Delegate to a `task-runner` agent with **full context**:
   ```
   Agent(
     subagent_type: "task-runner",
     prompt: """
     Execute task {TASK_ID} --scope=phase --defer-checks --auto from {$TASKS_PATH}.

     Task (full text from tasks.md): {full task line}

     Context:
     - Working directory: {cwd}
     - Current feature branch: {current_branch}
     - PHASE_BRANCH: {PHASE_BRANCH} (already created and checked out by phase-runner)
     - All project commands (Docker, tests, linting, artisan make:*) are defined in {cwd}/.claude-project.json under "commands.*". Read that file first — do NOT write docker compose commands by hand.
     - Workflow (PHASE MODE): do NOT create a branch. Assert you are on {PHASE_BRANCH} → implement → commit feat({TASK_ID}): ... ONTO {PHASE_BRANCH}. Do NOT merge into the feature branch (the phase branch is merged ONCE by phase-runner after all tasks). Do NOT mark [x] (phase-runner does that after the phase merge).
     - BRANCH (do not improvise): work directly on the already-checked-out {PHASE_BRANCH}. Do NOT create a per-task branch. Never merge into {current_branch} or development.
     - CHECKS DEFERRED (--defer-checks): do NOT run Pint / PHPStan / Tests. They run once for the whole phase at the phase CHECKS step. Just implement + commit.
     - Related files (SCOPE): {list of all backend/ and tests/ paths extracted from task text}. Touch ONLY these files. If something outside scope looks broken, note it and move on — do not fix it.
     - AUTO_MODE=true: do NOT ask for commit confirmation or review confirmation — proceed automatically.
     - MCP TOOLS: prefer Laravel Boost MCP tools over manual file reading — use mcp__laravel-boost__database-schema instead of reading migrations, mcp__laravel-boost__last-error + mcp__laravel-boost__read-log-entries before any code fix when tests fail, mcp__laravel-boost__application-info instead of reading config files
     - LANGUAGE: all PHPDoc blocks and inline code comments must be written in English
     - WAIT FOR COMPLETION: do NOT return early. The task is complete when you have implemented the change, applied @created-by {TASK_ID} tags, and committed feat({TASK_ID}): ... onto {PHASE_BRANCH}.
     """
   )
   ```
3. Wait for completion
4. **After the agent returns — mandatory verification (target = `PHASE_BRANCH`, NOT the feature branch):**
   a. First verify git health: `git config --list > /dev/null`. If this fails, **STOP** and report `.git/config` corruption.
   b. Ensure we are on the phase branch: `git checkout {PHASE_BRANCH}` (the sequential agent worked directly on it).
   c. `git log --oneline {current_branch}..{PHASE_BRANCH}` — there **must** be a new `feat({TASK_ID})` commit for this task on `PHASE_BRANCH`. If this task's commit is absent, the agent created no commit — task is INCOMPLETE.
   d. Run `git status --short` — check for stray changes. For any modified file NOT in the task's related-files list, restore it: `git checkout HEAD -- <file>` and log a warning. If an in-scope change was left uncommitted, commit it onto `PHASE_BRANCH` as `feat({TASK_ID}): ...`.
   e. **Do NOT merge into the feature branch and do NOT mark `[x]`** — both happen once at Step 7.5 after CHECKS pass.
   f. If step (c) shows no commit for `{TASK_ID}` → mark task as `✗ INCOMPLETE` and **STOP**: report to the user and ask how to proceed.
5. On any other error → **STOP** (do not run the next task without user confirmation)

### Step 7.5: Phase CHECKS + MERGE (ONCE per phase)

After **all** the phase's tasks are committed on `PHASE_BRANCH`, run the quality gates and
the merge exactly once.

1. **CHECKS** — run Pint + PHPStan + Tests once for the whole phase:
   ```
   Skill: task-finish "{N} --scope=phase --phase-action=CHECKS --auto"
   ```
   This runs `commands.pint` (auto-fix → commit `style(phase-{N}): pint` if it changed files), then `commands.phpstan` on changed files only, then `commands.test`.
   - On any failure (unfixable Pint violations, PHPStan errors in changed files, or failing tests) the skill **STOPs** and leaves `PHASE_BRANCH` **unmerged**. When this happens → **STOP**, surface the failure to the user, and do **not** merge or mark any task `[x]`.
   - **Baseline-red is not a regression** (see Rules): if a failing test was already red on `{current_branch}` before the phase, it is not this phase's regression — note it as pre-existing rather than blocking the merge or weakening the assertion.

2. **MERGE** — merge the phase branch into the feature branch once:
   ```
   Skill: task-finish "{N} --scope=phase --phase-action=MERGE --auto"
   ```
   This does `git checkout {current_branch}; git merge --no-ff {PHASE_BRANCH}`. **Never** into development. On conflict the skill **STOPs** — surface it and do not mark `[x]`.

3. **Mark tasks complete** — only **after** a successful merge, replace `- [ ] {TASK_ID}` →
   `- [x] {TASK_ID}` in `$TASKS_PATH` for **every** task run in this phase (parallel and
   sequential). Manual/`⊘ MANUAL` tasks (Step 4.5) stay `[ ]`.

### Step 8: Final report

Print the task summary table:

```
═══════════════════════════════════════════════════
  Phase {N} complete   →   branch {PHASE_BRANCH}
═══════════════════════════════════════════════════
  ✓ T025  — done        (parallel)   1m 30s   tokens: 45 210
  ✓ T026  — skipped     (already [x])
  ✓ T027  — done        (sequential) 8m 12s   tokens: 98 440
  ✗ T029  — INCOMPLETE: no commit found
  ───────────────────────────────────────────────
  Phase checks (ONCE):   Pint ✓   PHPStan ✓ (changed files)   Tests ✓
  Phase merge (ONCE):    {PHASE_BRANCH} → {current_branch} (--no-ff)
═══════════════════════════════════════════════════
  Total: {N_ok}/{N_total} completed   Wall time: {total_wall_time}
═══════════════════════════════════════════════════
```

**How to populate each row:**
- **timing** — parse `duration_ms` from the agent result's `<usage>` block; format as `Xm Ys`.
- **tokens** — parse `subagent_tokens` from the agent result's `<usage>` block.
- **Phase checks line** — Pint / PHPStan / Tests are reported **ONCE** for the whole phase (not per task), taken from the `task-finish --phase-action=CHECKS` output at Step 7.5. Per-task rows no longer carry per-task check marks (checks were deferred).
- **Phase merge line** — the single `--no-ff` merge from Step 7.5.
- **skipped tasks** — show only task ID and "skipped (already [x])"; no timing or tokens.
- **Wall time** — sum of all `duration_ms` values (parallel tasks count once, not summed).

Then print the orchestrator-level tools report:

```
═══════════════════════════════════════════════════
  Orchestrator Tools
═══════════════════════════════════════════════════
  Tool calls by phase-runner itself:
    Glob:              {N} call(s)
    Read:              {N} call(s)
    Grep:              {N} call(s)
    Edit:              {N} call(s)
    Bash:              {N} call(s)
    Agent:             {N} call(s)
    AskUserQuestion:   {N} call(s)

  Subagent tokens (from <usage> blocks):
    {TASK_ID}:  {subagent_tokens}
    ...
    Total:      {sum}
═══════════════════════════════════════════════════
```

**How to collect this data:**
- Count every tool call made by phase-runner itself during Steps 1–7, grouped by tool name.
- Subagent tokens: read the `subagent_tokens:` value from each agent result's `<usage>` block. Sum them all.
- Do NOT attempt to report token counts for the phase-runner conversation itself — those are not accessible.

After printing the final report, optionally send a notification. **Note:** the `curl` to `ntfy.sh` is an external-service call and is routinely **blocked by the auto-mode permission classifier** — that denial is expected and is NOT a failure of the run. Attempt it once; if it is denied, silently skip it and do not retry or treat it as an error. The report above is the real deliverable.
```
Bash("curl -s -o /dev/null -d \"Phase {N} complete: {N_ok}/{N_total}\" https://ntfy.sh/claude-shodxpg-p1 2>/dev/null || true")
```

---

## Rules (NON-NEGOTIABLE)

### Branch-per-Phase model (the core invariant)
- **ONE `PHASE_BRANCH` (`{phase_branch_prefix}{N}`) per phase**, created ONCE (Step 5.6) from the feature branch.
- **Every** task in the phase is committed onto `PHASE_BRANCH` (one commit per task — `feat({TASK_ID}): ...`). `[P]` tasks use isolated worktrees branched off `PHASE_BRANCH` HEAD and are **fast-merged back into `PHASE_BRANCH` (serialized)** — NOT into the feature branch.
- **Checks run ONCE per phase** (Step 7.5): Pint + PHPStan(changed files) + Tests, deferred from each task via `--defer-checks`.
- **The phase branch merges into the feature branch exactly ONCE** (Step 7.5, `--no-ff`), only after CHECKS pass. **NEVER** into development. **PROHIBITED: `--squash`.**
- Tasks are marked `[x]` in tasks.md **only after** the phase merge succeeds.

### Execution order
- Walk tasks in **tasks.md order**; consecutive `[P]` tasks form one parallel batch
- Sequential tasks that appear before a parallel group run first; those after run after
- **Never mix** — do not run sequential tasks in parallel
- Example: T009 (seq) → [T010, T011] (parallel) → T012 (seq) — all committing onto `PHASE_BRANCH`

### Delegation
- phase-runner **does NOT implement tasks** — it only orchestrates agent runs
- Phase branch lifecycle (CREATE / CHECKS / MERGE) → `task-finish --scope=phase` via the **Skill tool**
- Parallel tasks → `task-runner-parallel` agent (one call with all IDs, `--scope=phase --defer-checks`)
- Sequential tasks → `task-runner` agent (one call per task, `--scope=phase --defer-checks`)
- **Do NOT use** the Skill tool for task-runner-parallel/task-runner — use only the Agent tool
- **Always use `$TASKS_PATH`** (found via Glob) in agent prompts — never hardcode `specs/001-aps-payment-link/tasks.md`
- **Always pass `PHASE_BRANCH`** in agent prompts, and **always extract related files** from the task text (pattern `backend/...` and `tests/...`) as an explicit list

### Verifying task completion (applies to BOTH parallel and sequential tasks)
After every agent returns, confirm the task landed on `PHASE_BRANCH` (do NOT merge into the feature branch here):
1. `git checkout {PHASE_BRANCH}` — the integration target for the whole phase.
2. `git log --oneline {feature_branch}..{PHASE_BRANCH}` — must contain a `feat({TASK_ID})` commit for this task. Absent = task INCOMPLETE.
3. `git status --short` — no tracked uncommitted files (ignore untracked agent scratch: `.claude/worktrees/`, `.claude/agent-memory/`). Restore any stray out-of-scope TRACKED changes with `git checkout HEAD -- <file>`; commit any in-scope leftover onto `PHASE_BRANCH`.
4. For `[P]` tasks: if the worktree branch was not merged back into `PHASE_BRANCH`, merge it now into `PHASE_BRANCH` (NOT the feature branch).
5. If step 2 shows no commit for `{TASK_ID}` → mark task `✗ INCOMPLETE`, **STOP**, report to user.

### Stopping on errors
- Error or incomplete result in parallel batch → **STOP**, ask user before proceeding
- Error or incomplete result in sequential task → **STOP**, do not run next task automatically
- Phase CHECKS failure (Step 7.5) → **STOP**, leave `PHASE_BRANCH` unmerged, do not mark any task `[x]`
- Exception: task already `[x]` — not an error, skip silently

### Baseline-red is not a regression
- A failing test/assertion that is **already red on `{current_branch}` before the task runs** is NOT that task's regression. If an agent reports a red test, have it confirm (e.g. `git stash` or check the baseline) whether the failure pre-exists. If it does, note it as pre-existing and attribute it to the task that is supposed to fix it (per tasks.md dependencies) — do not block the current task or weaken the assertion to force green. (Example from a past run: a TDD query-count assertion was red by design until the unification task turned it green; it was a false "N+1" alarm, not a regression.)

### Language
- All user-facing communication — **English**
