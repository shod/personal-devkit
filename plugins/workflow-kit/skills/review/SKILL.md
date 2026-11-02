---
name: review
description: >-
  Framework-agnostic AI code review for spec-kit work. Checks spec compliance,
  correctness, security, performance, test quality and maintainability, plus stack rules
  from `.claude-project.json` → `review.rules` (for example `laravel-kit:laravel-review`).
  Use /review for uncommitted changes, /review T012 for one task, or
  /review --base=<branch> for a branch or a whole phase. phase-runner calls it once per
  phase. Reports only, never changes code.
argument-hint: "[task-id] [--base=<ref>] [--phase=<N>] [--out=<path>] [--auto]"
allowed-tools: Bash(git *) Read Grep Glob Write Skill
metadata:
  author: olegs
  version: "3.0"
  category: quality
model: opus
---

# Code Review

This skill reviews code that a spec-kit task or phase changed.
It writes a report. It **never changes code**.

The skill does not depend on a framework.
Stack rules come from other skills, listed in `.claude-project.json` → `review.rules`.

## Arguments

| Argument | Meaning |
|---|---|
| (none) | Review the uncommitted changes. |
| `T012` | Review the files of task T012. |
| `--base=<ref>` | Review `git diff <ref>...HEAD`. phase-runner uses this mode. |
| `--phase=<N>` | Phase number. Used only for the report title and file name. |
| `--out=<path>` | Write the report to this file. Without it, print the report only. |
| `--auto` | Do not ask questions. Use defaults and continue. |

## Step 1: Find the scope

1. If `--base` is present, run `git rev-parse --verify <ref>`.
   If it fails, **STOP** with `REVIEW_ERROR: bad base ref <ref>`.
2. Get the changed files:
   - With `--base`: `git diff --name-only <ref>...HEAD`.
   - With a task ID: find the task in `specs/*/tasks.md`. Use the file paths in the task text.
     If the task has no paths, use the files of the commits whose message contains the task ID.
   - With no arguments: `git diff --name-only` and `git diff --cached --name-only`.
3. Remove from the list: lock files, generated files, binary files, and files in `vendor/`,
   `node_modules/`, `build/`, `dist/`.
4. If the list is empty, **STOP** with `REVIEW_ERROR: empty diff`.

## Step 2: Load the context

1. Find the feature folder.
   Read `.specify/feature.json` first. If it does not exist, use the folder of the `tasks.md`
   that holds the task, or the folder that matches the branch name.
2. Read `spec.md`, `plan.md` and `tasks.md` from the feature folder, if they exist.
   For a phase review, note the tasks of that phase.
3. Read `.specify/memory/constitution.md`, if it exists.
4. Read `.claude-project.json` → `review.rules`, if it exists.
   For each entry, call the **Skill tool** with that skill name to load its rules.
   If a rules skill is not installed, write `Rules not loaded: <name>` in the report and continue.
5. Read the project standards files, if they exist: `CLAUDE.md`, `AGENTS.md`,
   `CODING_STANDARDS.md`, `CONTRIBUTING.md`.

## Step 3: Review

1. Read the full diff: `git diff <ref>...HEAD` (or the task commits, or the working tree).
2. For each changed file, read the full file when the diff alone is not enough.
3. Apply [checklist.md](references/checklist.md).
4. Apply the rules from the loaded rules skills.
5. Apply the constitution. A violation of a NON-NEGOTIABLE rule is always **CRITICAL**.
6. For each finding, record: category, severity, file and line, problem, recommendation.

Rules for findings:
- Report a finding only when you can point to a file and a line.
- Do not report what a linter or formatter already checks (for example Pint or PHPStan).
- Do not report style preferences that the project does not document.
- If you are not sure, use severity **INFO** and write "possible" in the problem text.

## Step 4: Write the report

1. Fill in [report-template.md](templates/report-template.md).
2. If `--out` is present, write the report to that path with the Write tool.
   This is the only file that the skill may write.
3. Print a short summary in chat: the counts and the list of CRITICAL findings.
4. Print this line as the **last line** of the output, exactly in this format:

```
REVIEW_RESULT: critical=<N> warning=<N> info=<N> report=<path or ->
```

phase-runner reads this line. Do not change its format.

## Severity levels

| Level | Meaning | Action |
|-------|---------|--------|
| CRITICAL | A bug, a security hole, data loss, or a feature that does not do what the spec says | Must fix before merge |
| WARNING | A probable problem or a clear violation of project rules | Fix soon |
| INFO | An improvement or a possible problem | Optional |

## Rules

### No code changes (NON-NEGOTIABLE)

- Do **not** edit, fix or format any project file.
- Do **not** run commands that change files or git state. Only read commands are allowed:
  `git diff`, `git log`, `git show`, `git rev-parse`.
- The only file that the skill writes is the report file from `--out`.

### General

- Write the report in **English**.
- With `--auto`, do not ask questions. If something is missing, write it in the report and continue.
