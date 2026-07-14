---
name: sh-speckit-archive
description: >-
  Archive old/superseded Spec Kit feature folders out of specs/ into
  specs/archive/ while keeping the active feature in place. Use when the user
  wants to clean up, archive, or retire old speckit specs/initiatives. Moves
  folders with git mv (history preserved), keeps the active feature from
  .specify/feature.json, and checks for stale references. Does NOT commit by default.
argument-hint: "[NNN ...] [--all-old] [--commit]"
allowed-tools: Bash(git *) Bash(ls *) Bash(mkdir *) Read Grep AskUserQuestion
metadata:
  author: speckit
  version: "1.0"
  category: speckit-workflow
---

# Spec Kit Archive Skill

Moves old Spec Kit feature folders out of the active `specs/` directory into
`specs/archive/`, using `git mv` so full history is preserved. The **active
feature is never archived**, and project files (code) are never touched — only
the spec docs are relocated.

This skill **does not commit by default**. Per project workflow, the user does
commits/merges themselves.

## Arguments

Parse `$ARGUMENTS`:
- `NNN ...` — one or more spec numbers/prefixes to archive (e.g. `001 002 003`,
  or full names like `002-credit-card-payment-link`). Multiple allowed.
- `--all-old` — archive **every** spec folder except the active feature.
- `--commit` — after archiving, create a single commit on the current branch.
  Default: **no commit** (changes left staged).

If no spec selection (`NNN` or `--all-old`) is given, ask the user which specs
to archive via AskUserQuestion, listing the candidates (all specs except the
active feature).

## Algorithm

### Step 0: Validation

1. Confirm `specs/` exists. If not — **STOP**: "No `specs/` directory found; not a Spec Kit project."
2. Read the active feature directory from `.specify/feature.json`
   (`feature_directory` field, e.g. `specs/006-fix-payment-link-generation`).
   Derive **ACTIVE_NAME** (the basename). If the file is missing, treat
   ACTIVE_NAME as the highest-numbered spec folder and warn the user.
3. List candidate folders: every directory directly under `specs/` **except**
   `archive/` and **except** ACTIVE_NAME. Use a non-recursive listing.

### Step 1: Resolve selection

- `--all-old` → select all candidates.
- Explicit `NNN`/names → match each against candidate folder names by prefix.
  - Any token that resolves to ACTIVE_NAME → **STOP** and refuse:
    "`{name}` is the active feature and cannot be archived."
  - Any token that matches nothing → warn and skip it.
- No selection → AskUserQuestion (multiSelect) listing candidates; proceed with
  the chosen set.
- If the resolved set is empty → **STOP**: "Nothing to archive."

### Step 2: Move

1. `mkdir -p specs/archive`.
2. For each selected folder: `git mv "specs/<name>" "specs/archive/<name>"`.
   - If a target already exists in `specs/archive/`, skip it and report.

### Step 3: Reference check

Grep the repo for references to the moved paths to catch breakage:
`specs/<name>` (and the numeric prefix form `specs/NNN-`), excluding
`specs/archive/**`.
- Classify hits: ignore illustrative examples (lines containing `e.g.`,
  `for example`, or generic placeholders). Report any **real** path dependency
  (config files, scripts, active spec links) so the user can fix it.
- Always re-confirm `.specify/feature.json` still points at the active feature.

### Step 4: Report

Print a tree of the resulting `specs/` layout (active feature + `archive/`
contents) and the list of moved folders. State that changes are **staged but
not committed** unless `--commit` was passed.

### Step 5: Commit (only if `--commit`)

1. `git rev-parse --abbrev-ref HEAD` → CURRENT_BRANCH. If it is `development`
   (the protected base) — **STOP**: refuse to commit on the base branch.
2. Commit the staged moves with a message like:
   `chore(specs): archive old Spec Kit features → specs/archive/`
   Append the project co-author trailer.
3. **Do not push** and **do not merge** — the user handles that.

## Notes

- Archiving only relocates spec docs; merged/deployed code is unaffected.
- After archiving, speckit helpers that pick "the latest feature" by sorting
  `specs/*` will see only the active feature, which is the intended outcome.
- All output and messages must be in English.
