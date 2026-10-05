---
name: hand-off
description: >-
  Save a hand-off snapshot of the current work session into a feature folder
  (specs/<feature>/handoffs/), so the work can continue in a new chat or by
  another person/agent. Uses the active Spec Kit feature from
  .specify/feature.json, or a feature name passed as an argument. Use when the
  user says "hand-off", "handoff", "save a snapshot", "save context", "сохрани
  слепок", "передай контекст", before /clear, or before ending a long session.
  Captures goal, state, decisions, open questions, next steps and git state.
  Does NOT commit by default.
argument-hint: "[<feature-name-or-NNN>] [--title=<text>] [--commit]"
allowed-tools: Bash(git *) Bash(ls *) Bash(mkdir *) Bash(date *) Read Write Glob Grep AskUserQuestion
metadata:
  author: Oleg Shmyk
  version: "1.0"
  category: speckit-workflow
---

# Hand-off Skill

Writes a **self-contained snapshot** of the current session into the feature folder.
A new chat (or another developer) reads only this file and can continue the work
without the old conversation.

The snapshot is a new file every time — old snapshots are never overwritten.

## Arguments

Parse `$ARGUMENTS`:
- `<feature>` (optional, first non-flag token) — feature folder name or prefix
  inside `specs/` (e.g. `007`, `007-airport-default-pickup`, `DUBAIRPORT-979`).
- `--title=<text>` — short topic for the file name (default: derived from the session goal).
- `--commit` — commit the snapshot on the current branch. Default: **no commit**.

## Algorithm

### Step 1: Resolve the feature folder → FEATURE_DIR

1. **Argument given** → match it against directories directly under `specs/`
   (exclude `archive/`, `_archive/`):
   - exact name match wins; otherwise prefix match (`007` → `007-*`);
   - one match → use it;
   - several matches → AskUserQuestion with the matches;
   - no match → **STOP**: "Feature `{arg}` not found in specs/." and list the
     available feature folders. Do not create a new feature folder.
2. **No argument** → read `.specify/feature.json`, field `feature_directory`
   (e.g. `specs/006-fix-payment-link-generation`). If the folder exists → use it.
3. **No argument and no valid `feature.json`** → try the current git branch:
   `git branch --show-current`; pick a `specs/*` folder whose number or name the
   branch references. One clear match → use it, and say so.
4. Still nothing → AskUserQuestion listing the feature folders.
5. **No `specs/` directory at all** → ask the user for a target folder
   (suggest `docs/handoffs/`). Never guess silently.

Tell the user which FEATURE_DIR was chosen and why (argument / feature.json / branch / choice).

### Step 2: Collect facts (do not invent anything)

Gather from the **real state**, not from memory alone:

- `git branch --show-current`, `git status --short`, `git log --oneline -10`
- the base/feature branch relation if clear (`git log --oneline <base>..HEAD`)
- if `FEATURE_DIR/tasks.md` exists: count done/open tasks
  (`- [x]` / `- [ ]`), list the next open task IDs and the current phase
- the list of files changed in this session (from git and from the conversation)
- from the conversation: the goal, what was done, decisions **with reasons**,
  rejected options, problems met and how they were solved, open questions, next steps

If a fact is unknown, write "unknown" — never guess.

### Step 3: Write the snapshot

1. `mkdir -p FEATURE_DIR/handoffs`
2. File name: `FEATURE_DIR/handoffs/YYYY-MM-DD-HHMM-<slug>.md`
   (`date +%Y-%m-%d-%H%M`; `<slug>` = kebab-case from `--title` or the goal, max ~5 words).
3. Fill `templates/handoff-template.md`. Rules:
   - **Self-contained:** a reader with no chat history must understand it.
     Use full paths (`path/to/file.py:42`), exact commands, exact error texts.
   - **Facts over story:** short bullets, no narrative.
   - **Decisions keep their "why".** A decision without a reason will be re-argued.
   - **Next steps are concrete:** the first step must be doable right away.
   - Write in the language of the conversation with the user.
   - **No secrets:** never copy tokens, passwords, keys, `.env` values or personal data.
     Write "see `.env` / secret manager" instead.
4. Do not modify other files in FEATURE_DIR (spec.md, plan.md, tasks.md stay untouched).

### Step 4: Report

Print:
- the path of the new file;
- how FEATURE_DIR was chosen;
- a 3–5 line summary (state + first next step);
- the resume line: `Read <path> and continue from "Next steps".`
- that the file is **not committed** (unless `--commit`).

### Step 5: Commit (only with `--commit`)

1. Current branch is the protected base (`main`, `master`, `development`) → **STOP**:
   refuse to commit on the base branch.
2. Stage **only** the new snapshot file: `git add <path>`.
3. Commit: `docs(handoff): <feature> — <slug>` + the co-author trailer.
4. **Do not push.**

## Resuming in a new chat

The user starts a new chat and says: `Read specs/<feature>/handoffs/<file>.md and continue.`
The agent must then:
1. read the snapshot;
2. check that git state still matches (branch, last commit) — if not, say what changed;
3. start from the first item of "Next steps".

## Notes

- Several snapshots per feature are normal; the newest file (by name) is the current one.
- The snapshot is a working note, not a spec. Long-lived decisions belong in
  `spec.md` / `plan.md` / ADRs — the snapshot can list them under "Promote to docs".
