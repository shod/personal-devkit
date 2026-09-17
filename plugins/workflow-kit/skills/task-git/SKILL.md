---
name: task-git
description: >-
  Git workflow for tasks: branch creation, commit, merge into feature branch.
  Use /task-git T*** (e.g. T002, T013) — the skill automatically determines
  the current phase (create → commit → merge) based on git state.
  Supports --scope=phase for branch-per-Phase orchestration (one
  phase/{N}-{feature-slug} branch, one CHECKS run, one merge) driven by phase-runner.
argument-hint: "<task-id|phase-number> [--scope=task|phase] [--phase=CREATE|COMMIT|MERGE] [--phase-action=CREATE|COMMIT|CHECKS|MERGE] [--phase-branch=<name>] [--auto]"
allowed-tools: Bash(git *) Read Grep Glob AskUserQuestion
metadata:
  author: speckit
  version: "1.4"
  category: git-workflow
---

# Task Git Skill

Git workflow for speckit tasks. Manages the complete task branch lifecycle:
**branch creation → commit → merge into feature branch**.

The skill automatically determines the current phase based on git state and executes the next step.

## Two scopes

| Scope | Branch unit | Identifier | Lifecycle |
|-------|-------------|------------|-----------|
| `task` (default) | one branch per task `{task_branch_prefix}{TASK_ID}` | `T###` | CREATE → COMMIT → MERGE (into feature branch) |
| `phase` | one branch per phase `{phase_branch_prefix}{N}-{feature-slug}` | phase number `N` | CREATE → COMMIT (per task) → CHECKS → MERGE (into feature branch) |

- **`--scope=task`** (or omitted) — the original per-task behavior, **unchanged**. Everything below the "Phase scope" section applies.
- **`--scope=phase`** — branch-per-Phase mode, driven by `phase-runner`. See the dedicated **"Phase scope"** section near the end of this file. In this mode the git sub-step is selected via `--phase-action=CREATE|COMMIT|CHECKS|MERGE` (NOT `--phase=`, which collides with the phase number).

## Required argument

`$ARGUMENTS` **MUST** contain:
- in `--scope=task` (default): a task ID in the format `T***` (e.g., `T002`, `T013`, `T101`).
- in `--scope=phase`: a phase number (e.g., `3`, `1`) plus `--phase-action=...`.

**Optional**: `--scope=task|phase` — branch granularity (default `task`).

**Optional**: `--phase=CREATE|COMMIT|MERGE` — force a specific phase in `task` scope (used when called from an agent/orchestrator).

**Optional**: `--phase-action=CREATE|COMMIT|CHECKS|MERGE` — the git sub-step in `phase` scope (always passed by `phase-runner`).

**Optional**: `--phase-branch=<name>` — the fully resolved phase-branch name (e.g.
`phase/3-007-bookings-export-fields`). `phase-runner` resolves it once and passes it to every
phase-scope call; use it **verbatim** when present instead of re-deriving the name.

**Optional**: `--auto` — non-interactive mode (used during parallel execution from `task-runner-parallel`). In this mode, all user questions are replaced with default values.

If `$ARGUMENTS` is empty — **STOP** and ask the user to specify the task ID:
> Specify the task ID: `/task-git T013`

## Algorithm

### Step 0: Validation

0. Extract `--scope=task|phase` from `$ARGUMENTS` → save as **SCOPE** (default `task`).
   **If SCOPE=phase → jump to the "Phase scope" section near the end of this file** and follow it instead of Steps 1–M4 below. The rest of Step 0 and all phases below describe `task` scope only.
