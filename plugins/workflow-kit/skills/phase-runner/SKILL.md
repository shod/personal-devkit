---
name: phase-runner
description: >-
  Phase orchestrator from tasks.md: runs every task of a phase on ONE phase
  branch, with ONE checks run and ONE merge. By default all tasks — including
  [P]-marked ones — run SEQUENTIALLY on the phase branch via task-runner;
  parallel worktree execution is opt-in via the explicit --parallel flag.
  Use /phase-runner 4 or /phase-runner "Phase 4" for full execution of all
  phase tasks. Accepts several phases (/phase-runner 4 5 6) — they run
  sequentially without a confirmation prompt. Indispensable when you need to
  run an entire phase with one command without manually parsing tasks.
argument-hint: "<phase-number-or-name> [more-phases...] [--parallel] [--auto|--yes|--no-confirm]"
allowed-tools: Agent Read Grep Glob Skill AskUserQuestion Edit Bash PowerShell TodoWrite
model: sonnet
metadata:
  author: speckit
  version: "1.4"
  category: task-orchestration
---

# Phase Runner — Task Phase Orchestrator

Reads tasks.md, determines which tasks belong to the requested phase, and runs the whole
phase on **ONE phase branch** (`{phase_branch_prefix}{N}-{feature-slug}`, e.g.
`phase/3-007-bookings-export-fields`):
- Create the phase branch **once** (from the feature branch).
- Run all phase tasks ON it — one commit per task (traceability preserved):
  - **By default (no `--parallel`): every task runs SEQUENTIALLY** directly on the phase
    branch via `task-runner` — no worktrees, no merge-back. A `[P]` marker in tasks.md is
    read as "this task *could* be parallelised", not as an instruction to do so.
  - **Only with the explicit `--parallel` flag**: `[P]`-marked tasks are batched to
    `task-runner-parallel` (isolated worktrees implement and commit concurrently;
    `task-runner-parallel` itself then merges each worktree branch back into the phase
    branch **sequentially, one at a time** — a single writer by construction, not a lock).
- Run **Pint + PHPStan + Tests ONCE** for the whole phase (CHECKS), then **ONE `--no-ff`
  merge** of the phase branch into the feature branch.

> **Why sequential by default.** The value of phase-runner is the *batching* — one branch,
> one CHECKS run, one merge — which is orthogonal to parallelism. In practice worktree
> parallelism bought little wall-time (tasks are small; worktree setup on Windows and
> `RefreshDatabase` test runs dominate) while adding a durable class of failures:
> merge-back races, false "success" on empty or wrong commits, and shared-file conflicts
> that only surface at merge time. Parallelism is therefore **opt-in**.

This replaces the old branch-per-task model (one branch + one merge + one full check run
per task) — collapsing N×(branch+merge+checks) into 1×(branch+merge) + 1×(checks) per phase.
Checks are deferred to phase level via `--defer-checks` on each task and run via
`task-git --scope=phase --phase-action=CHECKS`.

## Required argument

`$ARGUMENTS` **MUST** contain at least one phase number or name.

Accepted formats:
- `4`
- `Phase 4`
- `phase 4`
- **Several phases:** `4 5 6`, `Phase 4, Phase 5`, `3-5` (inclusive range)

Optional flags:
- `--auto`, `--yes`, `-y`, `--no-confirm` — skip the confirmation prompt.
- **`--parallel`** — enable parallel execution of `[P]`-marked tasks via
  `task-runner-parallel` (isolated worktrees + sequential merge-back). **Without this flag
  every task runs sequentially on the phase branch**, `[P]` marker or not.

If `$ARGUMENTS` contains no phase number — **STOP** and ask the user:
> Specify the phase number: `/phase-runner 4`

---

## Algorithm

### Step 1: Parse the argument

1. Strip the flags `--auto` / `--yes` / `-y` / `--no-confirm` from `$ARGUMENTS`; if any was present set **`AUTO_CONFIRM = true`**.
1a. Strip `--parallel` from `$ARGUMENTS`; set **`PARALLEL_MODE = true`** if it was present, otherwise **`PARALLEL_MODE = false`**. This is the ONLY way parallel execution is enabled — a `[P]` marker in tasks.md never enables it on its own.
2. Extract **all** phase numbers from the remainder, in the order given: every `\d+`, plus ranges `N-M` expanded to `N, N+1, …, M`. Ignore a trailing spec identifier (Step 2a) when it is a known spec name/number rather than a phase.
3. Save the ordered, de-duplicated list as **`$PHASES`**.
4. If `$PHASES` is empty — stop and ask the user to specify.
5. **If `$PHASES` contains more than one phase → set `AUTO_CONFIRM = true`.** Running several phases is itself an explicit instruction to proceed without asking.

### Step 1.5: Multi-phase loop

If `$PHASES` has more than one entry, run Steps 2–8 **for each phase in order**, fully completing one phase (CHECKS + MERGE + marking `[x]`) before starting the next. Resolve `$TASKS_PATH` once (Step 2) and reuse it for all phases. Each phase gets its own `PHASE_BRANCH`.

Stop the whole run (do not start the remaining phases) if a phase ends with an INCOMPLETE task, a CHECKS failure, or a merge conflict — report which phases completed and which were not attempted. A phase that is already fully `[x]` is skipped and does not stop the loop.

