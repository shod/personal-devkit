# workflow-kit: fixes from the horoscope 031 run

**Source**: phase-runner run of Phase 7 in `horoscope`, feature `031-session-paywall-chat-fixes`
(2026-11-11, tasks T028–T030).
**Plugin version**: workflow-kit 0.11.0.
**Status**: open.

| ID | Fix | Priority | Files |
|----|-----|----------|-------|
| H1 | Per-task line statistics in time-log END | medium | `skills/time-log/SKILL.md` |
| H2 | time-log description says it writes files | low | `skills/time-log/SKILL.md` (frontmatter) |

## H1. Per-task line statistics in time-log END

**Problem.** time-log END collects the statistics with
`git diff --shortstat {FEATURE_BRANCH}...HEAD`. In a phase run, all tasks commit on one phase
branch. So for the second and later tasks, the diff includes the commits of the earlier tasks.

Example from the run:

| Task | Real task commit | time-log END output |
|------|------------------|---------------------|
| T029 | 1 file, +34 / -28 | 2 files, +117 / -101 |
| T030 | 2 files, +206 / -0 | 4 files, +323 / -101 |

The finisher agents noticed this and wrote it in their notes. The numbers in the summary block
are still wrong for the task.

**Fix.**

1. In time-log END, read the scope from an argument. Add an optional `--scope=task|phase`
   (default `task`).
2. For `--scope=phase`, use the diff of the last commit only: `git diff --shortstat HEAD~1..HEAD`.
   task-finisher runs END right after the task commit, so `HEAD` is the task commit.
3. For `--scope=task`, keep `git diff --shortstat {FEATURE_BRANCH}...HEAD`. A task branch holds
   only one task.
4. In `agents/task-finisher.md`, pass `--scope=phase` to time-log END.

**Check.** Run a phase with 3 tasks. The END statistics of each task match
`git show --shortstat <task commit>`.

## H2. time-log description says it writes files

**Problem.** The frontmatter description says: "Record task execution time and write log to
time-log/". The Rules section says: "PROHIBITED to modify any project files. Skill only reads
data and outputs to console". The skill writes no file, and the project has no `time-log/`
folder. A user who reads the description looks for log files that do not exist.

**Fix.**

1. Change the description to: "Record task execution time and print a summary to the console."
2. Remove `Write` from `allowed-tools` if no step needs it (`Bash(mkdir *)` too).

**Check.** The description and the Rules section say the same thing.
