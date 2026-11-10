# workflow-kit: fixes from the shod-brain runs

**Source**: phase-runner runs in `shod-brain`, features 001–016 (2026-11-04 … 2026-11-10).
The problems come from brain cards (types `run`, `error_fix`, `task`, `note`, `howto`) and
from the 016 run.
**Plugin version**: workflow-kit 0.10.0.
**Status**: done in workflow-kit 0.11.0 (F1–F7). See `plugins/workflow-kit/CHANGELOG.md`.

## Summary

Most workarounds in shod-brain come from two causes:

1. workflow-kit has a fixed commit format, `feat(T001)`. Projects with commitlint require
   a lower-case scope (`feat(t001)`) and a body line limit.
2. `time-log` needs `php`. Non-PHP projects skip it, or the agent gets the wrong time zone.

The fixes F1–F3 remove these two causes. F4–F7 are smaller fixes.

| ID | Fix | Priority | Files |
|----|-----|----------|-------|
| F1 | Configurable commit scope case | high | `task-git`, `task-finisher`, `project-setup` schema |
| F2 | Case-insensitive task match in verify-task | high | `scripts/verify-task.sh`, `scripts/verify-task.ps1` |
| F3 | time-log without php | high | `skills/time-log/SKILL.md` |
| F4 | Short commit body | medium | `task-git` (COMMIT, phase scope) |
| F5 | Real check list in the time-log summary | low | `skills/time-log/SKILL.md` |
| F6 | No background shells left by agents | medium | `agents/task-coder.md`, `phase-runner` Step 7 |
| F7 | Pre-flight: tree clean, `feature.json` matches the branch | low | `phase-runner` Step 5.5 |

## F1. Configurable commit scope case

**Problem.** `task-git` COMMIT builds `feat({TASK_ID})` with `TASK_ID = T001`. A commitlint rule
`scope-case: lower-case` rejects it. The finisher fails, and phase-runner must commit by hand.
Cards: #1164, #2078, #425.

**Fix.**

1. Add an optional key to `.claude-project.json`:
   ```json
   "commit": { "scope_case": "lower" }
   ```
   Values: `"upper"` (default, current behavior) and `"lower"`.
2. In `task-git` (task scope COMMIT, task scope MERGE, phase scope COMMIT), build the scope from
   `TASK_ID` with this case. Example: `feat(t001): ...`.
3. In `task-finisher`, add no logic. The agent uses `task-git`, so it gets the fix.
4. In `project-setup`, detect the rule. If `commitlint.config.*` or `.commitlintrc*` has
   `scope-case` with `lower-case`, propose `"scope_case": "lower"`.
5. Document the key in `skills/project-setup/references/schema.md`.

**Check.** In a project with `scope-case: lower-case`, run one phase. The finisher commits on
the first try. There are no manual commits.

## F2. Case-insensitive task match in verify-task

**Problem.** `verify-task.sh` and `verify-task.ps1` find task commits with
`git log -E --grep="\(${TASK_ID}\)"`. The match is case-sensitive. With `feat(t001)` and
`TASK_ID = T001`, the script reports `commit missing`. phase-runner then verifies by hand or
passes the lower-case ID. Cards: #425, #271, #1027.

**Fix.**

1. Add `-i` (`--regexp-ignore-case`) to both `git log` calls in `verify-task.sh`
   (the commit list and the SHA list).
2. Make the same change in `verify-task.ps1` (lines with `--grep`).
3. Change the error text from `'feat(${TASK_ID})'` to `'(${TASK_ID})', any case`.

This fix is independent of F1. It also helps projects that already have mixed case in history.

**Check.** On a branch with `feat(t001)`, run `verify-task.sh <feature> <phase> T001`.
The result is `OK`.

## F3. time-log without php

