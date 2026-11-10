---
name: time-log
description: >-
  Record task execution time and write log to time-log/.
  Use /time-log T*** --phase=START|END|ERROR to manage the task timer.
argument-hint: "[task-id] --phase=START|END|ERROR [--start=TIME] [--stopped-phase=N] [--checks=TEXT]"
allowed-tools: Bash(date *) Bash(mkdir *) Bash(git diff *) PowerShell Write Read Grep Glob
model: haiku
metadata:
  author: speckit
  version: "1.1"
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

## Time commands

The skill does not need `php`. Use `date` (Git Bash, Linux, macOS) or PowerShell.

> **Always use local time.** Do not use `date -u`, UTC or any time zone conversion.
> START_TIME comes from the caller in local time (phase-runner Step 7 item 2). If one end
> is UTC and the other is local, the duration is wrong by hours.

### NOW — the current time

Run the first command that works:

1. Bash: `date '+%Y-%m-%d %H:%M:%S'`
2. PowerShell: `Get-Date -Format 'yyyy-MM-dd HH:mm:ss'`

### DURATION — the time from START_TIME to END_TIME

Run the first method that works:

1. Bash. Convert both times to epoch seconds with two separate `date` calls:
   - GNU date (Linux, Git Bash): `date -d "{START_TIME}" +%s`, then `date -d "{END_TIME}" +%s`.
   - BSD date (macOS): `date -j -f '%Y-%m-%d %H:%M:%S' "{START_TIME}" +%s`, then the same for END_TIME.

   Subtract: `D = END_EPOCH - START_EPOCH`. Write it as `{D/3600}h {(D%3600)/60}m {D%60}s`,
   two digits each. Example: `1794301405 - 1794301200 = 205` → `00h 03m 25s`.
2. PowerShell:
   ```powershell
   $t = New-TimeSpan -Start '{START_TIME}' -End '{END_TIME}'; '{0:00}h {1:00}m {2:00}s' -f [int][math]::Floor($t.TotalHours), $t.Minutes, $t.Seconds
   ```

If the duration is negative, or longer than 24 hours, write `DURATION = unknown` and add a
note: `⚠ time-log: check START_TIME (local time?)`. Do not guess the value.

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
   - `--checks` — the real check results, for example `"Pint ✓ | PHPStan ✓ | Tests ✓"`

---

### Phase START — Record start time

1. Get the current time with NOW (see "Time commands").
2. Save result as **START_TIME**
3. Output:

```
⏱️ Start: {TASK_ID} — {START_TIME}
```

> **IMPORTANT**: The calling agent/user must save START_TIME to pass to the END/ERROR phase.

---

### Phase END — Summary

**Required arguments**: `--start="{START_TIME}"`
**Optional arguments**: `--branch`, `--target`, `--merge-msg`, `--checks`

1. Get END_TIME with NOW (see "Time commands").

2. Calculate DURATION with DURATION (see "Time commands").

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
  ✅ Checks: {checks}
  ⏱️ Time: {START_TIME} → {END_TIME} ({DURATION})

  Branch {TASK_BRANCH} retained for history.
═══════════════════════════════════════════
```

> If optional parameters (--branch, --target, --merge-msg, --checks) are not passed — omit the corresponding lines from the output.
>
> Never write a `Checks:` line without `--checks`. This skill does not run checks, so it
> cannot know the result. In a phase run the checks run once per phase (phase CHECKS), and
> the caller does not pass `--checks`.

---

### Phase ERROR — Error

**Required arguments**: `--start="{START_TIME}"`, `--stopped-phase={N}`

1. Get END_TIME with NOW (see "Time commands").

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
