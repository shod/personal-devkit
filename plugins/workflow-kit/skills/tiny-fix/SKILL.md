---
name: tiny-fix
description: >-
  Lightweight Spec Kit flow for small changes and bug fixes. Writes a short fix plan
  (spec.md) and a one-phase tasks.md in specs/tiny/{YYMMDD}-{slug}/, shows the plan,
  then runs it with phase-runner: one phase branch, task-coder → task-finisher for
  each task, one CHECKS run, one REVIEW, one squash and one merge. Use when the user
  asks for a small fix, a bug fix, a UI tweak, a config change or a small refactor
  (1–5 files, up to 8 tasks), says "tiny fix", "tinyspec", "quick fix", "small task",
  "исправь баг", "мелкая задача", or wants a plan → tasks → implement → review flow
  without the full specify/plan/tasks chain. Recommends /spec-prepare for large work.
argument-hint: "<change or bug description> [--plan-only] [--yes] | --run=<tiny folder or tasks.md> [--yes]"
allowed-tools: Skill Agent Read Write Edit Grep Glob Bash PowerShell AskUserQuestion TodoWrite TaskStop
model: opus
metadata:
  author: Oleg Shmyk
  version: "1.0"
  category: speckit-workflow
---

# Tiny Fix — plan, tasks, phase run, review

A short Spec Kit flow for small changes. It has two parts:

| Part | Who does it | Result |
|------|-------------|--------|
| 1. Plan | this skill (main session) | `specs/tiny/{YYMMDD}-{slug}/spec.md` + `plan.md` + `tasks.md` |
| 2. Run | `phase-runner` (called by this skill) | code on the current branch, one commit, review reports |

```
tiny-fix                                   [skill] opus
├─ preflight (git, .specify, .claude-project.json)
├─ scope check            → too large? recommend /spec-prepare
├─ investigate            (graphify / Grep / Read; root cause for a bug)
├─ write spec.md + plan.md + tasks.md   (one "## Phase 1:" section)
├─ validate the plan files (gate)
├─ show plan → confirm
├─ commit the plan        docs(tiny): …
└─ phase-runner "1 --tasks=… --squash-message=… --auto"
    ├─ task-git CREATE    → phase/1-{YYMMDD}-{slug}
    ├─ for each task: task-coder (sonnet) → task-finisher (haiku)
    ├─ CHECKS (ONCE) → REVIEW (ONCE)
    └─ squash → merge --ff-only into the current branch
```

This skill does not write code. `phase-runner` and its agents write the code.
This skill writes only the three plan files.

**Spec Kit compatibility.** A tiny folder has the same files that `/speckit-implement` needs
(`spec.md`, `plan.md`, `tasks.md`). It is not the active feature: `.specify/feature.json` does
not change. `task-work` points the Spec Kit scripts at the tiny folder with
`SPECIFY_FEATURE_DIRECTORY`, `SPECIFY_FEATURE` and `SPECIFY_FEATURE_NO_PERSIST=1`
(see `task-work` → TASKS OVERRIDE). So a big feature can stay active while a tiny fix runs.

## Arguments

Parse `$ARGUMENTS`:
- `--plan-only` — write the plan files, then stop. Do not commit and do not run anything.
- `--yes` / `-y` / `--auto` — do not ask for confirmation of the plan. Gates still stop the run.
- `--run=<path>` — run an existing tiny plan. `<path>` is the tiny folder or its `tasks.md`.
  Skip Steps 3–6. Use this to resume a stopped run, or to run a plan after `--plan-only`.
- All other text — the **change description** (what to build or what bug to fix).

If there is no `--run=` and the description is empty:
- Use the change description from the current conversation, if there is a clear one.
- Otherwise **STOP** and ask: `/tiny-fix <what to fix or change>`.

## Algorithm

### Step 1: Preflight

1. Make sure that the folder is a git repository: `git rev-parse --show-toplevel`.
   If it fails → **STOP**.
2. Make sure that `.specify/` exists. `task-work` reads `.specify/templates/commands/implement.md`.
   If it does not exist → **STOP**: "Spec Kit is not initialized. Run `specify init` first."
