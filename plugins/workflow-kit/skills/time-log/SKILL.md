---
name: time-log
description: >-
  Record task execution time and write log to time-log/.
  Use /time-log T*** --phase=START|END|ERROR to manage the task timer.
argument-hint: "[task-id] --phase=START|END|ERROR [--start=TIME] [--stopped-phase=N]"
allowed-tools: Bash(php *) Bash(mkdir *) Bash(git diff *) Write Read Grep Glob
model: haiku
metadata:
  author: speckit
  version: "1.0"
  category: time-tracking
---

# Time Log Skill

Records task execution time and writes a log. The skill is **stateless** — it does not store state between calls; all data is passed via arguments.

## Required argument

`$ARGUMENTS` **MUST** contain:
1. Task ID in the format `T***` (e.g., `T002`, `T013`, `T101`)
2. `--phase=START|END|ERROR` — work phase

If `$ARGUMENTS` is empty — **STOP**:
> Specify the task ID and phase: `/time-log T013 --phase=START`

## Algorithm

### Step 0: Validation

1. Extract **TASK_ID** from `$ARGUMENTS` (first match against pattern `T\d+`)
2. Extract **--phase** (START, END, ERROR)
3. If TASK_ID not found — **STOP**: "Specify the task ID (format T***)"
4. If --phase not specified — **STOP**: "Specify phase: --phase=START|END|ERROR"
5. For END and ERROR phases — extract **--start** (required): START_TIME
6. For ERROR phase — extract **--stopped-phase** (required): stop phase number
7. For END phase — extract optional parameters:
   - `--branch` — task branch name
   - `--target` — feature branch name
   - `--merge-msg` — merge commit message

---

### Phase START — Record start time

1. Get current time via Bash:
   ```bash
   php -r "echo date('Y-m-d H:i:s');"
   ```
2. Save result as **START_TIME**
3. Output:

```
⏱️ Start: {TASK_ID} — {START_TIME}
```

> **IMPORTANT**: The calling agent/user must save START_TIME to pass to the END/ERROR phase.

---

### Phase END — Summary

**Required arguments**: `--start="{START_TIME}"`
**Optional arguments**: `--branch`, `--target`, `--merge-msg`

1. Get END_TIME via Bash:
   ```bash
   php -r "echo date('Y-m-d H:i:s');"
   ```

2. Calculate DURATION via Bash:
   ```bash
   php -r "\$s=new DateTime('{START_TIME}');\$e=new DateTime('{END_TIME}');echo \$s->diff(\$e)->format('%Hh %Im %Ss');"
   ```

3. Collect **change statistics** via git diff (comparing task branch with feature branch):
   ```bash
   git diff --shortstat {FEATURE_BRANCH}...HEAD
   ```
   Extract from output:
   - **FILES_CHANGED** — number of changed files
   - **INSERTIONS** — lines added
   - **DELETIONS** — lines deleted

   > If the command returns no output (no changes) — use `0` for all values.

4. Output the summary block:

```
═══════════════════════════════════════════
  ✓ Task Runner Complete: {TASK_ID}
═══════════════════════════════════════════

  🌿 Branch: {TASK_BRANCH} → {FEATURE_BRANCH}
  📝 Merge commit: {merge-msg}
  📁 Files changed: {FILES_CHANGED}
  📊 Lines: +{INSERTIONS} / -{DELETIONS}
  ✅ Checks: Pint ✓ | PHPStan ✓ | Tests ✓
  ⏱️ Time: {START_TIME} → {END_TIME} ({DURATION})

  Branch {TASK_BRANCH} retained for history.
═══════════════════════════════════════════
```

> If optional parameters (--branch, --target, --merge-msg) are not passed — omit the corresponding lines from the output.

---

### Phase ERROR — Error

**Required arguments**: `--start="{START_TIME}"`, `--stopped-phase={N}`

1. Get END_TIME via Bash:
   ```bash
   php -r "echo date('Y-m-d H:i:s');"
   ```

2. Output:
```
⏱️ STOPPED: {TASK_ID} — Phase {stopped-phase} | {START_TIME} → {END_TIME}
```

---

## Rules

### No code modification (NON-NEGOTIABLE)
- **PROHIBITED** to modify any project files
- Skill only reads data and outputs to console

### Language
- Communication with user — **English**