1. Extract TASK_ID from `$ARGUMENTS` (first match against pattern `T\d+`)
2. If TASK_ID not found — stop and ask user to specify ID
3. Extract `--phase=XXX` from `$ARGUMENTS` (if specified) → save as **FORCED_PHASE**
4. Extract `--auto` from `$ARGUMENTS` (if present) → save as **AUTO_MODE=true** (otherwise `false`)
4. Find FEATURE_DIR — directory `specs/FS-*` or `specs/*` containing `tasks.md`
5. Determine **FEATURE_BRANCH** = name of that directory (e.g., `FS-001-cart`)
6. Determine **TASK_BRANCH** = `{FEATURE_BRANCH}/{TASK_ID}` (e.g., `FS-001-cart/T002`)
7. Verify that task TASK_ID exists in `{FEATURE_DIR}/tasks.md`:
   - If not found — **STOP**: "Task {TASK_ID} not found in tasks.md"
   - If already `[x]` / `[X]` — **WARN**: "Task {TASK_ID} is already complete. Continue?"
8. Get current branch: `git branch --show-current`
9. Check existence of TASK_BRANCH: `git branch --list {TASK_BRANCH}`

### Step 1: Phase determination

**If FORCED_PHASE is set** — use it directly (skip auto-detection).

**Otherwise** — determine phase from git state:

| # | Current branch | Task branch exists | Uncommitted changes | Phase |
|---|---------------|----------------------|---------------------|------|
| 1 | FEATURE_BRANCH | No | — | **CREATE** |
| 2 | FEATURE_BRANCH | Yes | — | **SWITCH** |
| 3 | TASK_BRANCH | — | Yes | **COMMIT** |
| 4 | TASK_BRANCH | — | No | **MERGE** |
| 5 | Other branch | — | — | **ERROR** |

Show the user the determined phase:
> 📌 Task: {TASK_ID} — {description from tasks.md}
> 🔀 Phase: {CREATE|SWITCH|COMMIT|MERGE}

---

### Phase CREATE — Create task branch

**Condition**: we are on FEATURE_BRANCH, branch TASK_BRANCH does not exist.

1. Ensure the working directory is clean (`git status --porcelain` is empty)
   - If there are uncommitted changes — **STOP**: "There are uncommitted changes on {FEATURE_BRANCH}. Commit or stash them before creating the task branch."
2. Execute: `git checkout -b {TASK_BRANCH}`
3. Output result:

```
✓ Branch created: {TASK_BRANCH} (from {FEATURE_BRANCH})
  Task: {TASK_ID} — {description}

  Next step: implement the task, then run /task-git {TASK_ID} to commit
```

---

### Phase SWITCH — Switch to existing task branch

**Condition**: we are on FEATURE_BRANCH, branch TASK_BRANCH already exists.

1. Ensure the working directory is clean
2. Execute: `git checkout {TASK_BRANCH}`
3. Show status: `git status` and `git log {FEATURE_BRANCH}..{TASK_BRANCH} --oneline`
4. Output result:

```
✓ Switched to branch: {TASK_BRANCH}
  Commits: {N}

  Next step: /task-git {TASK_ID} to commit or merge
```

---

### Phase COMMIT — Commit changes

**Condition**: we are on TASK_BRANCH, there are uncommitted changes.

> **Commit format**: Conventional Commits 1.0.0 (see constitution)
> `<type>(<tracker-id>): <description>`

1. Show the user a change overview:
   - `git status --short` — file list
   - `git diff --stat` — statistics
2. **AUTO_MODE=false**: ask user via **AskUserQuestion**:

   **Question 1 — Commit type:**
   - `feat` — new functionality (recommended)
   - `fix` — bug fix
   - `refactor` — refactoring without behavior change
   - `test` — adding/modifying tests

   **Question 2 — Tracker ID** (optional):
   - Suggest format: `M24-XXXX` (e.g. `M24-1145`)
   - Option "No tracker ID" — then scope will be `{TASK_ID}`

   **Question 3 — Commit description:**
   - Suggest a brief description based on the task from tasks.md (recommended)
   - User can choose the suggested one or enter their own via "Other"

   **AUTO_MODE=true**: use defaults without questions:
   - Commit type: `feat`
   - Tracker ID: absent (scope = `{TASK_ID}`)
   - Description: first 72 characters of task description from tasks.md

