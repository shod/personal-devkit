---
name: task-runner-parallel
description: >-
  Parallel execution of multiple [P]-marked tasks from tasks.md.
  Accepts a list of TASK_IDs and runs each task in an isolated git worktree
  via a separate task-runner agent. Use when you need to execute several
  independent tasks simultaneously.
argument-hint: "<task-id> [<task-id> ...]"
allowed-tools: Agent Read Grep Glob AskUserQuestion
model: sonnet
metadata:
  author: speckit
  version: "1.0"
  category: task-orchestration
---

# Task Runner Parallel Skill

Wrapper around the `task-runner-parallel` agent for invocation via slash command `/task-runner-parallel`.

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
- Only tasks with the `[P]` marker are run in parallel
- Tasks without `[P]` are run sequentially and only with explicit user consent
- On one agent's error, the remaining agents continue working
