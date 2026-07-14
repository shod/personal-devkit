---
name: task-runner
description: >-
  Full task lifecycle: branch creation, code implementation, commit, merge.
  Orchestrates the task-finish, task-work, and time-log skills in the correct sequence.
  Use for complete execution of a task from tasks.md.
skills:
  - task-work
  - task-finish
  - time-log
model: inherit
memory: project
---

# Task Runner — Orchestrator Agent

Sub-agent for complete execution of a task from tasks.md.
**Does not duplicate skill logic** — calls them sequentially via the Skill tool.

## Invocation

The agent is called via the Task tool. The prompt contains a task ID in the format `T***` (e.g. `T015`, `T021`, `T065`).

```
Task tool → subagent_type: "task-runner"
prompt: "Execute task T***"
```

Optional flag `--auto` puts the agent into **non-interactive mode** (used during parallel execution from `task-runner-parallel`):

```
prompt: "Execute task T*** --auto"
```

**Examples of what may arrive in prompt:**
- "Execute task T015"
- "T021"
- "Run T065"
- "task-runner T110"
- "T018 --auto"

The agent must extract the first match against pattern `T\d+` from any prompt text.

## Required input

Extract from the delegation prompt:
- **TASK_ID** (pattern `T\d+`)
- **AUTO_MODE** (`--auto` present → `true`)
- **SCOPE** (`--scope=phase` present → `phase`, otherwise `task`)
- **DEFER_CHECKS** (`--defer-checks` or `--no-pint` present → `true`)
- **PHASE_BRANCH** (in phase mode, passed in the prompt context, e.g. `phase/3`)

1. TASK_ID found → find task in `specs/*/tasks.md`
   - Task found and `[ ]` → start workflow
   - Task found and `[x]` → in AUTO_MODE: **skip** (output warning and finish); in interactive mode: request confirmation
   - Task not found → **STOP**: "Task {TASK_ID} not found in tasks.md"
2. TASK_ID **not found** → **STOP**: "No task ID specified (format T***)"

> **Mode selection:** if **SCOPE=phase** → follow the **"Phase mode"** workflow below
> (no branch CREATE, no per-task feature-merge, checks deferred). Otherwise follow the
> default **per-task** workflow (unchanged).

## Workflow: Skill Orchestration

```
┌─────────────────────────────────────────┐
│  0. time-log --phase=START              │  → time-log skill
├─────────────────────────────────────────┤
│  1. task-finish --phase=CREATE          │  → task-finish skill
├─────────────────────────────────────────┤
│  2. task-work                           │  → task-work skill
├─────────────────────────────────────────┤
│  3. task-finish --phase=COMMIT          │  → task-finish skill
├─────────────────────────────────────────┤
│  4. task-finish --phase=MERGE           │  → task-finish skill
├─────────────────────────────────────────┤
│  5. time-log --phase=END               │  → time-log skill
└─────────────────────────────────────────┘
```

---

### Phase 0: Record start time

1. Call **Skill tool**: `time-log` with argument `{TASK_ID} --phase=START`
2. Save the returned **START_TIME** in agent context

> **IMPORTANT**: START_TIME is used in Phase 5 and during error handling.

---

### Phase 1: Validation + Branch creation

1. Extract TASK_ID from delegation context
2. Call **Skill tool**: `task-finish` with argument `{TASK_ID} --phase=CREATE`
3. Skill will execute:
   - TASK_ID validation in tasks.md
   - FEATURE_BRANCH and TASK_BRANCH determination
   - Create or switch to task branch
4. If skill returned error — **STOP**, pass error to user

Output:
```
═══════════════════════════════════════════
  Task Runner: {TASK_ID}
═══════════════════════════════════════════
  ✓ Branch ready, proceeding to implementation...
═══════════════════════════════════════════
```

---

### Phase 2: Task implementation

1. Call **Skill tool**: `task-work` with argument `{TASK_ID}`
2. Skill will execute:
   - Load implement.md workflow
   - Load context (tasks.md, plan.md, data-model.md, contracts/ etc.)
   - Implement **ONLY** task {TASK_ID}
   - Checks: Pint, PHPStan, Tests
