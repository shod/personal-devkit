---
name: squash-commits
description: >-
  Squash all commits on the current branch into a single commit, relative to a
  base branch (default: development). Use when the user wants to combine/flatten
  many commits into one before merge or review. Creates a safety backup branch,
  soft-resets to the merge-base, and makes one commit. Does NOT push by default.
argument-hint: "[--base=<branch>] [--message=<text>] [--no-backup] [--push]"
allowed-tools: Bash(git *) AskUserQuestion
metadata:
  author: speckit
  version: "1.0"
  category: git-workflow
---

# Squash Commits Skill

Flattens **all commits on the current branch** into a single commit, relative to a
base branch. Uses a **soft reset to the merge-base** — the resulting tree is
byte-identical to the pre-squash state; only history is rewritten.

This skill never modifies project files (only git history) and **does not push by default**.

## Arguments

Parse `$ARGUMENTS`:
- `--base=<branch>` — base branch to squash against. Default: **`development`**.
- `--message=<text>` — commit message for the squashed commit. If omitted, the
  message of the current `HEAD` commit is offered as the default.
- `--no-backup` — skip creating the safety backup branch (not recommended).
- `--push` — after squashing, force-push with `--force-with-lease`. Default: **no push**.

## Algorithm

### Step 0: Validation

1. `git rev-parse --abbrev-ref HEAD` → **CURRENT_BRANCH**.
   - If `CURRENT_BRANCH` is the base branch (e.g. `development`) — **STOP**:
     "You are on the base branch `{base}`. Switch to a feature branch first."
2. `git status --porcelain` — if **not empty**, **STOP**:
   "Working tree is not clean. Commit or stash changes before squashing."
3. Resolve **BASE** from `--base=` or default `development`.
   - Verify it exists: `git rev-parse --verify {BASE}`. If not — **STOP** and ask
     the user for the correct base branch.
4. `git merge-base {BASE} HEAD` → **MERGE_BASE**.
   - If `MERGE_BASE == HEAD` — **STOP**: "Branch has no commits ahead of `{BASE}`. Nothing to squash."

### Step 1: Preview

1. Count commits: `git rev-list --count {MERGE_BASE}..HEAD` → **N**.
   - If **N == 1** — **STOP**: "Already a single commit on this branch. Nothing to squash."
2. Show the commits that will be combined:
   `git log --oneline {MERGE_BASE}..HEAD`
3. Show change stats: `git diff --stat {MERGE_BASE}..HEAD`
4. Present the summary:

```
About to squash {N} commits on {CURRENT_BRANCH} into one (base: {BASE}).
Merge-base: {short MERGE_BASE}
```

### Step 2: Confirm

If neither a message nor explicit go-ahead was provided in `$ARGUMENTS`, ask via **AskUserQuestion**:

**Question 1 — Commit message:**
- "Use current HEAD commit message" (recommended) — show the message text.
- "I'll provide it" — user enters via Other.

**Question 2 — Push strategy** (only if `--push` not already specified):
- "Squash, no push" (recommended) — local only.
- "Squash + force-push" — `--force-with-lease` after squashing.

If `--message=` was provided, skip Question 1 and use it.

### Step 3: Backup (unless --no-backup)

Create a safety branch at the current HEAD (free insurance, lets the user undo):

```
git branch backup/{CURRENT_BRANCH}-pre-squash HEAD
```

If the backup branch already exists, append a timestamp suffix (e.g. `-pre-squash-2`)
so an earlier backup is never overwritten.

### Step 4: Squash

```
git reset --soft {MERGE_BASE}
git commit -m "{MESSAGE}"
```

### Step 5: Verify

1. `git rev-list --count {MERGE_BASE}..HEAD` — **MUST** be `1`.
2. `git diff backup/{CURRENT_BRANCH}-pre-squash --stat` — **MUST** be empty
   (tree is identical to pre-squash state). If non-empty — **STOP** and warn the
   user that the squash changed the tree (should never happen with soft reset);
   advise restoring from backup.
   - If `--no-backup` was used, instead diff against the pre-squash HEAD SHA
     captured in Step 0.

### Step 6: Push (only if --push or user chose force-push)

```
git push --force-with-lease
```

### Step 7: Summary

```
✓ Squashed {N} commits into one on {CURRENT_BRANCH}
  New commit: {short SHA} — {MESSAGE first line}
  Backup:     backup/{CURRENT_BRANCH}-pre-squash  (delete when satisfied)
  Pushed:     {yes via --force-with-lease | no — local only}

  Undo:  git reset --hard backup/{CURRENT_BRANCH}-pre-squash
  Push later:  git push --force-with-lease
```

## Edge cases

- **Detached HEAD**: `git rev-parse --abbrev-ref HEAD` returns `HEAD` — **STOP**:
  "Detached HEAD. Check out a branch before squashing."
- **Merge commits in range**: a soft reset flattens them automatically; no special
  handling needed. Mention in the preview if merge commits are present.
- **Branch not pushed yet**: force-push step is harmless to skip; default is no push anyway.

## Rules

### Git operations
- Squash **ONLY** via soft reset to the merge-base. No interactive rebase
  (`rebase -i` is not supported in this environment).
- **ALWAYS** create the backup branch unless `--no-backup` is explicitly passed.
- **NEVER** push unless `--push` is passed or the user explicitly chooses force-push.
- Push **ONLY** with `--force-with-lease` — never bare `--force`.
- On any unexpected git error — **STOP**, show the error, do not retry destructively.

### Project workflow guard
- This rewrites history. Confirm with the user that **no teammate is building on
  this branch** before force-pushing.
- Per project policy, **never merge into `development`** — this skill only squashes
  the feature branch; the user handles merge/deploy.

### No code modification (NON-NEGOTIABLE)
- **PROHIBITED** to modify any project files. Works **ONLY** with git history.

### Language
- Communicate with the user in **English**.
