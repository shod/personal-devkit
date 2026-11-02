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
| `checks` | string[] | recommended | The `commands` keys that phase CHECKS runs, in order. |
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
| `test` | task-work, phase CHECKS (legacy) | Full test suite. |
| `test:filter` | task-work | Tests that match `{FILTER}`. |
| `test:guard` | every task before commit | Fast tests that must stay green (architecture rules). A few seconds. |
| `{K}:bg` | phase CHECKS | Runs check `K` in the background inside the container. Writes a log that ends with `EXIT=<code>`. |
| `{K}:bg:wait` | phase CHECKS | Waits for the `{K}:bg` log and prints the result. Needs `{K}:bg`. |
| `pint` | phase CHECKS (legacy) | Formatter (Laravel). |
| `phpstan` | phase CHECKS (legacy), task-work | Static analysis (PHP). |
| `migrate` | phase-runner after merge | Migrates the dev database. |
| any other key | agents | Project commands: `make:*`, `up`, `down`, `flutter:*`, … |

## `checks`

A list of `commands` keys. phase-runner runs them once per phase, in this order, before the review and the merge.

```json
"checks": ["format", "lint", "typecheck", "test"]
```

Rules for each key `K`:
- A non-zero exit code, or a failure marker in the output (`N failed`, `N errors`), stops the phase.
- If the check changes files (a formatter), phase-runner commits them as `style(phase-N): K`. This is not a failure.
- If `commands.K:bg` and `commands.K:bg:wait` exist, the check runs in the background (for a long test suite in Docker).
- `{FILES}` in the command → the files changed in the phase. `{FILES:*.php}` → only the changed
  files that match the glob. `{BASE}` → the feature branch.
  Use them to analyse only changed files (for example PHPStan with legacy errors).
  If the file list is empty, the check is skipped.
  ⚠ The paths start at the repo root. If the tool runs in another folder (a monorepo app
  in Docker), the paths do not match. Use a project script that takes `{BASE}` instead.

| Value | Meaning |
|---|---|
| key absent | Legacy list: `pint`, `phpstan` (changed PHP files only), `test` — only the keys that exist in `commands`. |
| `[]` | No checks. |
| list | Run exactly these keys. |

Put fast checks first (formatter, linter), the test suite last.

Note: a formatter in `checks` must **fix** files, not only check them
(`dart format lib test`, `ruff format .`, `pint`), so its changes get committed.
A check-only formatter (`ruff format --check`) fails the phase on any difference.

## `review`

| Key | Type | Default | Meaning |
|---|---|---|---|
| `mode` | `"off"` \| `"report"` \| `"block"` | `"report"` | `off`: no review. `report`: write reports, never stop. `block`: STOP on CRITICAL findings. |
| `rules` | string[] | `[]` | Stack-rule skills for `workflow-kit:review`. |
| `providers` | object[] | `workflow-kit:review` only | Review skills that phase-runner runs. `[]` = no review. |
| `autofix` | bool | `false` | `block` mode only. `true`: on CRITICAL findings, an agent fixes them without a question, then CHECKS and REVIEW run again. `false`: phase-runner asks first. |
| `max_fix_rounds` | int | `2` | The maximum number of fix rounds per phase. After that, phase-runner asks: stop or merge anyway. |

### What happens on a CRITICAL finding

| `mode` | Result |
|---|---|
| `report` | The phase merges. The finding is only in the report. |
| `block` | STOP. Choice: fix automatically (up to `max_fix_rounds`), stop and fix by hand, or merge anyway. |

After "stop and fix by hand": commit the fix on the phase branch, check out the feature branch,
and run `/phase-runner N` again. The run finds the phase branch, skips the tasks that are already
on it, and runs CHECKS and REVIEW again.

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