After the last phase, print one combined final report (Step 8) with a per-phase section.

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
- **has_p_marker**: `[P]` marker present in the task line
- **is_parallel**: `has_p_marker AND PARALLEL_MODE` — i.e. **false for every task unless
  `--parallel` was passed**. When `PARALLEL_MODE = false`, `[P]` is informational only and
  the task joins the sequential list.
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

Build the execution schedule by walking tasks in **tasks.md order**.

**If `PARALLEL_MODE = false` (the default)** — there are no batches. Every pending task is
sequential and commits directly onto `PHASE_BRANCH`, in tasks.md order. Manual tasks
(Step 4.5) are listed separately as `⊘ MANUAL`. Show:

> In the plan templates below, `{PHASE_BRANCH}` is `{phase_branch_prefix}{N}-{feature-slug}`
> (Step 5.5). The slug comes from `$TASKS_PATH`, already resolved at Step 2, so print the
> **real branch name** here — never a placeholder or the bare `{phase_branch_prefix}{N}`.

```
═══════════════════════════════════════════════════
  Phase Runner: Phase {N}   →   branch {PHASE_BRANCH}
═══════════════════════════════════════════════════
  Queue: {$PHASES joined}  (phase {i} of {total})     ← only when >1 phase
  Mode: SEQUENTIAL (default — pass --parallel to enable [P] batching)
  Model: 1 phase branch → {pending} tasks → 1 CHECKS → 1 merge
  Total tasks: {total}  |  Skipped (done): {done}
  To run: {pending}

  ▶ Sequential onto {PHASE_BRANCH}:
    {T009} — {description}
    {T010} — {description}   [P in tasks.md — running sequentially]
    {T011} — {description}   [P in tasks.md — running sequentially]
    {T012} — {description}

  Execution order (tasks.md order, one task at a time):
    0. Create branch {PHASE_BRANCH}
    1. {T009} — sequential onto PHASE_BRANCH
    2. {T010} — sequential onto PHASE_BRANCH
    3. {T011} — sequential onto PHASE_BRANCH
    4. {T012} — sequential onto PHASE_BRANCH
    5. CHECKS: Pint + PHPStan + Tests (ONCE)
    6. Merge {PHASE_BRANCH} → {current_branch} (--no-ff, ONCE)
═══════════════════════════════════════════════════
Start? (yes/no)          ← omit this line entirely when AUTO_CONFIRM = true
```

Tasks carrying a `[P]` marker **must** be annotated `[P in tasks.md — running sequentially]`
so the user can see that parallelism was available and was not used.

**If `PARALLEL_MODE = true`** — group consecutive `[P]` tasks into a single parallel batch.
Sequential tasks that appear before, between, or after a parallel group run in their natural
order. Example:

```
T009 (sequential) → [T010, T011] (parallel batch) → T012 (sequential)
```

```
═══════════════════════════════════════════════════
  Phase Runner: Phase {N}   →   branch {PHASE_BRANCH}
═══════════════════════════════════════════════════
  Queue: {$PHASES joined}  (phase {i} of {total})     ← only when >1 phase
  Mode: PARALLEL (--parallel) — [P] tasks run in isolated worktrees
  Model: 1 phase branch → {pending} tasks → 1 CHECKS → 1 merge
  Total tasks: {total}  |  Skipped (done): {done}
  To run: {pending}

  ▶ Parallel [P]:
    {parallel_tasks list with descriptions}

  ▶ Sequential:
    {sequential_tasks list with descriptions}

  Execution order (tasks.md order, [P] groups fire simultaneously):
    0. Create branch {PHASE_BRANCH}
    1. {T009} — sequential       (commit onto phase branch)
    2. {T010, T011} — parallel batch (worktrees → merged back into phase branch)
    3. {T012} — sequential       (commit onto phase branch)
    4. CHECKS: Pint + PHPStan + Tests (ONCE)
    5. Merge {PHASE_BRANCH} → {current_branch} (--no-ff, ONCE)
═══════════════════════════════════════════════════
Start? (yes/no)          ← omit this line entirely when AUTO_CONFIRM = true
```

If the phase has **only parallel** or **only sequential** tasks — show the appropriate simplified plan.

**Confirmation:**
- If **`AUTO_CONFIRM = true`** (several phases were requested, or `--auto` / `--yes` / `-y` / `--no-confirm` was passed) → **do NOT call AskUserQuestion**. Print the plan followed by `Auto-confirmed ({reason: multiple phases | --auto flag}) — starting.` and proceed straight to Step 5.5.
- Otherwise (a single phase, no flag) → ask for confirmation via **AskUserQuestion** before starting.

`AUTO_CONFIRM` suppresses only this start-of-phase prompt. It never suppresses the **STOP** points (errors, INCOMPLETE tasks, failed CHECKS, merge conflicts, ambiguous spec at Step 2d) — those still halt and ask.

### Step 5.5: Pre-flight git health + resolve the feature branch & task-branch naming

Before starting any tasks:

1. **Git health:**
   ```
   git config --list > /dev/null
   ```
   If this fails with `fatal: bad config line`, `.git/config` is corrupted. **STOP** immediately and report — do not attempt any task.