3. Build commit message:
   - With tracker: `{type}({tracker-id}): {description}`
   - Without tracker: `{type}({TASK_ID}): {description}`
   - Examples:
     - `feat(M24-1145): add cart model`
     - `fix(T013): fix price calculation`
4. Execute:
   - `git add -A`
   - `git commit -m "{message}"`
5. Output result:

```
✓ Commit created in {TASK_BRANCH}
  Message: {message}
  Files changed: {N}

  Next step: review the code, optionally /review {TASK_ID}, then /task-git {TASK_ID} to merge
```

---

### Phase MERGE — Merge into feature branch

**Condition**: we are on TASK_BRANCH, no uncommitted changes.

#### Step M1: Summary

Show full report:

```
═══════════════════════════════════════════
  Merge Summary: {TASK_ID} → {FEATURE_BRANCH}
═══════════════════════════════════════════

  📋 Task: {description from tasks.md}

  📊 Commits ({N}):
  {git log FEATURE_BRANCH..TASK_BRANCH --oneline}

  📁 Files ({M}):
  {git diff FEATURE_BRANCH..TASK_BRANCH --name-only}

═══════════════════════════════════════════
```

#### Step M2: Merge decision

**AUTO_MODE=false**: ask via **AskUserQuestion**:
- "Perform merge" (recommended)
- "Cancel"

**AUTO_MODE=true**: perform merge without confirmation.

#### Step M3: Execute merge

> **ONLY `git merge --no-ff`** — all commits from the task branch are preserved in history, a merge commit is created in the feature branch. The branching and merging is visually visible in the git graph.
> **PROHIBITED: `--squash`**. Squash merge destroys individual task commits.

1. **AUTO_MODE=false**: ask user via **AskUserQuestion**:

   **Question 1 — Merge commit type:**
   - `feat` — new functionality (recommended)
   - `fix` — bug fix
   - `refactor` — refactoring
   - `test` — tests

   **Question 2 — Tracker ID**:
   - Suggest format: `M24-XXXX`
   - Option "No tracker ID" — scope will be `{TASK_ID}`

   **AUTO_MODE=true**: use defaults without questions:
   - Merge commit type: `feat`
   - Tracker ID: absent (scope = `{TASK_ID}`)

2. Build merge commit message:
   ```
   {type}({tracker-id}): {TASK_ID} {brief task description}

   Refs: #{tracker-id}
   ```
   Or without tracker:
   ```
   {type}({TASK_ID}): {brief task description}
   ```
   Examples:
   - `feat(M24-1145): T013 add cart item DTO\n\nRefs: #M24-1145`
   - `feat(T013): add cart item DTO`

3. Execute merge:
   - `git checkout {FEATURE_BRANCH}`
   - `git merge --no-ff {TASK_BRANCH} -m "{merge-message}"`
4. If merge conflict:
   - **STOP**: "Merge conflict. Resolve conflicts manually."
   - Show list of conflicting files
   - **DO NOT attempt to resolve automatically**

#### Step M4: Summary

```
✓ Merge complete: {TASK_BRANCH} → {FEATURE_BRANCH}
  Merge commit: {merge-message}

  Branch {TASK_BRANCH} retained for history.
```

---

## Phase scope (`--scope=phase`)

Branch-per-Phase mode. ONE branch per phase holds **every** task of that phase (one commit
per task — traceability preserved); **Pint + PHPStan + Tests run ONCE per phase** (CHECKS
action), then ONE `--no-ff` merge into the feature branch. Driven exclusively by
`phase-runner`, which passes the phase number positionally and the git sub-step via
`--phase-action=CREATE|COMMIT|CHECKS|MERGE`.