3. Make sure that `.claude-project.json` exists and has `paths.phase_branch_prefix`.
   If not → **STOP** and suggest `/project-setup`. Do not create the file yourself.
4. Run `git status --short`. Ignore untracked files (`??`), `.claude/worktrees/` and
   `.claude/agent-memory/`. If tracked files are modified or staged → **STOP**.
   Tell the user to commit or stash them.
5. Save `CURRENT_BRANCH` = `git branch --show-current`.
   - If it starts with `{phase_branch_prefix}` → **STOP**. Tell the user to check out the
     feature branch first. Then run `/tiny-fix --run=<folder>` again.
   - If it is a main branch (`main`, `master`, `development`, `develop`, or the default branch
     from `git symbolic-ref refs/remotes/origin/HEAD`) → ask with AskUserQuestion
     (also with `--yes`):
     - "Create a new branch (Recommended)" — Step 7 creates `fix/{slug}` (or `feat/{slug}`
       when the change is not a bug fix) before the plan commit. The slug comes from Step 5.
     - "Work on `{CURRENT_BRANCH}`" — the phase merges into this branch.
     - "Stop".

### Step 2: Resume mode (`--run=` only)

1. Resolve `TASKS_PATH`: if `<path>` is a folder, use `<path>/tasks.md`.
2. Make sure that `TASKS_PATH`, and `spec.md` and `plan.md` next to it, exist. If not → **STOP**.
   For a plan from an older `tiny-fix` without `plan.md`: write `plan.md` from the template
   in Step 5 (use `spec.md` as the source), then continue.
3. Read `spec.md` → `TITLE` (the text after `# Tiny Fix:`) and `TYPE` (the `**Type**:` line).
4. Run the gate of Step 6, item 1.
5. If the plan files are untracked or changed, do Step 7 (commit the plan).
6. Go to Step 8.

### Step 3: Check the scope

Decide if the change is a good fit for this flow.

| Good fit | Bad fit (→ `/spec-prepare`) |
|----------|-----------------------------|
| A bug fix with a known or findable place | Several modules or services |
| A UI tweak, a text change, a style change | A new database table or a schema redesign |
| A config or env change | An architecture change, a new integration |
| A small validation, one endpoint, a small refactor | Several user stories, an unclear scope ("improve performance") |
| 1–5 files, up to 8 tasks | More than 5 files or more than 8 tasks |

If the change is a bad fit → ask with AskUserQuestion (also with `--yes`):
- "Use the full flow: `/spec-prepare` (Recommended)" → **STOP**. Print the command with the description.
- "Continue with tiny-fix" → continue. Write `Scope: large — user chose tiny-fix` in `spec.md`.

When in doubt between small and medium, continue with tiny-fix.

### Step 4: Investigate

1. Read `.specify/memory/constitution.md`, `CLAUDE.md` and `AGENTS.md`, if they exist.
   The plan must follow the project rules.
2. If `graphify-out/` exists, query the graph first for the related code
   (Skill `graphify` with a query). Otherwise use Grep and Glob.
3. Read the files that the change touches, and their tests.
4. For a **bug**:
   - Find the root cause. Name the file, the function and the reason.
   - Find how to reproduce the bug in a test.
   - If you cannot find the root cause, ask the user one question with AskUserQuestion.
     Do not write a plan on a guess.
5. Find the test files and the test patterns of the project.
6. Make a list of files: the files to change, the context files, the test files.
   If the list has more than 5 files to change, go back to Step 3 with this new fact.

### Step 5: Write the plan files

1. Make the names:
   - `DATE` = today in `YYMMDD` form (for example `261119`).
   - `slug` = 2–5 English words from the description, kebab-case, `[a-z0-9-]` only.
   - `TINY_DIR` = `specs/tiny/{DATE}-{slug}/`. If the folder exists, add `-2`, `-3`, ….
   - `TYPE` = `fix` for a bug fix, `feat` for new behavior, `refactor`, `chore` or `docs` otherwise.
   - `TITLE` = a short English title, up to 60 characters.
