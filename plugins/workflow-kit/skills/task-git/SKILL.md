---
name: task-git
description: >-
  Git workflow for tasks: branch creation, commit, merge into feature branch.
  Use /task-git T*** (e.g. T002, T013) — the skill automatically determines
  the current phase (create → commit → merge) based on git state.
  Supports --scope=phase for branch-per-Phase orchestration (one phase/{N} branch,
  one CHECKS run, one merge) driven by phase-runner.
argument-hint: "<task-id|phase-number> [--scope=task|phase] [--phase=CREATE|COMMIT|MERGE] [--phase-action=CREATE|COMMIT|CHECKS|MERGE] [--auto]"
allowed-tools: Bash(git *) Read Grep Glob AskUserQuestion
metadata:
  author: speckit
  version: "1.0"
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
| `phase` | one branch per phase `{phase_branch_prefix}{N}` | phase number `N` | CREATE → COMMIT (per task) → CHECKS → MERGE (into feature branch) |

- **`--scope=task`** (or omitted) — the original per-task behavior, **unchanged**. Everything below the "Phase scope" section applies.
- **`--scope=phase`** — branch-per-Phase mode, driven by `phase-runner`. See the dedicated **"Phase scope"** section near the end of this file. In this mode the git sub-step is selected via `--phase-action=CREATE|COMMIT|CHECKS|MERGE` (NOT `--phase=`, which collides with the phase number).

## Required argument

`$ARGUMENTS` **MUST** contain:
- in `--scope=task` (default): a task ID in the format `T***` (e.g., `T002`, `T013`, `T101`).
- in `--scope=phase`: a phase number (e.g., `3`, `1`) plus `--phase-action=...`.

**Optional**: `--scope=task|phase` — branch granularity (default `task`).

**Optional**: `--phase=CREATE|COMMIT|MERGE` — force a specific phase in `task` scope (used when called from an agent/orchestrator).

**Optional**: `--phase-action=CREATE|COMMIT|CHECKS|MERGE` — the git sub-step in `phase` scope (always passed by `phase-runner`).

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

1. Extract **PHASE_NUM** from `$ARGUMENTS` (first bare integer; e.g. `3`, `1`). If not found → **STOP**: "No phase number specified (e.g. /task-git 3 --scope=phase --phase-action=CREATE)".
2. Extract **PHASE_ACTION** from `--phase-action=` (`CREATE|COMMIT|CHECKS|MERGE`). If missing → **STOP**.
3. Extract `--auto` → **AUTO_MODE** (default `false`).
4. For `COMMIT`: extract the **TASK_ID** (`T\d+`) being committed — `phase-runner`/`task-runner` pass it so the commit scope stays the task ID.
5. Determine **FEATURE_BRANCH** = `git branch --show-current` (the source of truth — **do not** read `feature_branch` from `.claude-project.json`, it is frequently stale).
6. Read `phase_branch_prefix` from `.claude-project.json` `paths` (e.g. `phase/`). Determine **PHASE_BRANCH** = `{phase_branch_prefix}{PHASE_NUM}` (e.g. `phase/3`).
7. Find FEATURE_DIR (`specs/*` containing `tasks.md`) for command/spec resolution.

### Phase action CREATE — create the phase branch (once)

**Condition**: currently on FEATURE_BRANCH, PHASE_BRANCH does not exist.

1. Ensure the working tree is clean (`git status --porcelain` empty). If dirty — **STOP**.
2. `git checkout -b {PHASE_BRANCH}`
3. Output:
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

1. **Pint** — run `commands.pint`.
   - If it modified files: `git add -A` → `git commit -m "style(phase-{PHASE_NUM}): pint"`.
   - On **unfixable** violations (Pint reports errors it cannot auto-fix) → **STOP** and report; do not proceed to PHPStan/Tests/MERGE.
2. **PHPStan (changed files only)** — get the changed PHP files:
   `git diff {FEATURE_BRANCH}...HEAD --name-only -- "*.php"`, pass them to `commands.phpstan` (as positional paths or `--paths=`). This honors the repo's 500+ legacy-error rule (only new/changed files are analysed; never touch legacy errors).
   - On errors in changed files → **STOP** and report.
3. **Tests** — run `commands.test`.
   - On any failing test → **STOP** and report. Do **not** proceed to MERGE.

Output:
```
✓ Phase {PHASE_NUM} checks passed
  Pint: ✓ (auto-fixed: {yes/no})   PHPStan: ✓ (changed files only)   Tests: ✓
```

> On any STOP here the phase branch is left **unmerged** for inspection. Never weaken an
> assertion or skip a gate to force green.

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