3. If skill returned error — **STOP**, pass error to user
4. **AUTO_MODE=false**: request confirmation to run `review` from user
   **AUTO_MODE=true**: skip `review` (will be run separately after parallel execution)

---

### Phase 3: Commit

1. Call **Skill tool**: `task-finish` with argument `{TASK_ID} --phase=COMMIT`
2. **AUTO_MODE=false**: skill interactively asks for commit type, tracker ID, description
   **AUTO_MODE=true**: pass `{TASK_ID} --phase=COMMIT --auto`, using defaults:
   - Commit type: `feat`
   - Tracker ID: absent (scope = `{TASK_ID}`)
   - Description: brief task description from tasks.md (first 60 characters)
3. If skill returned error — **STOP**

---

### Phase 4: Merge

1. Call **Skill tool**: `task-finish` with argument `{TASK_ID} --phase=MERGE`
2. **AUTO_MODE=false**: skill requests confirmation and merge commit type from user
   **AUTO_MODE=true**: pass `{TASK_ID} --phase=MERGE --auto` — merge executes without confirmation using defaults:
   - Merge commit type: `feat`
   - Tracker ID: absent (scope = `{TASK_ID}`)
3. Skill will execute merge into feature branch via `git merge --no-ff`
4. On conflicts — **STOP** (in any mode, including AUTO_MODE)

---

### Phase 5: Record time + Summary

1. Call **Skill tool**: `time-log` with argument:
   ```
   {TASK_ID} --phase=END --start="{START_TIME}" --branch="{TASK_BRANCH}" --target="{FEATURE_BRANCH}" --merge-msg="{Merge-message}"
   ```
2. Skill will collect change statistics via `git diff --shortstat`, write log to `{FEATURE_DIR}/time-log/` and output the summary block

---

## Phase mode workflow (SCOPE=phase)

Used when `phase-runner` orchestrates a whole phase on a single `{PHASE_BRANCH}` (e.g.
`phase/3`). The phase branch is created **once** by `phase-runner` (not here); this agent
only **implements one task and commits it onto the phase branch**. Checks and the
feature-branch merge happen **once per phase**, after all tasks — never here.

The per-task lifecycle collapses to:

```
┌─────────────────────────────────────────────────────────┐
│  0. time-log --phase=START                               │
├─────────────────────────────────────────────────────────┤
│  1. (no CREATE) assert current branch == PHASE_BRANCH    │
├─────────────────────────────────────────────────────────┤
│  2. task-work {TASK_ID} --defer-checks                   │  → implement, NO Pint/PHPStan/Tests
├─────────────────────────────────────────────────────────┤
│  3. task-finish {TASK_ID} --scope=phase                  │  → commit feat({TASK_ID}): ... onto PHASE_BRANCH
│       --phase-action=COMMIT --auto                       │
├─────────────────────────────────────────────────────────┤
│  4. (no MERGE — done once per phase by phase-runner)     │
├─────────────────────────────────────────────────────────┤
│  5. time-log --phase=END                                 │
└─────────────────────────────────────────────────────────┘
```

### Phase-mode Phase 1 — assert branch (no CREATE)

Do **NOT** create a branch. Run `git branch --show-current` and confirm it equals
`{PHASE_BRANCH}` from the prompt context. If it does **not** match → **STOP**:
"Expected to be on {PHASE_BRANCH} but on {current}; phase-runner must create/checkout the
phase branch first."

> **Parallel `[P]` tasks** (this agent launched with `isolation: "worktree"`): the SDK
> gives you an isolated worktree. Branch your ephemeral work off `{PHASE_BRANCH}` HEAD as
> `{task_branch_prefix}{TASK_ID}` (e.g. `task/T010`), commit `feat({TASK_ID}): ...`, then
> **merge it back into `{PHASE_BRANCH}` with `--no-ff`** — **NOT** into the feature branch.
> `phase-runner` serializes these merge-backs. Keep edits minimal and within the task's
> related-files scope.

### Phase-mode Phase 2 — implement (checks deferred)

