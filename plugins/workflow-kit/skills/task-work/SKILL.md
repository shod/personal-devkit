---
name: task-work
description: >-
  Implementation of a single specific task from tasks.md. Use /task-work T*** (e.g. T012, T025, T101)
  to start the implementation of the specified task. Recommended to call in a clean context (/clear before running).
  Supports --defer-checks to skip per-task Pint/PHPStan/Tests when checks run once per phase (phase-runner).
argument-hint: "<task-id> [--defer-checks]"
model: sonnet
allowed-tools: Bash(php *) Bash(./vendor/bin/*) Bash(composer *) Bash(git *) Bash(mkdir *) Bash(ls *) Bash(npm *) Bash(npx *) Bash(sail *) Bash(./sail *) Read Grep Glob Write Edit Task mcp__laravel-boost__application-info mcp__laravel-boost__search-docs mcp__laravel-boost__database-schema mcp__laravel-boost__database-query mcp__laravel-boost__tinker mcp__laravel-boost__list-artisan-commands mcp__laravel-boost__read-log-entries mcp__laravel-boost__last-error mcp__laravel-boost__get-config mcp__laravel-boost__get-absolute-url
---

# Task Work Skill

Wrapper around the speckit.implement workflow for implementing **a single specific task**. Designed for use in a clean context — run `/clear` before starting.

> **Base workflow**: Read the file `.specify/templates/commands/implement.md` from the project root — it is the complete speckit.implement instruction.

## Required argument

`$ARGUMENTS` **MUST** contain a task ID in the format `T***` (e.g., `T012`, `T025`, `T101`).

If `$ARGUMENTS` is empty — **STOP** and ask the user to specify the task ID:
> Specify the task ID: `/task-work T012`

## Algorithm

### Step 0: Context check

**BEFORE ANYTHING ELSE**: Check whether the skill is being called from an agent/orchestrator (task-runner) or directly by the user.

- **From agent (task-runner)**: skip clean context check — the agent has already performed validation and branch creation.
- **Directly by user**: Check whether this skill call is the **first message** in the conversation (excluding system messages).
  - If messages **already existed** before the call → **RECOMMEND** (do not block):
    > ⚠️ **Clean context recommended.**
    > For best results run `/clear`, then retry: `/task-work {TASK_ID}`
  - If first message — continue.

### Step 0.1: Argument validation

1. Extract TASK_ID from `$ARGUMENTS` (first match against pattern `T\d+`)
2. If TASK_ID not found — stop and ask user to specify ID
3. Extract `--defer-checks` (alias `--no-pint`) from `$ARGUMENTS` → save as **DEFER_CHECKS=true** (otherwise `false`). When `true`, the quality gates (Pint, PHPStan, Tests) are **SKIPPED** here because they run once per phase at the phase-level CHECKS step (see `phase-runner` + `task-git --scope=phase --phase-action=CHECKS`). This is set automatically when running under branch-per-Phase orchestration.

### Step 1: Load and execute speckit.implement workflow

1. Read the file `.specify/templates/commands/implement.md` from the project root (via Read tool)
2. Execute **all steps** from implement.md **in full**, with one restriction:

> **SCOPE OVERRIDE**: At the task execution step, implement **ONLY** task {TASK_ID}. All other tasks — **SKIP**. Do not proceed to the next task after completion.

> **CHECKS OVERRIDE (when DEFER_CHECKS=true)**: At the quality-gate step of implement.md, **SKIP Pint, PHPStan, and Tests entirely**. They run once per phase at the phase-level CHECKS step — do not run them per task. Still implement the code and apply all traceability tags. (When DEFER_CHECKS=false — the default for direct `/task-work` use — run the gates as normal.)

3. Before starting implementation — find task TASK_ID in tasks.md:
   - If task not found — **STOP**: "Task {TASK_ID} not found in tasks.md"
   - If task is already `[x]` / `[X]` — **WARN**: "Task {TASK_ID} is already complete. Continue?"
   - Show the user the task description before starting work

> **IMPORTANT**: implement.md is the single source of truth for the workflow. Follow it completely, skipping no steps.

### Step 1.5: PHPDoc Traceability (NON-NEGOTIABLE)

During implementation of task {TASK_ID} **MANDATORY** apply traceability tags at the **granular level**:

| Action | Tag | Example |
|--------|-----|---------|
| Class creation | `@created-by {TASK_ID}` | Class PHPDoc block |
| Method addition | `@created-by {TASK_ID}` | Method PHPDoc block |
| Property/constant addition | `@created-by {TASK_ID}` | Property PHPDoc block |
| Modifying existing method | `@modified-by {TASK_ID}` | Add to method PHPDoc |
| Modifying existing property | `@modified-by {TASK_ID}` | Add to property PHPDoc |
| Requirement linkage | `@spec FR-***/NFR-***` | If specified in tasks.md |

### Step 2: Summary

Show the user the result:

```
✓ Task {TASK_ID} complete
  Description: {brief description}
  Files:
    - path/to/file1.php
    - path/to/file2.php
  Checks:
    - Pint: ✓ / ✗ / deferred (phase-level)
    - PHPStan: ✓ / ✗ / deferred (phase-level)
    - Tests: ✓ / ✗ / N/A / deferred (phase-level)
```

> When **DEFER_CHECKS=true**, print `deferred (phase-level)` for all three gates instead of ✓/✗ — they will be run once at the phase CHECKS step.

## Rules

### Scope (NON-NEGOTIABLE)
- Implement **ONLY** task {TASK_ID} — do not touch others
- Do not refactor code unless it is part of the task
- Do not add functionality beyond the description

### Context
- When called directly by the user — **recommended** clean context (warning, not a block)
- When called from agent (task-runner) — context check is **skipped**
- Skill loads everything required via the implement.md workflow

### Webhook/Callback controllers
- If the contract or task requires "ALWAYS return 200" (typical for payment/webhook callbacks) — the controller **MUST** wrap the handler call in `try/catch(\Throwable $e)` and return HTTP 200 in catch. Otherwise side-effects (jobs, external APIs) may throw an exception → the provider receives 500 → retry storm.

### Test helpers for payloads
- When writing webhook/callback tests: if the `buildPayload()` helper accepts override parameters (e.g. `signature`), those values **MUST** be applied **after** building the base payload and **MUST NOT** be recalculated. Common mistake: `$params['signature'] = $this->calcSig($params)` ignores the passed override.

### MCP Tools — Use Before Manual File Reading (NON-NEGOTIABLE)

Always prefer MCP Laravel Boost tools over manual file reading when available:

| Need | MCP tool | Instead of |
|------|----------|------------|
| Database table structure | `mcp__laravel-boost__database-schema` | reading migration files |
| Check last exception | `mcp__laravel-boost__last-error` | guessing from PHPUnit output |
| Read Laravel logs | `mcp__laravel-boost__read-log-entries` | reading storage/logs/*.log |
| App/config values | `mcp__laravel-boost__application-info` | reading config/*.php |
| Search Laravel docs | `mcp__laravel-boost__search-docs` | web search |
| Run a DB query | `mcp__laravel-boost__database-query` | reading model/migration files |

### Test failure diagnosis (NON-NEGOTIABLE)

If tests failed — **before any code changes** read the logs via Laravel Boost:

1. **Last error**:
   ```
   mcp__laravel-boost__last-error
   ```
2. **Laravel log** (latest entries):
   ```
   mcp__laravel-boost__read-log-entries  (channel: "single" or "daily", limit: 20)
   ```
3. Only after analysing the logs — diagnose the cause and make changes.

> Do not try to guess the cause from PHPUnit output — the Laravel log contains the full stack trace and exception context that is absent from test output.

### PHPStan in projects with legacy errors (NON-NEGOTIABLE)

This project has **500+ legacy PHPStan errors** in existing files. For PHPStan tasks (T049 and similar):

1. **Run PHPStan only on new/changed files** — get the list via `git diff {feature_branch}...HEAD --name-only` and pass them via `--paths=` (or as positional arguments to vendor/bin/phpstan).
2. **Do not touch legacy errors** — fix only errors in files created/modified within the current feature branch.
3. To get the list of changed PHP files: `git diff development...HEAD --name-only -- "*.php"` (substitute the actual main branch name from CLAUDE.md).
4. If the task requires zero errors across the entire backend — clarify the scope with the user before starting.

### Coverage (NON-NEGOTIABLE)
- **DO NOT run** PHPUnit coverage (`--coverage`) automatically
- Coverage is checked **separately** via `/coverage` at the user's request
- If implement.md mentions coverage — **SKIP**

### Language
- Communication with user — **English**
- Code (class names, methods, variables) — **English**
- **PHPDoc blocks and inline comments — English** (all new and changed files)
