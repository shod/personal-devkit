# `.claude-project.json` schema

The file is in the repository root. workflow-kit skills read it.
Keys that start with `_comment` are notes for people and agents. Skills ignore them.

Branch names always come from git (`git branch --show-current`), not from this file.
An old `feature_branch` key is ignored.

## Top level

| Key | Type | Required | Meaning |
|---|---|---|---|
| `project` | string | no | Project name. Used only in reports. |
| `docker` | object | no | Notes about Docker: `compose_file`, `service`, `exec`. Skills do not run these; they run `commands.*`. |
| `paths` | object | **yes** for phase-runner | Folders and branch prefixes. |
| `commands` | object | **yes** for phase-runner | Shell commands that agents run. Agents never write Docker or test commands by hand. |
| `review` | object | no | Phase review settings. |

## `paths`

| Key | Example | Used by |
|---|---|---|
| `phase_branch_prefix` | `"phase/"` | phase-runner: branch `phase/{N}-{feature}` |
| `task_branch_prefix` | `"task/"` | phase-runner `--parallel`, task-git |
| `tasks_md` | `"specs/*/tasks.md"` | phase-runner, task-work |
| `backend`, `mobile`, `frontend`, … | `"./apps/api"` | Notes for agents in a monorepo |

## `commands`

Placeholders: `{FILTER}`, `{BASE}`, `{PATH}`, `{NAME}`, `{ARGS}`. The skill replaces them before it runs the command.
End commands with `2>&1`, so the output includes errors.

| Key | Used by | Meaning |
|---|---|---|
| `test` | task-work, phase CHECKS | Full test suite. |
| `test:filter` | task-work | Tests that match `{FILTER}`. |
| `test:guard` | every task before commit | Fast tests that must stay green (architecture rules). A few seconds. |
| `test:bg` | phase CHECKS | Full suite in the background inside the container. Writes a log. |
| `test:bg:wait` | phase CHECKS | Waits for the `test:bg` log and prints the result. Needs `test:bg`. |
| `pint` | phase CHECKS | Formatter (Laravel). |
| `phpstan` | phase CHECKS, task-work | Static analysis (PHP). |
| `migrate` | phase-runner after merge | Migrates the dev database. |
| any other key | agents | Project commands: `make:*`, `up`, `down`, `flutter:*`, … |

## `review`

| Key | Type | Default | Meaning |
|---|---|---|---|
| `mode` | `"off"` \| `"report"` \| `"block"` | `"report"` | `off`: no review. `report`: write reports, never stop. `block`: STOP on CRITICAL findings. |
| `rules` | string[] | `[]` | Stack-rule skills for `workflow-kit:review`. |
| `providers` | object[] | `workflow-kit:review` only | Review skills that phase-runner runs. `[]` = no review. |

### `review.rules` values

| Stack | Skill | Plugin |
|---|---|---|
| Laravel | `laravel-kit:laravel-review` | laravel-kit ≥ 0.2.0 |
| Flutter | `flutter-kit:flutter-best-practices` | flutter-kit |
| FastAPI | `python-kit:fastapi-best-practices` | python-kit |
| Python | `python-kit:python-best-practices` | python-kit |

The plugin must be installed in the project. If it is not, review writes
`Rules not loaded: <name>` and continues.

### `review.providers[]`

| Key | Type | Meaning |
|---|---|---|
| `skill` | string | Skill name, for example `workflow-kit:review`. |
| `args` | string | Arguments. Placeholders: `{base}`, `{N}`, `{spec_path}`, `{tasks_path}`, `{out}`. |
| `can_block` | bool | `true`: in `block` mode its CRITICAL findings stop the merge. The skill must print a `REVIEW_RESULT:` line. Default `false`. |

A provider skill must:
1. Allow model invocation (no `disable-model-invocation: true`).
2. Take the diff base in its arguments.
3. Not ask questions.
4. Not change code.

Known providers:

| Skill | `args` | Note |
|---|---|---|
| `workflow-kit:review` | `--base={base} --phase={N} --out={out} --auto` | Can block. |
| `mattpocock-skills:code-review` | `{base} — spec: {spec_path}` | Standards + spec. Needs `/setup-matt-pocock-skills` once. |
| `code-review` | `high {base}` | Built into Claude Code. Do not use `max`, `ultra` or `--fix`. |
| `security-review` | `""` | Built into Claude Code. Reviews the current branch. |
