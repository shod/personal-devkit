---
name: task-runner-parallel
description: >-
  Parallel execution of multiple [P]-marked tasks from tasks.md.
  Accepts a list of TASK_IDs and runs each task in an isolated git worktree
  via a separate task-runner agent. Use when you need to execute several
  independent tasks simultaneously.
skills:
  - task-runner
model: inherit
memory: project
---

# Task Runner Parallel — Parallel Orchestrator

Runs multiple `task-runner` agents simultaneously, each in an isolated git worktree.

## Invocation

```
/task-runner-parallel T015 T016 T018
```

or via Agent tool:
```
Agent(subagent_type: "task-runner-parallel", prompt: "T015 T016 T018")
```

Accepts a list of TASK_IDs in any format:
- `T015 T016 T018`
- `T015, T016, T018`
- `T015,T016,T018`

## Workflow

---

### Phase 1: Parse and validate

1. Extract all TASK_IDs (pattern `T\d+`) from prompt
1a. Extract mode flags from the prompt: **SCOPE** (`--scope=phase` → `phase`, else `task`), **DEFER_CHECKS** (`--defer-checks`/`--no-pint` → `true`), and **PHASE_BRANCH** (when in phase mode, read from the context block, e.g. `phase/3`). In `phase` mode every spawned `task-runner` must receive `--scope=phase --defer-checks` and the `PHASE_BRANCH`, and merges its worktree branch **back into `PHASE_BRANCH`** — never into the feature branch or development.
2. If no TASK_IDs found → **STOP**: "No task IDs specified (format: T015 T016 T018)"
3. Find `specs/*/tasks.md` (current feature)
4. For each TASK_ID:
   - Find task in tasks.md
   - Task `[x]` (done) → warn, exclude from list
   - Task not found → **STOP**: "Task {TASK_ID} not found in tasks.md"
   - Check for `[P]` marker in the task line
5. Split list into two groups:
   - `parallel_tasks` — tasks with `[P]` marker
   - `sequential_tasks` — tasks without `[P]` marker

If `sequential_tasks` is not empty — warn the user:
```
⚠️  The following tasks are NOT marked as [P] and will not run in parallel:
    {sequential_tasks list}

    Run them sequentially after the parallel ones? (yes/no)
```

---

### Phase 2: File conflict check

If `parallel_tasks` contains ≥2 tasks — attempt to detect file overlaps:

1. For each task find file mentions in the description (patterns: `app/`, `database/`, `resources/`, `.php`, `.vue`, `.ts`)
2. If the same files are mentioned in two tasks → warn:
   ```
   ⚠️  Possible file conflict:
       {T0xx} and {T0yy} both touch: {file}
       Continue? (yes/no)
   ```
3. If files are not annotated — skip check (do not block)

---

### Phase 3: Parallel execution

Output before starting:
```
═══════════════════════════════════════════════════
  Task Runner Parallel: {TASK_ID list}
═══════════════════════════════════════════════════
  Starting {N} agents in parallel in isolated worktrees...
═══════════════════════════════════════════════════
```

For each task in `parallel_tasks` — launch **Agent tool** in a single message:
```
Agent(
  subagent_type: "task-runner",
  isolation: "worktree",
  prompt: "Execute task {TASK_ID} --auto",            # task scope (default)
  run_in_background: false
)
```

**Phase mode (SCOPE=phase):** pass the phase flags and branch in each prompt. Workers **do
NOT** merge back into `PHASE_BRANCH` themselves — see "Merge-back serialization" below:
```
Agent(
  subagent_type: "task-runner",
  isolation: "worktree",
  prompt: "Execute task {TASK_ID} --scope=phase --defer-checks --auto\n\nPHASE_BRANCH: {PHASE_BRANCH}\nBranch your worktree off {PHASE_BRANCH} HEAD as {task_branch_prefix}{TASK_ID} and commit feat({TASK_ID}): ... on it. Do NOT merge into {PHASE_BRANCH}, the feature branch, or development — task-runner-parallel merges every worker's branch back sequentially after the whole batch finishes. Do NOT run Pint/PHPStan/Tests (checks are deferred to the phase level). Report the exact worktree branch name you committed to.",
  run_in_background: false
)
```

**CRITICAL**: all `Agent(...)` calls must be in **one message** — this ensures parallelism.

The `--auto` flag puts each `task-runner` into non-interactive mode: commit (and, in task scope, merge) execute with default values without asking the user (type `feat`, scope = `{TASK_ID}`, description from tasks.md).

Each agent runs in a separate git worktree (SDK creates and removes it automatically). Agents do not conflict when switching branches or committing — only the merge-back step below touches shared refs.

