---
name: orca-router
description: >-
  Cross-project flow router: runs a feature through the SDD flow
  (spec-prepare → approve → phase-runner → checks → cross-model review → fix loop →
  UI check → human acceptance) as an Orca coordinator, one Orca worktree per feature,
  a chosen agent/model per stage. Reads the flow from flows/feature.yaml (+ project
  override .claude/flow.yaml) and the queue from PROJECT_STATUS.md. Use when the user
  says "/orca-router run", "прогони фичу через flow", "запусти очередь", "orca-router status".
argument-hint: "run <project> <idea|NNN> | queue [<project>] | status | resume <feature_slug>"
allowed-tools: Bash PowerShell Read Grep Glob Edit Write AskUserQuestion
model: opus
metadata:
  author: shod
  version: "0.1-draft"
  category: orchestration
---

# Orca Router — SDD flow coordinator over Orca

The router is a **coordinator**. It never writes product code, never edits specs and
never merges into main/development. It starts workers, checks their results itself,
moves the feature to the next stage and asks the human at the gates.

```
orca-router (this session, opus)                 Orca
├─ orca orchestration run-create            one Run per router session
└─ per feature:
    ├─ worktree  flow-{feature_slug}        created by the first worker (new-child)
    ├─ stage = task-create + worker          claude/opus, claude/sonnet, codex …
    ├─ pass_when checks                      run by the router in the worktree
    ├─ gate-create                           approve-spec, accept, escalations
    └─ flow-log.md + PROJECT_STATUS.md       visible state for the human
```

## Commands

| Command | What it does |
|---|---|
| `/orca-router run <project> <idea\|NNN>` | Run one feature through the flow. |
| `/orca-router queue [<project>]` | Take items with `status: ready` from the `## Queue` of PROJECT_STATUS.md (one project or all projects of the dashboard), run them one after another (max 1 active feature per project). |
| `/orca-router status` | `orca orchestration task-list --json` + the last line of each `flow-log.md` → table: feature, stage, waiting for. |
| `/orca-router resume <feature_slug>` | Continue after a stop: read `flow-log.md`, start from the last unfinished stage. |

## Queue format (PROJECT_STATUS.md)

```markdown
## Queue
- [ready] 009 Export bookings to CSV — flow: feature
- [ready] idea: Push notification when a phrase is due — flow: feature
- [running] 008-phrase-sync — stage: cross-review
- [waiting] 007-onboarding — gate: accept
- [done] 006-settings-screen
```
The router changes only the `[status]` and the `stage:` / `gate:` tail of its own items.

## Algorithm

### 1. Load
1. Read `flows/feature.yaml` (next to this file). If the project has `.claude/flow.yaml`,
   merge it over the default **by stage `id`** (shallow merge of the stage keys).
2. Skip stages with `enabled: false`.
3. Read `.claude-project.json` of the project. Missing → STOP, suggest `/project-setup`
   (phase-runner needs it anyway).
4. Resolve `models.*` aliases to `--agent` / `--model`.

### 2. Start the Run (once per session)
```
orca orchestration run-create --objective "orca-router: {project} {feature}" --json
```

### 3. Run a stage — `type: worker`
1. Render the stage prompt: `run` (a slash command) or `prompt` (text), with placeholders.
   Add the standard worker footer:
   > Work only in this worktree. Do not merge into main/development, do not push.
   > When finished, report `worker_done` exactly once with `--outcome succeeded|failed`
   > and the list of modified files.
   For `readonly: true` add: *Do not change or commit files, except the report file.*
2. Create the task:
   ```
   orca orchestration task-create --spec "<rendered prompt>" --task-title "{feature_slug}: {stage.id}" --json
   ```