2. **Resolve `{current_branch}` from git, NOT from config.** Run `git branch --show-current` and use that as `{current_branch}`. ⚠️ Do **not** trust the `feature_branch` key in `.claude-project.json` — it is frequently STALE (e.g. it may name an old feature branch while the real working branch differs). The branch you are checked out on is the source of truth. Pass this resolved branch to every agent.
3. **Resolve the phase-branch name and the (ephemeral) task-branch prefix.**
   - **Derive `FEATURE_SLUG` from `$TASKS_PATH`** — the basename of the spec directory holding
     that `tasks.md` (`specs/007-bookings-export-fields/tasks.md` → `007-bookings-export-fields`).
     Normalize it for a git ref: lowercase, every character outside `[a-z0-9._-]` → `-`,
     collapse repeats, trim leading/trailing `-`. Never take the slug from the git branch name
     or from `.claude-project.json` — `$TASKS_PATH` (resolved in Step 2) is the source of truth,
     so the branch name always names the spec whose tasks are actually being run.
   - Read `phase_branch_prefix` from `.claude-project.json` `paths` (e.g. `phase/`). Set
     **`PHASE_BRANCH = {phase_branch_prefix}{N}-{FEATURE_SLUG}`** (e.g.
     `phase/3-007-bookings-export-fields`). This is the ONE branch that holds the whole phase.
     Only the prefix segment is nested; the `{N}-{FEATURE_SLUG}` part stays flat, which avoids
     the nested-ref problem (git cannot create `{current_branch}/...` under an existing
     `{current_branch}` ref) while making the name **unique per feature** — a `phase/3` from
     another feature can no longer collide with this run.
   - Read `task_branch_prefix` (e.g. `task/`). It is needed **only when `PARALLEL_MODE = true`**, for `[P]` **worktree** branches: parallel tasks branch off `PHASE_BRANCH` HEAD as `{task_branch_prefix}{TASK_ID}` and merge **back into `PHASE_BRANCH`** (not the feature branch). In the default sequential mode no task branches are created at all.
   - Pass `PHASE_BRANCH` explicitly to every agent and to **every `task-git --scope=phase` call
     (via `--phase-branch={PHASE_BRANCH}`)**, so the name is computed once here and never
     re-derived downstream (and `task_branch_prefix` too, in parallel mode).
4. **Resolve `{plugin_root}`** — the `workflow-kit` plugin directory, i.e. the parent of the
   directory holding this SKILL.md's `skills/` tree (`{plugin_root}/skills/phase-runner/SKILL.md`
   is this file). Its `{plugin_root}/scripts/` holds `verify-task.{sh,ps1}` and
   `merge-back.{sh,ps1}`, used at Steps 6 and 7. Check once that
   `{plugin_root}/scripts/verify-task.sh` exists; if it does not, note it and use the manual
   fallback described in Rules → "Verifying task completion" for the whole run.

### Step 5.55: Existing-branch check (`{N}-{FEATURE_SLUG}` is unique per feature)

Because `PHASE_BRANCH` carries the spec slug, a branch under that exact name can only be
**this feature's phase {N}** — a previous, interrupted run of this very phase. There is no
cross-feature collision to resolve anymore. **Before** Step 5.6:

1. `git rev-parse --verify --quiet {PHASE_BRANCH}` — if it does not exist, nothing to do;
   go to Step 5.6.
2. If it exists, it is **ours**: do **not** rename and do **not** delete it. Report that the
   existing phase branch is being reused and let Step 5.6 check it out rather than create it.
   Before continuing, confirm it is not behind the feature branch:
   `git log {PHASE_BRANCH}..{current_branch} --oneline` — if non-empty, merge the feature
   branch into it (`git merge --no-ff {current_branch}`) so the phase builds on current work;
   on conflict → **STOP** and hand it to the user.
3. **Legacy flat branch (migration).** Older versions of this skill named the branch
   `{phase_branch_prefix}{N}` with no slug. Check `git rev-parse --verify --quiet
   {phase_branch_prefix}{N}`: if such a branch exists, it is **not** used by this run. Leave it
   untouched — never rename, never delete — and mention it once:
   > ℹ️ Legacy phase branch `{phase_branch_prefix}{N}` exists (old naming scheme). This run
   > uses `{PHASE_BRANCH}`. If the legacy branch holds unmerged work for this phase, merge it
   > yourself before continuing.
   Only when its commits reference task IDs from **this** `$TASKS_PATH` and are unmerged
   (`git log {current_branch}..{phase_branch_prefix}{N} --oneline` non-empty) → **STOP** and
   ask the user how to proceed, rather than silently starting a second branch for the same
   phase.

### Step 5.6: Create the phase branch (ONCE)

Before running any task, create the phase branch from the feature branch. Always pass the
resolved name — `task-git` must not re-derive it:

```
Skill: task-git "{N} --scope=phase --phase-action=CREATE --phase-branch={PHASE_BRANCH} --auto"
```

Then verify: `git branch --show-current` **MUST** equal `PHASE_BRANCH`. If not → **STOP**
and report (do not run any task off the wrong branch). From here on, `PHASE_BRANCH` — not
the feature branch — is the integration target for every task in this phase.

### Step 6: Parallel batch — ONLY when `PARALLEL_MODE = true`

**If `PARALLEL_MODE = false` (the default) — SKIP this entire step.** `parallel_tasks` is
empty by construction (Step 3), `task-runner-parallel` is not invoked, no worktree is
created and no merge-back happens. Go straight to Step 7, which runs every pending task.

If `PARALLEL_MODE = true` and `parallel_tasks` is not empty:

