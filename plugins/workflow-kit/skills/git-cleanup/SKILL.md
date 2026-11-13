---
name: git-cleanup
description: >-
  Safely remove the throwaway git branches and worktrees left behind after a
  spec-kit / task-runner implementation finishes — the `task/*`, `phase/*`,
  `worktree-*` branches and `.claude/worktrees/` directories that pile up once
  their work is merged into the feature branch. Use this whenever the user says
  they've finished an implementation, a phase, or a feature and wants to "clean
  up", "tidy branches", "remove worktrees", "delete old task/phase branches",
  or when `git branch`/`git worktree list` is cluttered with dozens of
  agent-generated refs. Deletes ONLY branches already merged into the current
  feature branch, always shows a plan first, and never force-deletes unmerged
  work without a separate explicit yes. Git commands run in the chore-runner
  agent (Haiku), except a small delete plan, which runs in the main session;
  the plan and the approval stay in the main session.
argument-hint: "[yes] [--backups=<feature>]"
model: sonnet
---

# Git Cleanup — remove merged task/phase/worktree leftovers

Spec-kit orchestration (`phase-runner`, `task-runner-parallel`) creates a lot of
short-lived git refs: one `task/T###` branch per task, one `phase/N` branch per
phase, a `worktree-agent-*` branch plus a `.claude/worktrees/agent-*` directory
per parallel worker. Once a phase is merged into the feature branch, all of that
is dead weight — but it accumulates fast (a single feature can leave 40+ task
branches and 30+ worktrees), which clutters `git branch`, slows tab-completion,
and makes it hard to see the branches that actually matter.

This skill cleans that up **safely**. The guiding principle: *only delete what is
provably already saved in history, show the user exactly what will happen before
touching anything, and never silently throw away work.* Branch deletion is
effectively irreversible for the user's mental model, so the cost of a wrong
deletion is high and the cost of asking first is low — always err toward asking.

## Who does what

| Step | Who | Why |
|------|-----|-----|
| 1–3 resolve, list, classify | `workflow-kit:chore-runner` (Haiku) | Mechanical git commands; long output stays out of the main context. |
| 4 plan and approval | main session | Approval is a decision. The agent cannot ask the user. |
| 5 remove and delete | `workflow-kit:chore-runner` (Haiku), or the main session for a small plan | Runs only the exact approved names. See "Small plan: run in the main session". |
| 6 report | main session | Built from the agent's report, or from the raw command output for a small plan. |

Start `chore-runner` with the Agent tool: `subagent_type: "workflow-kit:chore-runner"`.
Only the main session can start it (a subagent cannot start a subagent).
If the agent is not available, run the same commands directly in the main session
and keep every other rule.

Check the last line of each agent report. If it is `CHORE_RESULT: failed <command>` →
**STOP**, show the raw error lines to the user, and do not continue.

## Arguments

Parse `$ARGUMENTS`:
- `yes` — pre-approval of **merged** deletions. The skill still shows the plan, but does not
  ask the Step 4 question. It never covers unmerged branches, dirty worktrees or backup branches.
- `--backups=<feature>` — also offer the `backup/<feature>*-pre-squash*` branches (see
  "Backup branches"). Without this argument the skill never lists or deletes backup branches.

## The one rule that makes this safe

A branch is safe to delete **only if its tip commit is already an ancestor of the
current feature branch** — i.e. every commit on it is reachable from where you
are, so nothing is lost. This is exactly what `git branch -d` checks, but you
verify it explicitly with `git merge-base --is-ancestor <branch> <feature>` so
you can *report* merged-vs-unmerged in the plan instead of just having `-d` fail.

The classification uses only exit codes of exact git checks, never model reasoning
about names or dates.

Never use `git branch -D` (force) on your own initiative. Unmerged branches carry
commits that exist nowhere else — deleting them loses that work permanently.

## Workflow

### Steps 1–3: Resolve, list and classify (chore-runner)

Start `chore-runner` with this prompt (one call for all three steps):