3. Start the worker.
   - **First worker of the feature** — creates the worktree:
     ```
     orca orchestration worker-start --task <taskId> --worktree new-child \
       --name flow-{feature_slug} --agent <agent> [--model <model> --effort <effort>] --setup run --json
     ```
     Save `worktreeId` (from `worker-show --dispatch <id> --json`) into `flow-log.md`.
   - **Next workers** — in the SAME worktree, through low-level dispatch:
     ```
     orca terminal create --worktree id:<worktreeId> --command "<agent cli + model flag>" --json
     orca terminal wait --terminal <handle> --for tui-idle --timeout-ms 60000 --json
     orca orchestration dispatch --task <taskId> --to <handle> --inject --json
     ```
     ⚠ DRAFT: confirm on the first real run that this is the right way to put a supervised
     worker into an existing worktree (`orca skills get orchestration --full`). If
     `worker-start` gets a `--worktree id:<id>` form, use that instead.
4. Wait:
   ```
   orca orchestration check --wait --types worker_done,escalation,question --timeout-ms 900000 --json
   ```
   - `question` → answer from the flow/spec if the answer is there; otherwise ask the human
     (AskUserQuestion) and reply. Never invent product decisions.
   - `escalation` → treat as `on_fail`.
   - Process every message of a delivery, then `check --ack <deliveryId>`.
   - Total wait > `limits.worker_timeout_min` → `worker-stop`, treat as `on_fail: ask`.
5. After `worker_done`: `worker-read --dispatch <id> --limit 50`, then `worker-release`.

### 4. Run a stage — `type: gate`
```
orca orchestration gate-create --task <taskId> --question "<rendered question>" --options '<options json>' --json
```
Wait until it is resolved (`orca orchestration gate-list --task <taskId> --json`, poll every
few minutes, or the human answers in this chat — then `gate-resolve` it yourself).
Go to `on.<resolution>`. A comment given with the answer is passed to the next stage prompt.

### 5. Run a stage — `type: router`
Do it yourself in the feature worktree: `checks` = run `.claude-project.json → checks` in
order with the same rules as phase-runner CHECKS (raw output, exit code, failure markers;
`:bg` pairs for long suites). `finish` = see the stage `steps`.

### 6. Check `pass_when` — yourself
Every check is done by the router with its own commands in the worktree:
| check | how |
|---|---|
| `outcome: succeeded` | `worker_done --outcome` |
| `files_exist` | `Test-Path` / `test -f` |
| `file_not_contains` | `Select-String` / `grep -F` |
| `open_tasks_only_manual` | every `- [ ]` line in tasks.md is a task that phase-runner reported as `⊘ MANUAL` |
| `git_clean` | `git status --short` has no tracked changes |
| `report_line` | read the **last** line with `prefix` from the report file |
| `all_checks: green` | step 5 result |

**Never accept a worker's prose ("done", "all green") as a pass.** Same rule as phase-runner.

### 7. Failure routing and loopbacks
- `on_fail: fix` → run `fix` with `{failure_report}` = the report/output of the failed
  stage and `{came_from}` = that stage id. Route by the `/speckit.fix` category (stage `route`).
- `on_fail: ask` → gate with options `retry`, `rework` (→ prepare), `stop`.
- Every return to an earlier stage increases `loopbacks`. When it reaches
  `limits.max_loopbacks` (or `fix` ran `max_fix_rounds` times) → no more automatic
  returns: open a gate `continue | stop` with the full history.

### 8. State — visible to the human
Append one line per event to `{spec_dir}/flow-log.md` in the worktree (commit it together
with the stage results):
```
2026-11-14 14:02 | implement | worker claude/opus d-123 | succeeded | phases 1-4 merged
2026-11-14 14:40 | cross-review | worker codex d-131 | critical=2 → fix (loopback 1/2)
```
Update the queue item in PROJECT_STATUS.md (`[running] … — stage: X`, `[waiting] … — gate: accept`)
and run `node scripts/report-status.mjs` from the project, so the Projects Dashboard shows it.

## Rules
- One active feature per project; features of different projects can run in parallel
  (each in its own worktree).
- Workers of the same feature run one at a time (stages are sequential).
- The router never merges to main/development and never opens an MR/PR.
- Secrets, tokens and client code never go into flow-log.md or PROJECT_STATUS.md.
- Work project (dubz, GitLab, Jira): same flow, but the status goes to the work dashboard
  (`report-status` target `work`).
