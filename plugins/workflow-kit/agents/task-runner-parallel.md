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

**Phase mode (SCOPE=phase):** pass the phase flags and branch in each prompt:
```
Agent(
  subagent_type: "task-runner",
  isolation: "worktree",
  prompt: "Execute task {TASK_ID} --scope=phase --defer-checks --auto\n\nPHASE_BRANCH: {PHASE_BRANCH}\nBranch your worktree off {PHASE_BRANCH} HEAD as {task_branch_prefix}{TASK_ID}, commit feat({TASK_ID}): ..., then merge it back into {PHASE_BRANCH} (--no-ff). NEVER merge into the feature branch or development. Do NOT run Pint/PHPStan/Tests (checks are deferred to the phase level).",
  run_in_background: false
)
```

**CRITICAL**: all `Agent(...)` calls must be in **one message** — this ensures parallelism.

The `--auto` flag puts each `task-runner` into non-interactive mode: commit (and, in task scope, merge) execute with default values without asking the user (type `feat`, scope = `{TASK_ID}`, description from tasks.md).

Each agent runs in a separate git worktree (SDK creates and removes it automatically). Agents do not conflict when switching branches.

> **Merge-back serialization (phase mode).** Multiple worktree agents merging into the
> **same** `PHASE_BRANCH` concurrently will race. The implementation work runs in parallel,
> but the final merge-back into `PHASE_BRANCH` must be **serialized**: instruct each agent
> to commit on its own `{task_branch_prefix}{TASK_ID}` worktree branch, and if two agents
> race on the merge, the second retries after the first lands (fast-forward/`--no-ff` onto
> the updated `PHASE_BRANCH`). If a merge-back is left undone, `phase-runner`'s post-batch
> verification (Step 6) merges the leftover worktree branch into `PHASE_BRANCH`.

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
- **task scope (default):** each worktree branch merges into the **feature branch** (unchanged behavior).
- **phase scope (`--scope=phase`):** each worktree branch branches off `PHASE_BRANCH` HEAD and merges **back into `PHASE_BRANCH`** — **NEVER** the feature branch or development. The single feature-branch merge is done once by `phase-runner` after the phase CHECKS pass. Checks are deferred (`--defer-checks`): spawned agents do **not** run Pint/PHPStan/Tests. Serialize the merge-backs into `PHASE_BRANCH`.

### Delegation
- task-runner-parallel **does NOT implement** tasks — only orchestrates execution
- All implementation, commit, and merge logic is in the `task-runner` skill
- On one agent's error — other agents continue working

### Compatibility
- The `task-runner` skill for single tasks **does not change**
- task-runner-parallel is an addition, not a replacement

### Language
- Communication with user — **English**
