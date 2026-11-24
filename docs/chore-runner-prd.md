# PRD: `chore-runner` agent for workflow-kit

**Plugin**: workflow-kit (current version 0.11.0)
**Status**: draft, ready for implementation
**Date**: 2026-11-13
**Origin**: phase-runner run of feature 019 in `shod-brain`. Routine commands ran on the main
(Opus) model and used its context.

## 1. Problem

Many workflow-kit steps are mechanical. They run fixed commands and report the output:

- git housekeeping (list, classify and delete merged branches);
- quality gates (`mise run check`, project `checks` commands);
- `graphify update .`;
- status and time logs.

Today these steps run in the main session, usually on Opus. This has two costs:

1. **Money and speed.** A strong model runs commands that need no judgment.
2. **Context.** Long command output (for example `mise run check`, ~300 lines) goes into the main
   context and pushes out useful history.

`task-finisher` already shows the pattern: a Haiku agent for commit and time log. There is no
general agent for other routine commands.

## 2. Goal

Add one general agent, `chore-runner`, to workflow-kit. It runs routine commands on Haiku and
returns a short result. Skills delegate mechanical steps to it. Decisions and user approval stay
in the main session.

### Success criteria

| ID | Criterion |
|----|-----------|
| SC-1 | `workflow-kit:chore-runner` is available in every project that has workflow-kit installed. |
| SC-2 | `git-cleanup` runs its git commands through `chore-runner`. The main session sees only the plan and the final report. |
| SC-3 | No destructive command (`git branch -D`, `git reset --hard`, `git push`, `--no-verify`) runs without an explicit name of the target in the prompt. |
| SC-4 | A failed check is reported with its raw error. `chore-runner` never edits source code to fix it. |

## 3. Non-goals

- No change to `task-coder` (writes code, needs a stronger model).
- No change to `task-finisher` in this release. It already runs on Haiku.
- No change to review agents. Review needs judgment.
- No parallel or background orchestration.

## 4. Requirements

### 4.1 Agent file

| ID | Requirement |
|----|-------------|
| FR-1 | Add `plugins/workflow-kit/agents/chore-runner.md`. |
| FR-2 | Frontmatter: `name: chore-runner`, `model: haiku`, a `description` that names the routine work (git housekeeping, checks, graphify, status/time logs). |
| FR-3 | Allowed tools: Bash, PowerShell, Read, Grep, Glob. No Edit or Write for source code. Follow the format of `task-finisher.md`. |
| FR-4 | The agent runs only the commands that the prompt or the calling skill names. |
| FR-5 | The agent never runs `git branch -D`, `git reset --hard`, `git push`, `git clean -f` or `--no-verify`, unless the prompt names the exact command and target. |
| FR-6 | If a command fails, the agent reports the exit code and the raw error lines, and stops. It does not try to fix code. |
| FR-7 | The report format: one line per command with exit code, then the key raw lines (counts, errors, summary lines). Final line: `CHORE_RESULT: ok` or `CHORE_RESULT: failed <command>`. |
| FR-8 | The agent cannot ask the user questions. It never decides on approval. |

Draft agent body:

```markdown
---
name: chore-runner
description: >-
  Runs routine mechanical commands with no design decisions: git housekeeping,
  quality checks (`mise run check`, project `checks`), `graphify update .`,
  status and time logs. Reports raw results. Never edits source code.
model: haiku
tools: Bash, PowerShell, Read, Grep, Glob
---

# Chore Runner

You run routine commands for the main session.

1. Run only the commands that the prompt or the calling skill names.
2. Do not use `git branch -D`, `git reset --hard`, `git push`, `git clean -f`
   or `--no-verify`, unless the prompt names the exact command and target.
3. Do not change source code. If a command fails, report it and stop.
4. Report each command with its exit code and the key raw output lines.
5. End with `CHORE_RESULT: ok` or `CHORE_RESULT: failed <command>`.
```

### 4.2 `git-cleanup` skill

| ID | Requirement |
|----|-------------|
| FR-9 | Step 1–3 (resolve the feature branch, list candidates, classify merged/unmerged): the main session starts `chore-runner` with these commands. `chore-runner` returns the classified lists. |
| FR-10 | Step 4 (plan and approval) stays in the main session. The main session shows the plan and asks the user. |
| FR-11 | Step 5 (remove worktrees, `git branch -d`): the main session starts `chore-runner` with the exact list of approved worktrees and branches. |
| FR-12 | The explicit force-delete path (`git branch -D <name>`) passes the exact branch names to `chore-runner`, one name per approved branch. |
| FR-13 | The `yes` argument (pre-approval of merged deletions) keeps its current meaning. |
| FR-14 | Add an optional rule for `backup/*-presquash` branches. They are not in the default families. They are deleted only on an explicit request with the feature name, because `git branch -d` refuses them (squash). |

### 4.3 Candidates for later releases

Do not implement now. Record them in the CHANGELOG "Next" section or in a follow-up doc.

| Skill | Step for `chore-runner` | Note |
|-------|------------------------|------|
| `phase-runner` / `task-git` CHECKS | run the `checks` commands | The verdict stays in the main session, based on the raw lines that `chore-runner` returns. |
| `phase-runner` Step 8 | `graphify update .` | Only when `graphify-out/` exists. |
| `time-log` | whole skill | Candidate for `context: fork` (see 4.4). |
| `project-status` | `mise run status` | User-level skill, not in the plugin. |

### 4.4 Whole-skill delegation (to verify)

Claude Code skills may support frontmatter fields that run the whole skill in a subagent
(for example `context: fork` and `agent: <name>`, or `model:`). **Verify the exact field names in
the current Claude Code docs before use.** Use this only for skills that never ask the user.

## 5. Constraints

- **The plugin cache is overwritten on update.** Change only the source in this repo
  (`plugins/workflow-kit/...`), never `~/.claude/plugins/cache/...`.
- **A duplicate `git-cleanup` exists.** The user-level copy `~/.claude/skills/git-cleanup/SKILL.md`
  is different from the plugin copy. After the release, delete the user-level copy, so only the
  plugin version is used.
- **Subagents cannot start subagents.** A skill that runs inside a forked context cannot start
  `chore-runner`. Only the main session starts it.
- **Haiku makes weaker judgments.** All classification that leads to deletion must use exact git
  checks (`git merge-base --is-ancestor`), not model reasoning.

## 6. Implementation steps

1. Create a branch from `main` (for example `feat/chore-runner`).
2. Add `plugins/workflow-kit/agents/chore-runner.md` (FR-1 – FR-8).
3. Update `plugins/workflow-kit/skills/git-cleanup/SKILL.md` (FR-9 – FR-14).
4. Add `chore-runner` to the roles table in the workflow-kit `README.md`.
5. Bump the version in `plugins/workflow-kit/.claude-plugin/plugin.json` to 0.12.0.
6. Add a `CHANGELOG.md` entry. List the 4.3 candidates under "Next".
7. Commit with Conventional Commits (`feat(workflow-kit): add chore-runner agent`).
8. Install the new version in a test project.
9. Delete the user-level copy `~/.claude/skills/git-cleanup/`.

## 7. Acceptance test

Run in a project that has merged `phase/*` branches (for example `shod-brain`).

1. Run `/git-cleanup`.
2. Check that the main session starts `workflow-kit:chore-runner` for the listing.
3. Check that the plan shows merged and unmerged branches correctly.
4. Answer "yes".
5. Check that `chore-runner` deletes only the merged branches with `git branch -d`.
6. Check that the final report lists the kept branches.
7. Run `/git-cleanup` with an unmerged branch present. Check that it is kept and reported.