```
Run these git commands in the repo root and report the raw results.
ON_FAIL: stop, except `git merge-base --is-ancestor`: exit 0 = merged, 1 = not merged
(a normal result, record it and continue).

1. git rev-parse --abbrev-ref HEAD
2. git branch --list "task/*" "phase/*" "worktree-*"
3. git worktree list --porcelain
4. For each branch from command 2, and for each branch checked out in a worktree
   from command 3 that matches task/*, phase/* or worktree-*:
   git merge-base --is-ancestor <branch> <FEATURE>
   where <FEATURE> is the output of command 1.
5. For each branch with exit code 1 in command 4:
   git rev-list --count <FEATURE>..<branch>

Do not delete or remove anything.
After the command lines, add these lists, built only from the exit codes:
FEATURE: <name>
MERGED: <branch names>
UNMERGED: <branch name> (<N> commits)
WORKTREES: <path> [<branch>] merged|unmerged
```

If `--backups=<feature>` is given, add to the same prompt:
```
6. git branch --list "backup/<feature>*-pre-squash*"
7. For each branch from command 6: git log -1 --format="%h %cs %s" <branch>
```

Then check the result in the main session:

1. **Feature branch.** Use `FEATURE` as the feature branch **unless** it is itself a
   `task/*`, `phase/*`, or `worktree-*` branch, or `HEAD` (detached) — cleaning up
   relative to a throwaway branch makes no sense. In that case **stop and ask** the
   user which branch is the real feature branch (e.g. `002-onboarding-chat`, `main`,
   `develop`), then start `chore-runner` again with that name. Never guess.
2. State the resolved feature branch to the user before continuing.
3. Make sure that every candidate is in `MERGED` or `UNMERGED`. If one is missing, or the
   lists and the raw exit codes disagree → **STOP** and report it.

What the lists mean:
- **MERGED** — tip is an ancestor of the feature branch → safe to delete.
- **UNMERGED** — has commits not in the feature branch → **keep, warn, never
  auto-delete** (per the safety contract; deleting these loses work).
- **Worktrees** are classified by the branch checked out in them. A worktree whose
  branch is merged is safe to remove; one whose branch is unmerged is flagged and kept.

Two distinct things get created and both need cleaning: **worktrees** (the
`.claude/worktrees/agent-*` directories, each with a branch checked out into it)
and **branches** (`task/*`, `phase/*`, `worktree-agent-*`). They overlap but are not
the same: a `task/T045` branch may be checked out inside a worktree, and there may
also be standalone `worktree-agent-*` branches with no live worktree. Handle both.

### Step 4: Show the plan and wait for explicit approval (main session)

Never delete before the user has seen the plan and said yes. Present it clearly —
grouped, counted, and honest about what is being kept and why. For example:

```
Feature branch (keeping everything merged into it): 002-onboarding-chat

WILL REMOVE (merged — work is safe in 002-onboarding-chat):
  Worktrees (28):
    .claude/worktrees/agent-a097d24b…  [task/T045]
    …
  Branches (79):
    phase/1 … phase/6          (7)
    task/T001 … task/T083      (44)
    worktree-agent-a097…       (28)

WILL KEEP (not merged — deleting would lose commits):
  task/T099   — 3 commits not in 002-onboarding-chat
  worktree-agent-abc…  [task/T099]

Proceed with removing the merged items? (yes / no)
```

- Without `yes`: ask via the normal approval flow. If the user wants only a subset
  (e.g. "just the worktrees, leave the branches"), honor that.
- With `yes`: show the plan and continue to Step 5 without the question. The approval
  covers only the WILL REMOVE list.
- If the plan is empty: say "Nothing to clean up." and stop.

### Small plan: run in the main session

Steps 1–3 always run in `chore-runner`, because the plan size is not known before the scan.
For Step 5, an agent run costs more than a few direct commands.

**Small plan** = the approved plan has **5 or fewer branches** to delete and **0 worktrees**
to remove. This is the only place that defines the threshold.

If the plan is a small plan:
1. Do not start `chore-runner` for Step 5.
2. Run the Step 5 `git branch -d` commands directly with the Bash tool, one command per line.
3. Use the same order as Step 5: `phase/*`, then `task/*`, then `worktree-agent-*`.
4. Read the raw output of each command.
5. Stop on the first non-zero exit code. Then follow the failure rules in Step 5.
6. Do not run `git worktree prune`. A small plan has no worktrees.

All safety rules stay the same, with no exceptions:
- Use only `git branch -d`. Never use `-D` or `--force`.
- Use only the exact approved branch names. Never use a pattern.
- Unmerged branches and backup branches still need a separate, explicit approval
  (see "Unmerged branches" and "Backup branches").