2. Write `{TINY_DIR}/spec.md` from the template below.
3. Write `{TINY_DIR}/plan.md` from the template below.
4. Write `{TINY_DIR}/tasks.md` from the template below.
5. Set `TASKS_PATH` = `{TINY_DIR}/tasks.md`.

**`spec.md` template** (keep it under 80 lines; remove sections that add no value):

```markdown
# Tiny Fix: {TITLE}

**Date**: {YYYY-MM-DD}
**Type**: {TYPE}
**Branch**: {CURRENT_BRANCH}
**Scope**: small

## What

{1–3 sentences: what changes and why.}

## Root Cause            ← bug only

{File, function, the reason. How to reproduce it.}

## Context

| File | Role |
|------|------|
| `path/to/file.ext` | Change — {what} |
| `path/to/other.ext` | Context — {why it matters} |
| `tests/path/to/test.ext` | Change — regression test |

## Requirements

1. {Clear, testable requirement.}
2. {…}

## Plan

1. {Step: what to change and where.}
2. {…}

## Out of Scope

- {What this fix does not do.}

## Done When

- All tasks in `tasks.md` are `[x]`.
- The project checks pass (phase CHECKS).
- The review has no CRITICAL findings, or the user accepted them.
```

**`plan.md` template** (5–20 lines; the Spec Kit scripts require this file):

```markdown
# Plan: {TITLE}

**Spec**: [spec.md](spec.md)   **Tasks**: [tasks.md](tasks.md)

## Technical Context

- **Stack**: {language, framework — from the project, for example "PHP 8.3, Laravel 11"}
- **Tests**: {test framework and the test folder}
- **Constraints**: {project rules from the constitution that apply, or "none"}

## Approach

{2–5 lines: how the fix works and why this way. The full plan steps are in spec.md → Plan.}

## Files

| File | Change |
|------|--------|
| `path/to/file.ext` | {what changes} |
```

Do not add `research.md`, `data-model.md`, `contracts/` or `quickstart.md`.

**`tasks.md` template** (the format that `phase-runner` reads):

```markdown
# Tasks: {TITLE}

**Spec**: [spec.md](spec.md)

## Phase 1: {TITLE}

- [ ] T001 {Imperative description} in `path/to/test.ext`
- [ ] T002 {Imperative description} in `path/to/file.ext`
- [ ] T003 {…} in `path/a.ext`, `path/b.ext`
```

**Task rules:**
- Use one `## Phase 1:` section only. Use IDs `T001`, `T002`, … in order.
- Each task names **at least one file path** in its text. `phase-runner` uses the paths as the
  task SCOPE. A task without a path fails verification.
- One task = one coherent change in 1–3 files. Use 1–8 tasks.
- **Bug fix:** the first task writes a regression test that reproduces the bug. The next task
  fixes the code. (The test is red until the fix. That is correct: CHECKS run after all tasks.)
- Do not add tasks such as "run the tests" or "run the linter". Phase CHECKS do that.
- Do not add manual tasks, except one optional last task for a manual check in the UI.
  Start its text with `Manual:`. `phase-runner` reports it and does not run it.
- Do not use the `[P]` marker. All tasks run in order.

### Step 6: Gate and confirmation

1. Check the plan files:
   - `spec.md`, `plan.md` and `tasks.md` exist in `TINY_DIR` and are not empty.
   - `tasks.md` has exactly one `## Phase 1:` heading.
   - It has 1–8 lines that match `- [ ] T\d{3} `.
   - Each task line (except `Manual:` tasks) has at least one file path.
   If a check fails, fix the file and check again. Do not run a plan that fails the gate.
   In resume mode (`--run=`), do not fix the files yourself: **STOP** and name the failed check.
2. Show the plan to the user:
   ```
   ═══════════════════════════════════════════════════
     Tiny Fix: {TITLE}   ({TYPE})
   ═══════════════════════════════════════════════════
     Folder:   {TINY_DIR}
     Branch:   {CURRENT_BRANCH}  →  phase branch {prefix}1-{DATE}-{slug}
     Root cause: {one line}              ← bug only
     Files:    {N} to change, {M} tests
     Tasks:
       T001 — {description}
       T002 — {description}
     Run:      task-coder → task-finisher per task → CHECKS → REVIEW → squash → merge
   ═══════════════════════════════════════════════════
   ```