```
═══════════════════════════════════════════════════
  [1/2] Parallel batch: {TASK_ID list}
═══════════════════════════════════════════════════
```

**Before delegating — check for a shared-file hazard.** Extract the file paths from each parallel task's text. If two `[P]` tasks in the batch reference the **same file** (common with TDD pairs where one writes a test the other also edits, or Pint vs PHPStan on the same source), the concurrent-writer race on `PHASE_BRANCH` itself cannot happen anymore — workers never merge into `PHASE_BRANCH` (`task-runner-parallel` does that sequentially, see Merge-back serialization in that agent's definition) — but the two workers' edits can still **content-conflict** at that later sequential-merge step, since both touched the same file independently in isolated worktrees. When you detect overlap, instruct the parallel agent in the prompt to (a) run the overlapping tasks in **isolated worktrees** (already mandatory) and (b) keep edits minimal/non-overlapping where possible, so the sequential merge-back is more likely to be conflict-free; a real conflict is still possible and will surface as a **STOP** during `task-runner-parallel`'s merge-back step, to be resolved manually.

Delegate to a `task-runner-parallel` agent. The integration target is **`PHASE_BRANCH`**, NOT the feature branch:
```
Agent(
  subagent_type: "task-runner-parallel",
  prompt: "{TASK_ID1} {TASK_ID2} {TASK_ID3} --scope=phase --defer-checks\n\n{context block: cwd, current_branch, PHASE_BRANCH, task_branch_prefix, AUTO_MODE, MCP tools, per-task SCOPE files, and the shared-file reconciliation note if overlap detected. KEY RULES: each task's ephemeral worktree branch is {task_branch_prefix}{TASK_ID} off PHASE_BRANCH HEAD; workers commit feat({TASK_ID}): ... on their own worktree branch ONLY — workers must NOT merge into PHASE_BRANCH, the feature branch, or development; task-runner-parallel itself merges every worker's branch back into PHASE_BRANCH sequentially (--no-ff), one at a time, immediately after the batch returns; checks are deferred (--defer-checks) — do NOT run Pint/PHPStan/Tests.}"
)
```

Wait for the batch to complete.

> ⚠️ **When the batch's task-notification arrives, its one-line `<summary>` is a UI label
> only** — never read that line and stop there. Open the agent's **full result body**. If
> the result body embeds raw command output (test runner output, PHPStan/Pint output,
> etc.), that raw output — not the agent's own prose wrapped around it — is what matters.
> A worker claiming "implemented and committed" is not evidence the commit is real or that
> any check it happened to run actually passed; the mandatory verification below (script
> exit code, and later the phase-level CHECKS raw output) is what decides, never the
> agent's phrasing. See "Never trust agent prose for pass/fail" in Rules.

**After the agent returns — mandatory verification and cleanup:**

First, verify git is still healthy: `git config --list > /dev/null`. If this fails, **STOP** and report `.git/config` corruption to the user before doing anything else.

For each task in the batch, in order:

1. **Check for stray changes to out-of-scope files:**
   ```
   git status --short
   ```
   **NEVER restore these paths** — they are excluded from the restore, always:
   - `.claude/worktrees/` and `.claude/agent-memory/` (agent working dirs, never project scope — leave untouched)
   - **`$TASKS_PATH` (`specs/*/tasks.md`)** — restoring it **destroys completion marks**. If it has uncommitted changes here, do **not** `git checkout` it: **flag it** to the user (`⚠ tasks.md has uncommitted changes — either an agent violated its scope, or a previous phase left its `[x]` marks uncommitted`). Inspect `git diff -- {$TASKS_PATH}`; if the diff is a prior phase's `[x]` marks, commit it (`chore: commit pending tasks.md marks`) rather than discarding it. Never silently discard.

   For any other tracked file (lines `M` or `A`) that is **not** listed in the task's "Related files" — restore it immediately and log a warning:
   ```
   git checkout HEAD -- <out-of-scope-file>
   ```
   Then restore any remaining uncommitted changes to in-scope files as well (agents should have committed everything).

