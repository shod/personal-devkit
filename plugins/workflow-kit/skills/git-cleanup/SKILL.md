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
  work without a separate explicit yes.
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

## The one rule that makes this safe

A branch is safe to delete **only if its tip commit is already an ancestor of the
current feature branch** — i.e. every commit on it is reachable from where you
are, so nothing is lost. This is exactly what `git branch -d` checks, but you
verify it explicitly with `git merge-base --is-ancestor <branch> <feature>` so
you can *report* merged-vs-unmerged in the plan instead of just having `-d` fail.

Never use `git branch -D` (force) on your own initiative. Unmerged branches carry
commits that exist nowhere else — deleting them loses that work permanently.

## Workflow

### Step 1: Resolve the feature branch (the "keep" reference)

The feature branch is the branch everything else should have merged *into*, and
the one commit-ancestry is measured against. Resolve it from git, not assumptions:

```bash
git rev-parse --abbrev-ref HEAD    # the branch you're on now
```

Use the current branch as the feature branch **unless** it is itself a
`task/*`, `phase/*`, or `worktree-*` branch — cleaning up relative to a throwaway
branch makes no sense. If HEAD is one of those (or detached), **stop and ask** the
user which branch is the real feature branch (e.g. `002-onboarding-chat`, `main`,
`develop`). Never guess.

State the resolved feature branch to the user before continuing.

### Step 2: Enumerate the candidates

Collect the throwaway refs by pattern. These are the three families spec-kit
orchestration produces:

```bash
# Branches matching the throwaway patterns
git branch --list "task/*" "phase/*" "worktree-*"

# Worktrees (directories + their checked-out branch)
git worktree list --porcelain
```

Two distinct things get created and both need cleaning:
- **worktrees** — the `.claude/worktrees/agent-*` directories, each with a branch
  checked out into it. Listed by `git worktree list`.
- **branches** — `task/*`, `phase/*`, and the `worktree-agent-*` branches. Listed
  by `git branch`.

They overlap but are not the same: a `task/T045` branch may be checked out inside
a worktree, and there may also be standalone `worktree-agent-*` branches with no
live worktree. Handle both.

### Step 3: Classify each candidate as merged or unmerged

For every candidate branch, check whether it's already saved in the feature branch:

```bash
git merge-base --is-ancestor <branch> <feature-branch>   # exit 0 = merged, 1 = not
```

Build two lists:
- **MERGED** — tip is an ancestor of the feature branch → safe to delete.
- **UNMERGED** — has commits not in the feature branch → **keep, warn, never
  auto-delete** (per the safety contract; deleting these loses work).

For worktrees, classify by the branch checked out in them. A worktree whose branch
is merged is safe to remove; one whose branch is unmerged is flagged and kept.

### Step 4: Show the plan and wait for explicit approval

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

Ask via the normal approval flow. If the user wants only a subset (e.g. "just the
worktrees, leave the branches"), honor that.

### Step 5: Execute in the correct order

Order matters — **a branch checked out in a worktree cannot be deleted until the
worktree is removed first**. Otherwise `git branch -d` fails with "used by
worktree". So:

1. **Remove merged worktrees first:**
   ```bash
   git worktree remove <path>          # clean worktree
   git worktree remove --force <path>  # only if it has ignored/untracked build
                                       # artifacts AND its branch is merged
   ```
   Then `git worktree prune` to clear any stale administrative entries.

2. **Delete merged branches** with the safe flag (never `-D`):
   ```bash
   git branch -d <branch>
   ```
   `-d` refuses to delete an unmerged branch — a second safety net. If it refuses a
   branch you classified as merged, stop and investigate rather than reaching for
   `-D`; the classification and git disagree, and git is right.

Delete in batches by family (worktrees → phase → task → worktree-agent branches)
and report counts as you go.

### Step 6: Report

Summarize what happened: N worktrees removed, N branches deleted, and — importantly
— list what was **kept** and why, so the user knows unmerged work is still there:

```
✓ Removed 28 worktrees, deleted 79 merged branches.
⚠ Kept 1 unmerged branch (task/T099, 3 commits). Merge or delete it manually
  with `git branch -D task/T099` once you're sure.
```

## Unmerged branches: the explicit-override path

If the user, after seeing the warning, explicitly says to force-delete a specific
unmerged branch ("yes, delete task/T099, I don't need it"), you may run
`git branch -D <branch>` **for that named branch only**. Requirements:
- It must be a *separate, explicit* confirmation naming the branch — not covered by
  the Step 4 "proceed?" yes, which only authorizes merged deletions.
- Never batch-force-delete all unmerged branches on a single blanket yes. Each is
  potentially unique work; make the user own each one.

## What this skill never touches

- The feature branch itself, `main`, `master`, `develop`, or any branch not
  matching `task/*` / `phase/*` / `worktree-*`.
- Anything with uncommitted changes in a worktree — if `git worktree remove`
  refuses because the worktree is dirty, **stop and report** rather than forcing;
  the user may have unsaved work there.
- Remote branches. This is local cleanup only; deleting remote refs is a separate,
  higher-stakes action the user should request explicitly.
