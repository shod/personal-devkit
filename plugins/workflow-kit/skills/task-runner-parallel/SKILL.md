---
name: task-runner-parallel
description: >-
  Parallel execution of multiple [P]-marked tasks from tasks.md.
  Accepts a list of TASK_IDs and runs each task in an isolated git worktree
  via a separate task-runner agent. OPT-IN ONLY: from phase-runner this path is
  taken exclusively when it was started with --parallel; invoking this skill
  directly is itself an explicit opt-in.
argument-hint: "<task-id> [<task-id> ...]"
allowed-tools: Agent Read Grep Glob AskUserQuestion
model: sonnet
metadata:
  author: speckit
  version: "1.1"
  category: task-orchestration
---

# Task Runner Parallel Skill

Wrapper around the `task-runner-parallel` agent for invocation via slash command `/task-runner-parallel`.

> **Opt-in only.** Parallel worktree execution is no longer any orchestrator's default.
> `phase-runner` reaches `task-runner-parallel` **only** when the user passed `--parallel`;
> otherwise it runs every task of the phase — `[P]`-marked or not — sequentially on the phase
> branch. Calling `/task-runner-parallel` yourself is an explicit request for parallelism and
> works as before.

## Required argument

`$ARGUMENTS` **MUST** contain one or more TASK_IDs in the format `T***`.

Accepted formats:
- `T015 T016 T018`
- `T015, T016, T018`
- `T015,T016,T018`

If `$ARGUMENTS` is empty — **STOP** and ask user to specify task IDs:
> Specify task IDs: `/task-runner-parallel T015 T016 T018`

## Algorithm

The skill immediately delegates work to the `task-runner-parallel` sub-agent:

```
Agent(
  subagent_type: "task-runner-parallel",
  prompt: "$ARGUMENTS"
)
```

All orchestration, validation, and execution logic is described in `.claude/agents/task-runner-parallel.md`.

## Rules

- The skill is a thin wrapper — **does NOT duplicate** the agent's logic
- Reached from `phase-runner` **only** under `--parallel`; direct invocation is its own opt-in
- Only tasks with the `[P]` marker are run in parallel
- Tasks without `[P]` are run sequentially and only with explicit user consent
- If a task's file SCOPE cannot be determined, the agent warns that a parallel conflict is not guaranteed to be excluded and requires confirmation — it does not skip the check silently
- On one agent's error, the remaining agents continue working