**Problem.** `time-log` gets the time and the duration with `php -r`. Its `allowed-tools`
allow only `Bash(php *)`. In Go, Python and Flutter projects, php is often missing, so the
step is skipped (cards #502, #418, #168, #356, #357). When an agent uses a different command,
it can get UTC and report a wrong duration: 56 min instead of 3 min (card #2078).

**Fix.**

1. Replace the php commands with `date`, which exists in Git Bash, Linux and macOS:
   - now: `date '+%Y-%m-%d %H:%M:%S'`
   - duration: convert both times to epoch seconds and subtract.
     GNU date: `date -d "{START_TIME}" +%s`. On macOS, `date -j -f '%Y-%m-%d %H:%M:%S' ...`.
2. On Windows without Bash, use PowerShell:
   `Get-Date -Format 'yyyy-MM-dd HH:mm:ss'` and
   `New-TimeSpan -Start '{START_TIME}' -End '{END_TIME}'`.
3. Always use **local** time. Do not use `-u` or UTC. phase-runner Step 7 item 2 already
   makes `START_TIME` in local time, so both ends match.
4. Change `allowed-tools` to `Bash(date *) Bash(git diff *) PowerShell Write Read Grep Glob`.
   Remove `Bash(php *)`.

**Check.** Run `/time-log T001 --phase=START`, wait one minute, run END with that start.
The duration is about 1 minute.

## F4. Short commit body

**Problem.** The finisher once wrote a commit body line longer than 100 characters.
commitlint `body-max-line-length` rejected the commit (016 run, T003).

**Fix.**

1. In `task-git` COMMIT (both scopes), write the subject line only by default. Do not add a body.
2. If a body is necessary, wrap every line at 100 characters or less.
3. Cut the subject to 72 characters (the rule already exists in AUTO_MODE). Apply it in all modes.

## F5. Real check list in the time-log summary

**Problem.** The END summary always prints `Checks: Pint ✓ | PHPStan ✓ | Tests ✓`. In a phase run,
checks are deferred, and non-PHP projects have no Pint or PHPStan. The line is false.

**Fix.**

1. Add an optional `--checks="<text>"` argument to `time-log` END.
2. Print the `Checks:` line only when the argument is present.
3. In phase scope, do not pass it. The checks run once in phase CHECKS.

## F6. No background shells left by agents

**Problem.** In the 016 run, two `task-coder` agents (T003, T011) finished with a background
shell still running. The orchestrator had to stop them with TaskStop and confirm that the tree
did not change.

**Fix.**

1. In `agents/task-coder.md` Rules, add: "Do not use `run_in_background` for tests or builds.
   Run them in the foreground with a timeout. Before you return, make sure no shell that you
   started is still running."
2. In `phase-runner` Step 7 item 7, add a check after each `task-coder` run: if the agent result
   lists running background tasks, stop them, then run `git status --short` again.

## F7. Pre-flight: clean tree and the active feature

**Problem.**

- Uncommitted files in `docs/` stopped a run after the start (card #348).
- `.specify/feature.json` named a different feature than the git branch (cards #911, #318, #1156).
  Skills that read `feature.json` (spec-prepare, speckit-*) then use the wrong folder.

**Fix.** In `phase-runner` Step 5.5, before the first phase:

1. Run `git status --short`. If tracked files are dirty, **STOP** before any branch is created.
   Tell the user which files are dirty.
2. Read `.specify/feature.json` (if it exists). If its `feature_directory` is not the folder of
   `$TASKS_PATH`, print a warning with both values. Do not change the file.

## Out of scope

These problems are project-side. They need no change in workflow-kit:

- Flaky tests (`TestSchedulerIdleWithoutSources` port 47821, fixed in shod-brain `8636e47`;
  the mcpserver benchmark; two `internal/app` tests).
- A parallel session that commits into the active branch (card #623).
- `typos` reading a SHA fragment as a typo (card #563). Review reports can use task IDs
  instead of SHAs. This is a possible review-skill rule, but it is optional.