> **Why a separate flag:** `--phase=` already names the git sub-step in `task` scope and
> would be ambiguous with the phase **number** here. In `phase` scope **always** read the
> sub-step from `--phase-action=`. If `--phase-action` is missing → **STOP** and ask
> `phase-runner` to pass it.

### Step P0: Validation (phase scope)

1. Extract **PHASE_NUM** from `$ARGUMENTS` (first bare integer; e.g. `3`, `1`). If not found, and `--phase-branch=` was passed, take the number from that name (the digits right after the prefix, `phase/3-007-…` → `3`). If still not found → **STOP**: "No phase number specified (e.g. /task-git 3 --scope=phase --phase-action=CREATE)".
2. Extract **PHASE_ACTION** from `--phase-action=` (`CREATE|COMMIT|CHECKS|MERGE`). If missing → **STOP**.
3. Extract `--auto` → **AUTO_MODE** (default `false`).
4. For `COMMIT`: extract the **TASK_ID** (`T\d+`) being committed — `phase-runner`/`task-runner` pass it so the commit scope stays the task ID.
5. Determine **FEATURE_BRANCH** = `git branch --show-current` (the source of truth — **do not** read `feature_branch` from `.claude-project.json`, it is frequently stale). If the current branch **is** `PHASE_BRANCH` (COMMIT/CHECKS/MERGE run on it), take instead the branch it was created from: `git reflog show {PHASE_BRANCH}` → the `branch: Created from <name>` entry, or `--feature-branch=` if `phase-runner` passed it. If neither resolves → **STOP** rather than guessing.
6. Determine **PHASE_BRANCH**:
   - If `--phase-branch=<name>` was passed → use it **verbatim**. This is the normal path: `phase-runner` resolved the name once (Step 5.5) and every phase-scope call carries it.
   - Otherwise derive it: read `phase_branch_prefix` from `.claude-project.json` `paths` (e.g. `phase/`), take **FEATURE_SLUG** = basename of the spec directory holding `tasks.md` (`specs/007-bookings-export-fields` → `007-bookings-export-fields`; lowercase, every character outside `[a-z0-9._-]` → `-`, collapse repeats, trim `-`), and set **PHASE_BRANCH** = `{phase_branch_prefix}{PHASE_NUM}-{FEATURE_SLUG}` (e.g. `phase/3-007-bookings-export-fields`).
   - The slug makes the name **unique per feature**, so a phase branch from another spec can never be picked up by mistake. Never fall back to the bare `{phase_branch_prefix}{PHASE_NUM}` form — that is the legacy naming and is not created or written to anymore.
7. Find FEATURE_DIR (`specs/*` containing `tasks.md`) for command/spec resolution — and, when the slug has to be derived (6b), as its source.

### Phase action CREATE — create the phase branch (once)

**Condition**: currently on FEATURE_BRANCH, PHASE_BRANCH does not exist.

1. Ensure the working tree is clean (`git status --porcelain` empty). If dirty — **STOP**.
2. If `{PHASE_BRANCH}` **already exists**, `git checkout -b` will fail. Do **not** force it and
   do **not** delete the branch. Since the name carries the feature slug
   (`{phase_branch_prefix}{N}-{feature-slug}`), an existing branch is **this feature's own
   phase {N}** — an earlier, interrupted run — never a foreign feature's. **STOP** and report
   it; `phase-runner` decides before calling CREATE (Step 5.55: reuse the branch and check it
   out instead of creating it).
3. `git checkout -b {PHASE_BRANCH}`
4. Output:
```
✓ Phase branch created: {PHASE_BRANCH} (from {FEATURE_BRANCH})
  All Phase {PHASE_NUM} tasks will be committed here; CHECKS + merge run once at the end.
```

### Phase action COMMIT — commit one task onto the phase branch

**Condition**: on PHASE_BRANCH, uncommitted changes for one task.

Identical mechanics to the `task`-scope COMMIT phase, with one rule: **the commit scope
label stays the TASK_ID** so per-task traceability survives on the phase branch.

