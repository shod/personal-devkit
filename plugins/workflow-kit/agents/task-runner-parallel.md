---
name: task-runner-parallel
description: >-
  Parallel execution of multiple [P]-marked tasks from tasks.md.
  Accepts a list of TASK_IDs and runs each task in an isolated git worktree
  via a separate task-runner agent. OPT-IN ONLY: in phase mode this agent is
  invoked exclusively when phase-runner was started with --parallel; without
  that flag phase-runner runs every task sequentially and never calls it.
skills:
  - task-runner
model: inherit
memory: project
---

# Task Runner Parallel — Parallel Orchestrator

Runs multiple `task-runner` agents simultaneously, each in an isolated git worktree.

> **When this agent runs at all.** Parallel execution is **opt-in**. `phase-runner` invokes
> this agent **only** when the user passed `--parallel`; by default it runs every task of the
> phase — `[P]`-marked or not — sequentially on `PHASE_BRANCH` via `task-runner`, and this
> agent is never reached. Direct invocation (`/task-runner-parallel T015 T016`) is itself an
> explicit opt-in and remains supported.

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

If `parallel_tasks` contains ≥2 tasks — detect file overlaps. This check is what makes
parallel execution safe; it is **never skipped silently**.

1. For each task find file mentions in the description (patterns: `app/`, `database/`, `resources/`, `.php`, `.vue`, `.ts`, `.dart`, `tests/`) → the task's **SCOPE**.
2. If the same file appears in two tasks' SCOPE → warn and require confirmation:
   ```
   ⚠️  Possible file conflict:
       {T0xx} and {T0yy} both touch: {file}
       Their edits are made in isolated worktrees and will only collide at merge-back.
       Continue? (yes/no)
   ```
3. **If a task's SCOPE cannot be extracted** (the task text names no file paths) — do **NOT**
   skip quietly. The whole safety argument for running these tasks concurrently is that their
   file sets are disjoint, and with no scope that cannot be established:
   ```
   ⚠️  SCOPE not determined for: {TASK_ID list}
       No file paths could be extracted from these tasks' text, so a parallel
       conflict is NOT guaranteed to be excluded — two workers may edit the same
       file and collide at merge-back.
       Options: run these tasks sequentially instead (recommended), or add explicit
       "Related files:" paths to the task text in tasks.md.
       Continue in parallel anyway? (yes/no)
   ```
   Ask via **AskUserQuestion** and **wait**. Without an explicit yes, do not launch the batch
   — report back to the caller that these tasks need sequential execution (which is
   `phase-runner`'s default mode anyway: dropping `--parallel` resolves it).
   Note this unverified-scope state in the Phase 4 summary as well, and remember that an
   empty SCOPE also weakens the per-task verification below (`verify-task` can only check
   scope when it is given globs).

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
> 4. Merge it back with the helper **script** and read the exit code — do not run the merge
>    by hand and do not interpret git output yourself:
>    ```
>    bash {plugin_root}/scripts/merge-back.sh {PHASE_BRANCH} {exact-branch} {TASK_ID}
>    # Windows / PowerShell:
>    {plugin_root}/scripts/merge-back.ps1 {PHASE_BRANCH} {exact-branch} {TASK_ID}
>    ```
>    It performs `git checkout {PHASE_BRANCH}` + `git merge --no-ff`, refuses to target
>    `development`/`master`/`main`, and is idempotent (a branch already merged exits 0 with
>    "nothing to merge"). Exit 0 = merged. Exit 2 = usage/repo error → **STOP**.
> 5. **Exit 1 = merge conflict** — the script has already aborted the merge and listed the
>    conflicting files on stderr, so `PHASE_BRANCH` is left clean, not mid-merge. **STOP**:
>    report those files for that task, do not attempt to resolve automatically, and do not
>    proceed to the next task's merge until the user resolves it.
> 6. **Verify the task actually landed** — a merge that produced nothing is not success:
>    ```
>    bash {plugin_root}/scripts/verify-task.sh {feature_branch} {PHASE_BRANCH} {TASK_ID} {SCOPE_GLOBS...}
>    # Windows: {plugin_root}/scripts/verify-task.ps1 {feature_branch} {PHASE_BRANCH} {TASK_ID} {SCOPE_GLOBS...}
>    ```
>    The task counts as done **only** when the `feat({TASK_ID})` commit is on `PHASE_BRANCH`
>    **AND** its diff versus the feature branch is **non-empty** **AND** at least one changed
>    file falls inside the task's SCOPE (Phase 2). Exit 0 = verified; any non-zero exit ⇒
>    that task is `✗ INCOMPLETE` — record it with the script's stderr and continue with the
>    rest of the batch. `{SCOPE_GLOBS...}` are the paths extracted in Phase 2; if that task
>    had no SCOPE, the script warns that the scope check was skipped — surface that warning
>    rather than reporting the task as fully verified.
>
> Since merges happen one at a time from this single process, there is no concurrent writer
> and no lock/CAS machinery is needed. If a worker's branch is somehow already merged (e.g.
> a retry), step 3 will show no new commits and `merge-back` exits 0 as a no-op — move on.
>
> **If the scripts cannot be run** (missing interpreter, `{plugin_root}` unresolved): say so
> explicitly in the summary, then apply the same criteria manually —
> `git merge --no-ff {exact-branch} -m "feat({TASK_ID}): merge into {PHASE_BRANCH}"`, and for
> verification `git log --oneline {feature_branch}..{PHASE_BRANCH} --grep="({TASK_ID})"` plus
> `git show --stat <sha>` checked against the task's SCOPE. The criteria do not change; only
> the mechanism does.

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

### Parallelism is OPT-IN
- This agent is invoked from `phase-runner` **ONLY** when the user passed `--parallel`. Without that flag `phase-runner` runs every task sequentially on `PHASE_BRANCH` and never reaches this agent. If you are running, parallelism was explicitly requested.
- Run in parallel **ONLY** tasks with the `[P]` marker
- Tasks without `[P]` — sequential only and only with explicit user consent
- All `Agent(...)` calls for parallel tasks — **in one message**
- **Never launch a batch with an unverified SCOPE** — if file paths cannot be extracted from a task's text, warn that a parallel conflict is not guaranteed to be excluded and get an explicit yes first (Phase 2.3). Silence is not consent.

### Verifying a task landed (NON-NEGOTIABLE criterion)
- A task is done **only** when: the `feat({TASK_ID})` commit is on `PHASE_BRANCH`, **AND** the diff versus the feature branch is **non-empty**, **AND** at least one changed file is inside the task's SCOPE. A commit that exists but changes nothing, or changes only out-of-scope files, is `✗ INCOMPLETE`.
- Evaluate it with `{plugin_root}/scripts/verify-task.{sh,ps1}` and read the **exit code** (0 = verified, 1 = incomplete, 2 = orchestration error); merge back with `{plugin_root}/scripts/merge-back.{sh,ps1}` the same way. Do not re-derive either verdict from raw git output. Manual fallback only if the scripts cannot run, and say so when you use it.

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