3. If `--plan-only` → **STOP** here. Print: "Plan written. Review it, then run
   `/tiny-fix --run={TINY_DIR}`." Do not commit.
4. If `--yes` → print `Auto-confirmed (--yes) — starting.` and go to Step 7.
5. Otherwise ask with AskUserQuestion:
   - "Run the plan (Recommended)" → go to Step 7.
   - "I edit the plan first" → **STOP**. Print the resume command `/tiny-fix --run={TINY_DIR}`.
   - "Stop" → **STOP**. Leave the files. Do not commit.

### Step 7: Commit the plan

`phase-runner` needs a clean tree, and the coder must not see `tasks.md` as a change.
So commit the plan on the current branch before the run.

1. If the user chose "Create branch" in Step 1, run `git checkout -b {fix|feat}/{slug}` now.
   Set `CURRENT_BRANCH` to the new branch.
2. Run:
   ```
   git add {TINY_DIR}
   git commit -m "docs(tiny): plan {slug}"
   ```
3. Run `git status --short`. No tracked changes may remain. If there are → **STOP**.

### Step 8: Run the plan with phase-runner

Call the **Skill tool** with `skill: "phase-runner"` and these args:

```
1 --tasks={TASKS_PATH} --squash-message="{TYPE}: {TITLE}" --auto
```

- `--auto` is correct here: the user confirmed the plan in Step 6.
- Follow the phase-runner instructions in full, until its final report.
  phase-runner keeps all its own STOP points (INCOMPLETE task, failed CHECKS,
  REVIEW stop, merge conflict). Do not skip them.
- Do not write code yourself, also when a task fails. phase-runner decides.
- The review reports go to `{TINY_DIR}/reviews/`. They become part of the phase commit.

### Step 9: Final report

After the phase-runner report, print a short block:

```
═══════════════════════════════════════════════════
  Tiny Fix done: {TITLE}
═══════════════════════════════════════════════════
  Plan:     {TINY_DIR}spec.md
  Commits:  docs(tiny): plan {slug}  +  {TYPE}: {TITLE}
  Branch:   {CURRENT_BRANCH}
  Review:   {TINY_DIR}reviews/   ({C} critical, {W} warnings)
  Manual:   {Manual: tasks, or "none"}
  Next:     git log -2 · /git-cleanup · push / open a PR
═══════════════════════════════════════════════════
```

If phase-runner stopped, print the reason and the resume command instead:
`/tiny-fix --run={TINY_DIR}`. phase-runner finds the existing phase branch and skips the
tasks that are already on it.

## Rules

- **Plan first, then code.** Never start phase-runner without the gate of Step 6.
- **Three plan files only:** `spec.md`, `plan.md` and `tasks.md` in `specs/tiny/{YYMMDD}-{slug}/`.
  Do not write `research.md`, `data-model.md` or contracts.
- **Never change `.specify/feature.json`.** A tiny plan is never the active Spec Kit feature.
- **This skill never writes project code.** Only `phase-runner` agents change code.
- **Do not edit `tasks.md` after Step 7.** phase-runner marks `[x]` itself.
- **No scope creep.** If the investigation shows more than 5 files or 8 tasks, go back to
  Step 3. Do not hide a large change in a tiny plan.
- **Never trust agent prose.** The phase-runner rules apply: the verdict comes from raw
  output, scripts and report files.
- **Never push.** Never merge into a main branch without the user's choice in Step 1.
- **Language:** plan files, commit messages and code comments are in English.

## Done When

- [ ] `spec.md`, `plan.md` and `tasks.md` exist in `specs/tiny/{YYMMDD}-{slug}/` and pass the gate.
- [ ] The plan is committed, or the run stopped with `--plan-only` or by the user.
- [ ] phase-runner ran Phase 1 to its final report, or stopped with a clear reason.
- [ ] The final report shows the plan path, the commits, the review result and the next step.