1. AUTO_MODE=true (always, in phase scope from orchestrator): type `feat`, no tracker, description = first 72 chars of the task description from tasks.md.
2. Build message: `feat({TASK_ID}): {description}`.
3. `git add -A` → `git commit -m "{message}"`.
4. Output: `✓ Commit on {PHASE_BRANCH}: {message}`.

> Do **not** merge into the feature branch here — that happens once at MERGE.

### Phase action CHECKS — run Pint + PHPStan + Tests once

**Condition**: on PHASE_BRANCH, all phase tasks committed, working tree clean.

Run all three quality gates **once** for the whole phase, in order. Use the commands from
`.claude-project.json` `commands.*` — **do not** hand-write `docker compose`.

> **The pass/fail verdict for every gate below MUST be derived by directly parsing the raw
> stdout/stderr of the command you just ran** — grep/match the tool's own failure markers
> (`FAILED`, `✗`, non-zero exit code, PHPStan's error count, PHPUnit's "N failed" summary
> line) in the actual captured output. Do not infer PASS from "the command didn't crash" or
> from your own paraphrase of what it printed — read the numbers/markers in the output
> itself. This is the one place in the whole skill chain where CHECKS is authoritative, so
> it must not degrade into a summarized impression of the output.

1. **Pint** — run `commands.pint`.
   - If it modified files: `git add -A` → `git commit -m "style(phase-{PHASE_NUM}): pint"`.
   - On **unfixable** violations (Pint reports errors it cannot auto-fix) → **STOP** and report; do not proceed to PHPStan/Tests/MERGE.
2. **PHPStan (changed files only)** — get the changed PHP files:
   `git diff {FEATURE_BRANCH}...HEAD --name-only -- "*.php"`, pass them to `commands.phpstan` (as positional paths or `--paths=`). This honors the repo's 500+ legacy-error rule (only new/changed files are analysed; never touch legacy errors).
   - On errors in changed files → **STOP** and report.
3. **Tests (full suite)** — pick the command by what the project defines:
   - **If `commands.test:bg` AND `commands.test:bg:wait` exist — use them (preferred):**
     1. Make sure no earlier suite run is still alive in the container (an orphan would
        overwrite the same log mid-run): list processes with `ps -eo pid,etime,args` via the
        project's exec command. If one is left, stop it with `kill <PID>`. **Never**
        `pkill -f "<pattern>"` inside `sh -c '...'` when the pattern also appears in that
        command line — it matches and kills its own shell (exit 143) and leaves the real
        process running.
     2. Run `commands.test:bg`. It returns immediately: the suite runs **detached inside the
        container** and writes a plain-text log ending with an `EXIT=<code>` line.
     3. Run `commands.test:bg:wait` with `run_in_background: true` and wait for its
        completion notification (do not poll, do not sleep in the foreground). Its output is
        the raw summary (`Tests:` / `FAILED` / `EXIT=` lines) read from the log.
     4. Verdict comes from that raw output: `EXIT=` must be `0` **and** the `Tests:` line must
        have no failed count. A missing `Tests:` line (crash, OOM, killed run) is a **failure**,
        not a pass. If `FAILED` lines are listed, read the failure details from the log file
        before reporting.
   - **Otherwise** run `commands.test` (legacy, foreground).
   - **Why detached:** a full suite run in the foreground (or as a host-side background
     command) streams all output through the host `docker compose exec` client. On a long
     suite that client has been killed "because the system is running low on memory": the
     output was lost and the PHP process kept running orphaned in the container. The
     detached run + log file finished reliably on every phase.
   - On any failing test → **STOP** and report. Do **not** proceed to MERGE.
   - Read the test runner's own summary line (e.g. `Tests: N failed, M passed`) from the
     captured output; a non-zero "failed" count is a failure regardless of exit code or any
     surrounding narration.