2. **Verify each task landed on `PHASE_BRANCH`** — run the verification **script** and read
   its exit code. Do NOT interpret git state yourself, and do NOT merge into the feature
   branch yet (that happens once at Step 7.5):
   ```
   git checkout {PHASE_BRANCH}
   bash {plugin_root}/scripts/verify-task.sh {current_branch} {PHASE_BRANCH} {TASK_ID} {SCOPE_GLOBS...}
   # Windows / PowerShell:
   {plugin_root}/scripts/verify-task.ps1 {current_branch} {PHASE_BRANCH} {TASK_ID} {SCOPE_GLOBS...}
   ```
   `{SCOPE_GLOBS...}` = the task's related-files list extracted from the task text
   (see "Related files (SCOPE)"). **Exit 0 = task verified. Any non-zero exit = `✗ INCOMPLETE`** —
   print the script's stderr verbatim, **STOP**, and report to the user. See
   "Verifying task completion" in Rules for the exact criterion and the manual fallback.

   By design, `task-runner-parallel` already performed every merge-back **sequentially**
   (one worker's branch at a time) before returning — workers themselves never touch
   `PHASE_BRANCH`, so this is a verification/safety-net step, not the primary merge point.
   If verification fails **because the worktree branch was never merged back** (the branch
   exists and holds the commit, e.g. `task-runner-parallel` reported an error for it) —
   merge it now with the merge-back **script** (NOT into the feature branch), then re-run
   `verify-task`:
   ```
   git branch --list "*{TASK_ID}*"      # find the exact ephemeral branch name
   bash {plugin_root}/scripts/merge-back.sh {PHASE_BRANCH} {exact-branch} {TASK_ID}
   # Windows: {plugin_root}/scripts/merge-back.ps1 {PHASE_BRANCH} {exact-branch} {TASK_ID}
   ```
   Exit 0 = merged (or already merged). Exit 1 = conflict — the script aborts the merge and
   lists the conflicting files; **STOP** and hand them to the user, do not resolve
   automatically.

   If **no branch and no commit** matches `{TASK_ID}` AND the task was supposed to create a new file — check if that file exists; if it exists uncommitted, commit it onto `PHASE_BRANCH` and re-run `verify-task`. If neither commit nor file exists, mark as `✗ INCOMPLETE`.

3. **Do NOT mark `[x]` yet.** Tasks are marked complete in tasks.md only after the phase CHECKS pass and the phase branch is merged (Step 7.5). This keeps a failed CHECKS from leaving tasks falsely marked done.

Print the result:
```
  ✓ Parallel batch complete: {N_ok}/{N_total} successful
```

If any tasks failed:
- Print the error list with details
- **STOP**: do not proceed to sequential tasks without user confirmation
  > "Parallel batch finished with errors. Continue with sequential tasks?"

### Step 7: Sequential tasks

In the **default mode (`PARALLEL_MODE = false`) this step runs EVERY pending task of the
phase**, `[P]`-marked or not, one at a time, directly on `PHASE_BRANCH`. With
`--parallel` it runs only the tasks left over from the batches in Step 6.

If `sequential_tasks` is not empty:

```
═══════════════════════════════════════════════════
  Sequential tasks: {TASK_ID list}
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
3. Wait for completion.

   > ⚠️ **The task-notification's one-line `<summary>` is a UI label only — never use it to
   > decide pass/fail.** Always open and read the agent's full result body. If that body
   > embeds raw command output, the raw output is the source of truth, not the agent's
   > prose around it. See "Never trust agent prose for pass/fail" in Rules.
4. **After the agent returns — mandatory verification (target = `PHASE_BRANCH`, NOT the feature branch):**
   a. First verify git health: `git config --list > /dev/null`. If this fails, **STOP** and report `.git/config` corruption.
   b. Ensure we are on the phase branch: `git checkout {PHASE_BRANCH}` (the sequential agent worked directly on it).
   c. Run the verification **script** and read its exit code — do NOT interpret git state yourself:
      ```
      bash {plugin_root}/scripts/verify-task.sh {current_branch} {PHASE_BRANCH} {TASK_ID} {SCOPE_GLOBS...}
      # Windows / PowerShell:
      {plugin_root}/scripts/verify-task.ps1 {current_branch} {PHASE_BRANCH} {TASK_ID} {SCOPE_GLOBS...}
      ```
      `{SCOPE_GLOBS...}` = the task's related-files list passed to the agent. **Exit 0 = verified; any non-zero exit = the task is INCOMPLETE.** (See "Verifying task completion" in Rules for the criterion and the manual fallback if the script cannot run.)
   d. Run `git status --short` — check for stray changes. For any modified file NOT in the task's related-files list, restore it: `git checkout HEAD -- <file>` and log a warning — **except** `.claude/worktrees/`, `.claude/agent-memory/` and **`$TASKS_PATH` (`specs/*/tasks.md`)**, which are never restored. Restoring `tasks.md` destroys completion marks: if it has uncommitted changes, **flag it** to the user (an agent violated its scope, or a previous phase left its `[x]` marks uncommitted) and commit those marks instead of discarding them. If an in-scope change was left uncommitted, commit it onto `PHASE_BRANCH` as `feat({TASK_ID}): ...` and re-run step (c).
   e. **Do NOT merge into the feature branch and do NOT mark `[x]`** — both happen once at Step 7.5 after CHECKS pass.
   f. If step (c) exits non-zero → mark task as `✗ INCOMPLETE`, print the script's stderr verbatim, and **STOP**: report to the user and ask how to proceed. An empty commit, a commit that changes nothing, or a commit touching only files outside the task's SCOPE all land here — they are **not** success.
5. On any other error → **STOP** (do not run the next task without user confirmation)

### Step 7.5: Phase CHECKS + MERGE (ONCE per phase)

After **all** the phase's tasks are committed on `PHASE_BRANCH`, run the quality gates and
the merge exactly once.

1. **CHECKS** — run Pint + PHPStan + Tests once for the whole phase:
   ```
   Skill: task-git "{N} --scope=phase --phase-action=CHECKS --phase-branch={PHASE_BRANCH} --auto"
   ```
   This runs `commands.pint` (auto-fix → commit `style(phase-{N}): pint` if it changed files), then `commands.phpstan` on changed files only, then `commands.test`.
   - On any failure (unfixable Pint violations, PHPStan errors in changed files, or failing tests) the skill **STOPs** and leaves `PHASE_BRANCH` **unmerged**. When this happens → **STOP**, surface the failure to the user, and do **not** merge or mark any task `[x]`.
   - **Baseline-red is not a regression** (see Rules): if a failing test was already red on `{current_branch}` before the phase, it is not this phase's regression — note it as pre-existing rather than blocking the merge or weakening the assertion.
   - **The PASS/FAIL verdict for Pint/PHPStan/Tests MUST come from `task-git`'s own direct
     parsing of each command's raw stdout/stderr — never from a subagent's prose summary.**
     `task-git` runs `commands.pint`/`commands.phpstan`/`commands.test` itself (Bash/PowerShell,
     not a delegated agent) and reads the raw output directly, so this step already satisfies
     the rule by construction. If `task-git`'s report to phase-runner ever comes from an agent
     hop instead (e.g. a future refactor delegates CHECKS to a subagent), phase-runner MUST NOT
     accept that agent's "tests passed" / "completed successfully" claim as sufficient — see
     "Never trust agent prose for pass/fail" in Rules.

2. **MERGE** — merge the phase branch into the feature branch once:
   ```
   Skill: task-git "{N} --scope=phase --phase-action=MERGE --phase-branch={PHASE_BRANCH} --auto"
   ```
   This does `git checkout {current_branch}; git merge --no-ff {PHASE_BRANCH}`. **Never** into development. On conflict the skill **STOPs** — surface it and do not mark `[x]`.

3. **Migrations — run them against the dev database (do NOT skip silently).**
   The phase tests run on `RefreshDatabase`, which migrates a **throwaway** schema; the
   developer's dev database is left un-migrated, so a phase that added a migration leaves
   the local app broken until it is applied. Immediately after the merge:
   ```
   git diff --name-only {current_branch}@{1}..{current_branch} -- "*database/migrations/*.php"
   ```
   If that list is **non-empty**, tell the user explicitly (never do it quietly):
   > ⚠️ Phase {N} added {M} migration(s): {file list}
   > The test suite ran them on a throwaway schema only — your **dev database is not
   > migrated**. Running `commands.migrate` (`artisan migrate --force`) now.

   Then run the migrate command from `.claude-project.json` `commands.*` (`commands.migrate`
   if present, otherwise the project's `artisan migrate --force` equivalent) — **do not
   hand-write `docker compose`**. If no such command is defined, or the run fails, do **not**
   treat the phase as broken: report the exact command the user must run themselves and
   carry on to step 4.

4. **Mark tasks complete — and COMMIT the marks** — only **after** a successful merge, replace
   `- [ ] {TASK_ID}` → `- [x] {TASK_ID}` in `$TASKS_PATH` for **every** task run in this phase
   (parallel and sequential). Manual/`⊘ MANUAL` tasks (Step 4.5) stay `[ ]`.

   Then **immediately commit `tasks.md`** on the feature branch, as its own commit:
   ```
   git checkout {current_branch}
   git add {$TASKS_PATH}
   git commit -m "chore(phase-{N}): mark {TASK_ID list} complete"
   ```
   ⚠ **Leaving `tasks.md` uncommitted is a BUG, not a cosmetic omission.** The marks live only
   in the working tree, and this skill's own out-of-scope restore (Steps 6.1 / 7.4d / Rules →
   "Verifying task completion") runs `git checkout HEAD -- <file>` on the next phase — which
   reverts them. Observed in production: Phase 1 marked T001–T004 `[x]` uncommitted, Phase 2's
   cleanup reverted `tasks.md`, and T001–T004 silently went back to `[ ]` while Phase 2's own
   (committed) marks survived — the phase looked unrun. Mark **and** commit in the same step.

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
  tasks.md marks:        {commit_sha} chore(phase-{N}): mark {TASK_ID list} complete
                         {or ✗ NOT COMMITTED — marks will be lost on the next phase}
  Migrations:            {none | M new → dev DB migrated ✓ | M new → RUN MANUALLY: {cmd}}
═══════════════════════════════════════════════════
  Total: {N_ok}/{N_total} completed   Wall time: {total_wall_time}
═══════════════════════════════════════════════════
```

**How to populate each row:**
- **timing** — parse `duration_ms` from the agent result's `<usage>` block; format as `Xm Ys`.
- **tokens** — parse `subagent_tokens` from the agent result's `<usage>` block.
- **Phase checks line** — Pint / PHPStan / Tests are reported **ONCE** for the whole phase (not per task), taken from the `task-git --phase-action=CHECKS` output at Step 7.5. Per-task rows no longer carry per-task check marks (checks were deferred).
- **Phase merge line** — the single `--no-ff` merge from Step 7.5.
- **tasks.md marks line** — the `chore(phase-{N}): mark ... complete` commit from Step 7.5 item 4; take the sha from `git log -1 --format=%h -- {$TASKS_PATH}` on `{current_branch}`. If `git status --short -- {$TASKS_PATH}` is still dirty, report `✗ NOT COMMITTED` here — this is a data-loss condition, not a cosmetic gap, so surface it in the report instead of letting it be discovered a phase later.
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

### Never trust agent prose for pass/fail

> **Why this rule exists.** In production use, a `task-runner` agent whose job was
> literally "run tests and verify no regressions" reported a task-notification summary of
> "completed successfully" while its own result body contained the raw test-runner output
> showing `5 failed, 1206 passed`. phase-runner initially trusted the prose summary and
> reported the phase green; the failure was only caught by a later, independent re-read of
> the raw output — by which point a real product bug (a service silently failing to persist
> a row) had shipped uncaught through an earlier phase. **Do not relax this rule "for
> efficiency" or because an agent's summary looks confident** — a confident wrong summary is
> exactly the failure mode this guards against, and an agent that can misreport once can
> misreport again no matter how its prompt asks it to phrase things.

Applies to **every** step in this skill that gates a merge, a `[x]` mark, or a "phase
complete" report on a test/lint/build/verification outcome — Step 6 (parallel batch),
Step 7 (sequential tasks), Step 7.5 (phase CHECKS), and the final report (Step 8). Concretely:

1. **The pass/fail verdict for any test/lint/build/CHECKS step MUST be established by
   directly parsing the raw stdout/stderr of the command** — grep/match the tool's own
   failure markers (`FAILED`, `✗`, non-zero exit code, "N failed" summary lines, PHPStan
   error counts, etc.) **in the actual captured output**. A subagent's prose claim of
   "passed", "completed successfully", "all green", "no regressions", etc. is **never**
   sufficient evidence on its own, whether it appears in a task-notification `<summary>`
   line or inside the result body's prose. If phase-runner did not itself see and
   pattern-match the raw output (or read a script's exit code — see "Verifying task
   completion"), the gate is **not yet verified**.
2. **The task-notification `<summary>` line is a UI label only.** Always open the full
   result body of every subagent. If the body embeds raw command output, that raw output —
   not the agent's prose wrapped around it — is the source of truth.
3. **A mismatch between an agent's prose and the raw output it embeds is a serious finding
   on its own**, not just a fixed-and-move-on incident: if a `task-runner`/`task-runner-parallel`
   agent's self-reported status ever disagrees with the raw output in its own result, treat
   that agent's self-reporting as unreliable for the rest of the run — re-verify neighboring
   tasks it touched too (re-run "Verifying task completion" on them), don't just fix the one
   contradiction and continue trusting the rest.
4. **Independent re-verification is mandatory, not a nice-to-have.** The dedicated CHECKS
   step (Step 7.5) already runs Pint/PHPStan/Tests directly via `task-git` (Bash/PowerShell,
   not a delegated agent) and reads the raw output itself — this satisfies the rule by
   construction and must stay that way. If a future task ever appears in tasks.md that is
   itself titled "run tests"/"verify no regressions"/similar and gets delegated to
   `task-runner`, treat that task's own self-report as **never sufficient**: the mandatory
   Step 7.5 CHECKS gate (which phase-runner runs and parses independently) is what actually
   decides pass/fail, and it must still run in full even if such a task claims success.

### Branch-per-Phase model (the core invariant)
- **ONE `PHASE_BRANCH` (`{phase_branch_prefix}{N}-{FEATURE_SLUG}`, e.g. `phase/3-007-bookings-export-fields`) per phase**, created ONCE (Step 5.6) from the feature branch. The slug is the spec directory of `$TASKS_PATH` — resolved once at Step 5.5 and passed verbatim to every agent and `task-git` call (`--phase-branch=`); nothing downstream re-derives it.
- **Every** task in the phase is committed onto `PHASE_BRANCH` (one commit per task — `feat({TASK_ID}): ...`). In the default sequential mode the agent commits straight onto `PHASE_BRANCH`. Only under `--parallel` do `[P]` tasks use isolated worktrees branched off `PHASE_BRANCH` HEAD; workers commit there only, and `task-runner-parallel` merges every worktree branch **back into `PHASE_BRANCH` itself, sequentially, one at a time** (never the workers, never concurrently) — NOT into the feature branch.
- **Checks run ONCE per phase** (Step 7.5): Pint + PHPStan(changed files) + Tests, deferred from each task via `--defer-checks`.
- **The phase branch merges into the feature branch exactly ONCE** (Step 7.5, `--no-ff`), only after CHECKS pass. **NEVER** into development. **PROHIBITED: `--squash`.**
- Because the name carries the feature slug, a pre-existing `PHASE_BRANCH` can only be **this** feature's interrupted phase — reuse it (Step 5.55), never rename or delete it. A legacy flat `{phase_branch_prefix}{N}` from the old naming scheme is left untouched and is never built on.
- Tasks are marked `[x]` in tasks.md **only after** the phase merge succeeds — and the mark **MUST be committed in the same step** (`chore(phase-{N}): mark ... complete`); an uncommitted tasks.md is destroyed by the next phase's cleanup.
- If the phase added migrations, the dev database must be migrated (or the exact command surfaced to the user) after the merge — **never silently** (Step 7.5.3).

### Parallelism is OPT-IN
- **Default = fully sequential.** With no `--parallel` flag, every pending task of the phase — including tasks carrying `[P]` — runs one at a time via `task-runner` directly on `PHASE_BRANCH`. **No worktrees, no task branches, no merge-back.**
- A `[P]` marker in tasks.md is **advisory metadata** ("this task has no ordering dependency"), NOT a trigger. It never by itself causes parallel execution.
- `task-runner-parallel` is invoked **only** when `PARALLEL_MODE = true` (the user passed `--parallel`).
- The plan (Step 5) must state the mode (`SEQUENTIAL` / `PARALLEL`) and, in sequential mode, annotate `[P]` tasks as `[P in tasks.md — running sequentially]`.

### Execution order
- Walk tasks in **tasks.md order**
- Default (sequential mode): strict tasks.md order, one task at a time
- `--parallel` only: consecutive `[P]` tasks form one parallel batch; sequential tasks before a parallel group run first, those after run after
- **Never mix** — do not run sequential tasks in parallel
- Example under `--parallel`: T009 (seq) → [T010, T011] (parallel) → T012 (seq) — all committing onto `PHASE_BRANCH`

### Delegation
- phase-runner **does NOT implement tasks** — it only orchestrates agent runs
- Phase branch lifecycle (CREATE / CHECKS / MERGE) → `task-git --scope=phase` via the **Skill tool**
- Parallel tasks (**`--parallel` only**) → `task-runner-parallel` agent (one call with all IDs, `--scope=phase --defer-checks`)
- Sequential tasks (**all tasks by default**) → `task-runner` agent (one call per task, `--scope=phase --defer-checks`)
- Task verification and phase-mode merge-back → the `scripts/verify-task.{sh,ps1}` and `scripts/merge-back.{sh,ps1}` helpers via **Bash/PowerShell**; read the exit code, do not re-derive the verdict from git output
- **Do NOT use** the Skill tool for task-runner-parallel/task-runner — use only the Agent tool
- **Always use `$TASKS_PATH`** (found via Glob) in agent prompts — never hardcode `specs/001-aps-payment-link/tasks.md`
- **Always pass `PHASE_BRANCH`** in agent prompts, and **always extract related files** from the task text (pattern `backend/...` and `tests/...`) as an explicit list

### Verifying task completion (applies to BOTH parallel and sequential tasks)

**A task counts as done only when ALL THREE hold:**
1. A `feat({TASK_ID})` commit is present on `PHASE_BRANCH` (range `{feature_branch}..{PHASE_BRANCH}`), **AND**
2. `git diff --stat {feature_branch}..{PHASE_BRANCH}` for that task is **non-empty** — the commit actually changed files, **AND**
3. At least one changed file matches the task's **SCOPE** (the related-files list extracted from the task text).

"A commit exists" alone is **NOT** sufficient: an empty commit, an `--allow-empty`-style
no-op, or a commit that only touched files nobody asked for all satisfy (1) and still mean
the task was not done. Any of the three failing ⇒ `✗ INCOMPLETE` ⇒ **STOP** and report to
the user.

**Do not evaluate this by hand — run the script and read the exit code:**
```
bash {plugin_root}/scripts/verify-task.sh {feature_branch} {PHASE_BRANCH} {TASK_ID} {SCOPE_GLOBS...}
# Windows / PowerShell:
{plugin_root}/scripts/verify-task.ps1 {feature_branch} {PHASE_BRANCH} {TASK_ID} {SCOPE_GLOBS...}
```
| exit | meaning | action |
|------|---------|--------|
| 0 | all three criteria hold | task verified; continue |
| 1 | verification failed (missing/empty commit, or out of scope) | `✗ INCOMPLETE` → **STOP**, print stderr verbatim, report |
| 2 | usage / repo error (bad branch, not a git repo) | **STOP** — an orchestration bug, not a task failure |

The script is read-only and idempotent; re-running it after a fix is always safe. If it
emits `WARNING: no SCOPE globs given`, the scope criterion was skipped — say so in the
report rather than presenting the task as fully verified.

Around that check, still:
- `git checkout {PHASE_BRANCH}` first — the integration target for the whole phase. Never merge into the feature branch here.
- `git status --short` — no tracked uncommitted files (ignore untracked agent scratch: `.claude/worktrees/`, `.claude/agent-memory/`). Restore any stray out-of-scope TRACKED changes with `git checkout HEAD -- <file>`; commit any in-scope leftover onto `PHASE_BRANCH` and re-run the script. **Exclusion: never restore `$TASKS_PATH` (`specs/*/tasks.md`)** — that reverts completion marks. If it is dirty, **flag it** (scope violation by an agent, or a prior phase's uncommitted `[x]` marks) and commit the marks; do not discard them.
- For `[P]` tasks under `--parallel`: if the worktree branch was not merged back into `PHASE_BRANCH`, merge it with `scripts/merge-back.{sh,ps1} {PHASE_BRANCH} {branch} {TASK_ID}` (exit 0 = merged or already merged; exit 1 = conflict → **STOP** with the listed files) — NEVER into the feature branch.

**Fallback if the script cannot run** (missing interpreter, `plugin_root` unresolved,
permission denied): say so explicitly in the report, then evaluate the same three criteria
manually — `git log --oneline {feature_branch}..{PHASE_BRANCH} --grep="({TASK_ID})"`,
`git show --stat <sha>` for a non-empty file list, and check those paths against the task's
related-files list. The criteria are unchanged; only the mechanism is.

### Stopping on errors
- Error or incomplete result in parallel batch → **STOP**, ask user before proceeding
- Error or incomplete result in sequential task → **STOP**, do not run next task automatically
- Phase CHECKS failure (Step 7.5) → **STOP**, leave `PHASE_BRANCH` unmerged, do not mark any task `[x]`
- Exception: task already `[x]` — not an error, skip silently

### Baseline-red is not a regression
- A failing test/assertion that is **already red on `{current_branch}` before the task runs** is NOT that task's regression. If an agent reports a red test, have it confirm (e.g. `git stash` or check the baseline) whether the failure pre-exists. If it does, note it as pre-existing and attribute it to the task that is supposed to fix it (per tasks.md dependencies) — do not block the current task or weaken the assertion to force green. (Example from a past run: a TDD query-count assertion was red by design until the unification task turned it green; it was a false "N+1" alarm, not a regression.)

### Language
- All user-facing communication — **English**