> **Merge-back serialization (phase mode) — done centrally, not by the workers.**
> Concurrent worktree agents merging into the **same** `PHASE_BRANCH` at once is a race:
> two workers can each read the same starting tip and clobber one another's merge when they
> write the ref. The fix is architectural, not a lock: in phase mode, workers **only**
> implement and commit onto their own `{task_branch_prefix}{TASK_ID}` worktree branch (see
> the prompt above) and never touch `PHASE_BRANCH`. `task-runner-parallel` — a single
> process — merges every worker's branch back **sequentially, one at a time**, once the
> whole batch has returned. Because there is only ever one writer to `PHASE_BRANCH`, the
> race cannot occur by construction.
>
> After all agents in the batch have returned, for each `TASK_ID` **in the order the tasks
> were listed** (not completion order):
> 1. `git checkout {PHASE_BRANCH}`
> 2. Locate the worker's branch: prefer the branch name the agent reported; otherwise
>    `git branch --list "{task_branch_prefix}{TASK_ID}*"` to find it.
> 3. `git log {PHASE_BRANCH}..{exact-branch} --oneline` — confirm the expected
>    `feat({TASK_ID}): ...` commit is present. If empty or missing, mark that task `✗
>    INCOMPLETE` and skip its merge (do not block the rest of the batch).
> 4. `git merge --no-ff {exact-branch} -m "feat({TASK_ID}): merge into {PHASE_BRANCH}"`.
> 5. On conflict — **STOP**: report the conflicting files for that task; do not attempt to
>    resolve automatically, and do not proceed to the next task's merge until the user
>    resolves it (an unresolved conflict leaves `PHASE_BRANCH` mid-merge).
>
> Since merges happen one at a time from this single process, there is no concurrent writer
> and no lock/CAS machinery is needed. If a worker's branch is somehow already merged (e.g.
> a retry), step 3 will show no new commits — skip it and move on.

---

### Phase 4: Results summary

After all agents complete, output the summary table:

```
═══════════════════════════════════════════════════
  Parallel execution complete
═══════════════════════════════════════════════════
  ✓ T015  — done  (2m 34s)
  ✓ T016  — done  (3m 12s)
  ✗ T018  — ERROR: merge conflict in app/Models/Order.php
═══════════════════════════════════════════════════
  Total: 2/3 completed
═══════════════════════════════════════════════════
```

If there are errors — output details for each error.
If all succeeded — output the list of created merge commits.

---

### Phase 5: Sequential tasks (optional)

If the user agreed to run `sequential_tasks` after the parallel ones:

For each task in tasks.md order:
1. Call **Skill tool**: `task-runner` with argument `{TASK_ID}`
2. Wait for completion before starting the next one

---

## Rules (NON-NEGOTIABLE)

### Parallelism
- Run in parallel **ONLY** tasks with the `[P]` marker
- Tasks without `[P]` — sequential only and only with explicit user consent
- All `Agent(...)` calls for parallel tasks — **in one message**

### Isolation
- Each agent runs with `isolation: "worktree"` — this is mandatory
- DO NOT manage worktrees manually (SDK does this automatically)
- Task branches are created in the worktree and retained in the main repository after merge

### Merge target (scope-dependent)
- **task scope (default):** each worktree branch merges into the **feature branch** (unchanged behavior). Workers merge their own branch (no concurrent-writer risk since each task-scope worker targets a distinct feature-branch merge in its own worktree flow, per `task-git`).
- **phase scope (`--scope=phase`):** every worker's worktree branch branches off `PHASE_BRANCH` HEAD but **workers themselves never merge into `PHASE_BRANCH`** — see "Merge-back serialization" above. `task-runner-parallel` merges all of them back **sequentially, one at a time**, immediately after the parallel batch returns, before reporting results. **NEVER** the feature branch or development. The single feature-branch merge is done once by `phase-runner` after the phase CHECKS pass. Checks are deferred (`--defer-checks`): spawned agents do **not** run Pint/PHPStan/Tests.

### Delegation
- task-runner-parallel **does NOT implement** tasks — only orchestrates execution and, in phase mode, the sequential merge-back
- All implementation and commit logic is in the `task-runner` skill; the phase-mode merge-back into `PHASE_BRANCH` is performed directly by task-runner-parallel (not delegated), by design, to guarantee a single writer
- On one agent's error — other agents continue working; that task is skipped in the merge-back step

### Compatibility
- The `task-runner` skill for single tasks **does not change**
- task-runner-parallel is an addition, not a replacement

### Language
- Communication with user — **English**