- If `git branch -d` refuses a branch, stop and report. Do not force it.

Any other plan uses `chore-runner` for Step 5.

### Step 5: Execute in the correct order (chore-runner, or the main session for a small plan)

For a small plan, use the rules in "Small plan: run in the main session". Otherwise use
`chore-runner` as below.

Order matters — **a branch checked out in a worktree cannot be deleted until the
worktree is removed first**. Otherwise `git branch -d` fails with "used by worktree".

Start `chore-runner` with the **exact approved names** — one command per worktree and
per branch, never a pattern:

```
Run these commands in the repo root, in this order. ON_FAIL: stop.

1. git worktree remove <path>        (one line per approved worktree)
2. git worktree prune
3. git branch -d <branch>            (one line per approved branch:
                                      phase/* first, then task/*, then worktree-agent-*)

Do not use -D, --force or any other command.
After the command lines, add:
REMOVED_WORKTREES: <count>
DELETED_BRANCHES: <count>
```

If the agent (or the main session, for a small plan) stops on a failure:
- **`git worktree remove` refuses** (dirty worktree) → do not force. Report it — the
  user may have unsaved work there. `git worktree remove --force <path>` is allowed only
  when the worktree has only ignored/untracked build artifacts, its branch is merged, and
  the user approves that exact path. Then pass the exact command and path to `chore-runner`.
- **`git branch -d` refuses a branch you classified as merged** → stop and investigate
  rather than reaching for `-D`; the classification and git disagree, and git is right.
- Commands after the failed one did not run. Show what was done, then ask the user
  whether to continue with the rest.

### Step 6: Report (main session)

Summarize from the agent's report: N worktrees removed, N branches deleted, and —
importantly — list what was **kept** and why, so the user knows unmerged work is
still there:

```
✓ Removed 28 worktrees, deleted 79 merged branches.
⚠ Kept 1 unmerged branch (task/T099, 3 commits). Merge or delete it manually
  with `git branch -D task/T099` once you're sure.
```

Take the counts from `REMOVED_WORKTREES` and `DELETED_BRANCHES`. For a small plan, count the
raw `Deleted branch ...` lines from the command output. Do not count from memory.

## Unmerged branches: the explicit-override path

If the user, after seeing the warning, explicitly says to force-delete a specific
unmerged branch ("yes, delete task/T099, I don't need it"), you may run
`git branch -D <branch>` **for that named branch only**. Requirements:
- It must be a *separate, explicit* confirmation naming the branch — not covered by
  the Step 4 "proceed?" yes or by the `yes` argument, which only authorize merged deletions.
- Never batch-force-delete all unmerged branches on a single blanket yes. Each is
  potentially unique work; make the user own each one.
- Pass the exact names to `chore-runner`, one `git branch -D <name>` line per approved
  branch. Write in the prompt: "The user approved force-delete of exactly these branches."

## Backup branches (`--backups=<feature>`)

`squash-commits` leaves `backup/<branch>-pre-squash` branches (sometimes with a
suffix like `-pre-squash-2`). They are **not** in the default families:
- The skill lists them only with `--backups=<feature>`, and only the ones whose name
  starts with `backup/<feature>`.
- `git branch -d` refuses them, because a squash rewrites history: the backup commits
  are not ancestors of the feature branch. So deletion needs `git branch -D`.
- Show them in the plan in a separate block `BACKUP BRANCHES (force-delete needed)`, with
  the tip line (`%h %cs %s`) from the agent report.
- Delete them only after a separate, explicit confirmation that names them (the same
  rule as the explicit-override path). The `yes` argument never covers them.
- Pass the exact names to `chore-runner`, one `git branch -D <name>` line per approved branch.

## What this skill never touches

- The feature branch itself, `main`, `master`, `develop`, or any branch not
  matching `task/*` / `phase/*` / `worktree-*` (and `backup/<feature>*-pre-squash*`
  only with `--backups`).
- Anything with uncommitted changes in a worktree — if `git worktree remove`
  refuses because the worktree is dirty, **stop and report** rather than forcing;
  the user may have unsaved work there.
- Remote branches. This is local cleanup only; deleting remote refs is a separate,
  higher-stakes action the user should request explicitly.