Output:
```
✓ Phase {PHASE_NUM} checks passed
  Pint: ✓ (auto-fixed: {yes/no})   PHPStan: ✓ (changed files only)   Tests: ✓
```

> On any STOP here the phase branch is left **unmerged** for inspection. Never weaken an
> assertion or skip a gate to force green.
>
> **Why this is spelled out explicitly:** a `task-runner` agent's *prose* summary of a test
> run has been observed, in production, to claim "completed successfully" while its own
> captured output showed real failures (`5 failed, 1206 passed`) — the failure shipped
> uncaught until an unrelated later re-read of the raw output caught it. That failure mode
> is why CHECKS never delegates the verdict to a subagent's phrasing, here or anywhere else
> in this skill: only direct parsing of the raw output established the verdict then, and
> only that should ever establish it. Do not relax this to "trust the summary" for speed.

### Phase action MERGE — merge the phase branch into the feature branch (once)

**Condition**: on PHASE_BRANCH, working tree clean, CHECKS passed.

1. Show summary: `git log {FEATURE_BRANCH}..{PHASE_BRANCH} --oneline` and `git diff {FEATURE_BRANCH}..{PHASE_BRANCH} --name-only`.
2. `git checkout {FEATURE_BRANCH}`
3. `git merge --no-ff {PHASE_BRANCH} -m "feat(phase-{PHASE_NUM}): merge phase {PHASE_NUM} into feature branch"`
   - **ONLY `--no-ff`** — preserve every per-task commit. **PROHIBITED: `--squash`.**
   - Merge into **FEATURE_BRANCH only** — **NEVER `development`**.
4. On merge conflict → **STOP**, list conflicting files, do **not** resolve automatically.
5. Output:
```
✓ Merge complete: {PHASE_BRANCH} → {FEATURE_BRANCH}
  Merge commit: feat(phase-{PHASE_NUM}): merge phase {PHASE_NUM} into feature branch
  Branch {PHASE_BRANCH} retained for history.
```
6. If the merged diff contains new migrations
   (`git diff --name-only {FEATURE_BRANCH}@{1}..{FEATURE_BRANCH} -- "*database/migrations/*.php"`
   is non-empty), report them in the output. The phase tests ran on `RefreshDatabase`, i.e. a
   throwaway schema — the **dev database is not migrated**. This skill does not run
   migrations (it works only with git); `phase-runner` applies `commands.migrate` right after
   MERGE (its Step 7.5.3). Never let new migrations pass unmentioned.

---

## Edge cases

### Multiple specs directories
If multiple `specs/*/tasks.md` directories are found — ask user which feature to use.

### Not on FEATURE_BRANCH or TASK_BRANCH
Output error:
> ❌ Current branch `{current}` does not match expected branches:
> - Feature: `{FEATURE_BRANCH}`
> - Task: `{TASK_BRANCH}`
>
> Switch to one of them.

### No commits to merge
If `git log {FEATURE_BRANCH}..{TASK_BRANCH}` is empty — output:
> No changes to merge. Branch {TASK_BRANCH} is identical to {FEATURE_BRANCH}.

## Rules

### Git operations (NON-NEGOTIABLE)
- **PROHIBITED** force push, reset --hard, rebase and other destructive operations
- **PROHIBITED** to delete task branches (retain for history)
- **PROHIBITED** `git merge --squash` — NEVER use squash. Squash destroys commit history
- Merge **ONLY** via `git merge --no-ff` (merge commit, Conventional Commits 1.0.0). No other strategies
- On conflicts — **STOP**, do not resolve automatically

### No code modification (NON-NEGOTIABLE)
- **PROHIBITED** to modify any project files
- **PROHIBITED** to use Edit/Write on any project files
- Does **NOT** run task implementation — skill works **ONLY** with git
- Code quality checks are the responsibility of `/review`, **NOT** this skill

### Language
- Communication with user — **English**
- Commit messages — **English** (unless the user specifies otherwise)