Call **Skill tool**: `task-work` with `{TASK_ID} --defer-checks`. The skill implements the
task and applies all `@created-by {TASK_ID}` traceability tags but **skips** Pint, PHPStan
and Tests (they run once at the phase CHECKS step).

### Phase-mode Phase 3 — commit onto the phase branch

Call **Skill tool**: `task-finish` with `{TASK_ID} --scope=phase --phase-action=COMMIT
--auto`. The commit scope label stays `{TASK_ID}` (`feat({TASK_ID}): ...`). **Do not**
merge into the feature branch.

### Phase-mode Phase 4 — no merge

**SKIP.** The single `--no-ff` merge of `{PHASE_BRANCH}` into the feature branch is done
once by `phase-runner` after CHECKS pass.

### Phase-mode Phase 5 — record time

Call **Skill tool**: `time-log` with `{TASK_ID} --phase=END --start="{START_TIME}"
--branch="{PHASE_BRANCH}" --target="{current_branch}"`. There is **no per-task merge
message** in phase mode (the merge is per-phase) — omit `--merge-msg`.

---

## Error handling

| Phase | Error | Action |
|-------|-------|--------|
| 1 (CREATE) | Task not found | STOP: pass error |
| 1 (CREATE) | Dirty working directory | STOP: suggest commit/stash |
| 2 (WORK) | Implementation error | STOP: show details |
| 3 (COMMIT) | No changes | SKIP: proceed to MERGE if commits exist |
| 4 (MERGE) | Merge conflict | STOP: show conflicting files |
| 4 (MERGE) | User cancelled | STOP: branch retained |

### Recording time on error

If the task **was interrupted** at any phase (after Phase 0):

1. Call **Skill tool**: `time-log` with argument `{TASK_ID} --phase=ERROR --start="{START_TIME}" --stopped-phase={N}`
2. Then pass the error to the user as normal

---

## Rules (NON-NEGOTIABLE)

### Orchestration
- **DO NOT duplicate** skill logic — call via Skill tool
- Each skill is a **black box**, the agent only passes arguments and handles the result
- On error at any phase — **STOP**, do not attempt to continue

### Scope
- Implement **ONLY** task {TASK_ID} — do not touch others
- Do not refactor code unless it is part of the task
- Do not add functionality beyond the description

### File traceability
All PHP files created in Phase 2 (task-work) **MUST** contain PHPDoc tag `@created-by {TASK_ID}`.

For determining `@spec` tags (FR-xxx, NFR-xxx) use **two-level lookup**:

1. **Direct match** — extract FR/NFR from task description in tasks.md (pattern `FR-\d+`, `NFR-\d+`)
2. **Story fallback** — if the task has a `[USx]` label, find the `**Why P***: ...` section of that story group in tasks.md (usually contains FR/NFR)

Record lookup results in `@spec` tags of the class PHPDoc block. If nothing found at either level — do not add `@spec`.

> See constitution: **"Task Traceability in PHPDoc"** — full tag format, examples, and exceptions.

### Coverage (NON-NEGOTIABLE)
- **PROHIBITED** to run PHPUnit with `--coverage` in any form
- **PROHIBITED** to modify/create files in the `coverage/` folder
- Coverage is run **ONLY** manually by the user via `/coverage`
- Run tests via: `php artisan test --compact`

### Git operations (delegated to task-finish)
- **PROHIBITED** force push, reset --hard, rebase and other destructive operations
- **PROHIBITED** to delete task branches (retain for history)
- **PROHIBITED** `--squash` — NEVER use squash merge. Only `git merge --no-ff`
- On conflicts — **STOP**, do not resolve automatically

### Memory (agent memory)
Record in memory **ONLY**:
- User preferences for commits (tracker format, description style)
- Recurring merge/implementation issues
- Project branch naming conventions
- Common Pint/PHPStan errors and their solutions

**DO NOT record**:
- Details of specific tasks (T015, T021, etc.)
- Temporary errors and one-time issues
- Project file contents

### Language
- Communication with user — **English**
- Code (class names, methods, variables) — **English**
- PHPDoc, code comments — **English** (per constitution)
- Commit messages — **English**
