---
name: project-setup
description: >-
  Create or update `.claude-project.json` — the project config that phase-runner,
  task-work, task-git and review read (branch prefixes, commands, review settings).
  Detects the stack (Laravel, Flutter, Python, Node, monorepo), proposes a config from the
  examples, shows it, and writes it only after a yes. In an existing config it only adds
  missing keys and never changes existing ones. Also sets the `checks` list that phase
  CHECKS runs. Use when the user says "setup project",
  "create .claude-project.json", "configure review", or when phase-runner reports that
  the config is missing. Use --check to report only.
argument-hint: "[--check] [--review-only]"
allowed-tools: Read Glob Grep Write Edit Bash(git *) AskUserQuestion
metadata:
  author: olegs
  version: "1.0"
  category: setup
model: sonnet
---

# Project Setup

This skill creates or updates `.claude-project.json` in the repository root.
The format of every key is in [schema.md](references/schema.md).
Ready configs are in [examples/](examples/).

## Arguments

| Argument | Meaning |
|---|---|
| (none) | Create the config, or add missing keys to the existing config. |
| `--check` | Report the missing keys. Do not write anything. |
| `--review-only` | Add or update only the `review` section. |

## Safety rules (read first)

- **Never** write the file without a "yes" from the user.
- **Never** change or delete an existing key. Only add missing keys.
- **Never** invent commands. Take each command from a file in the repo
  (`composer.json`, `package.json`, `pyproject.toml`, `Makefile`, `docker-compose.yml`,
  `pubspec.yaml`) or from the user. If you cannot find a command, leave it out and list it
  under "Not found" in the summary.
- Do not commit. The user commits the file.

## Step 1: Read the current state

1. Run `git rev-parse --show-toplevel`. Work in that folder.
2. If `.claude-project.json` exists, read it. Keep its key order and its `_comment*` keys.
3. If the file has invalid JSON, **STOP** and show the parse error. Do not overwrite it.

## Step 2: Detect the stack

Check these files. A repo can have more than one stack (monorepo). Check the root and
`apps/*`, `backend/`, `frontend/`, `mobile/`.

| File | Stack | Example | Review rules |
|---|---|---|---|
| `artisan` + `composer.json` with `laravel/framework` | Laravel | `laravel-sail.json` | `laravel-kit:laravel-review` |
| `pubspec.yaml` with `flutter:` | Flutter | `flutter.json` | `flutter-kit:flutter-best-practices` |
| `pyproject.toml` with `fastapi` | FastAPI | `python-uv.json` | `python-kit:fastapi-best-practices` |
| `pyproject.toml` without `fastapi` | Python | `python-uv.json` | `python-kit:python-best-practices` |
| `package.json` | Node / TypeScript | `minimal.json` | none |

More details for Laravel:
- A `docker-compose.yml` service `laravel.test` means Sail. Use `docker compose ... exec` commands.
- `vendor/bin/pint` exists → add `pint`. `phpstan.neon` exists → add `phpstan`.

More than one stack → use `monorepo-laravel-flutter.json` as the base. Put the path of each
app in `paths` (`backend`, `mobile`, …).

## Step 3: Build the proposal

1. Start from the matching example in `examples/`.
2. Replace each command with the real command for this repo (paths, compose file, service name).
3. Set `project` to the repo folder name.
4. Add the `checks` list: the `commands` keys that phase CHECKS runs, in order.
   - Order: formatter (one that fixes files) → linter / analyzer → type check → test suite.
   - Use only keys that exist in the proposed `commands`.
   - Laravel: `["pint", "phpstan:changed", "test"]`. With 500+ legacy PHPStan errors, use a
     command with `{FILES:*.php}` or a script with `{BASE}`, not the full `phpstan`.
   - Flutter: `["flutter:format", "flutter:analyze", "test"]`.
   - Python (uv): `["format", "lint", "typecheck", "test"]`.
   - Monorepo: the checks of every app.
5. Add the `review` section:
   - `mode`: `report`.
   - `rules`: the review rules of every detected stack (table above).
   - `providers`: leave the key out. Then phase-runner uses `workflow-kit:review`.
6. Detect the commitlint scope rule:
   1. Find the commitlint config in the repo root: `commitlint.config.*`, `.commitlintrc*`,
      or the `commitlint` key in `package.json`.
   2. If the config has `scope-case` with `lower-case`, propose
      `"commit": { "scope_case": "lower" }`.
   3. If there is no config or no such rule, do not add the `commit` key. The default is `"upper"`.
   4. Show the found rule in the summary: `Commit:     scope_case lower (commitlint scope-case)`.
7. If the config exists, the proposal is only the **missing keys**.
   An existing config without `checks` gets a proposed `checks` list built from its own `commands` keys.
8. With `--review-only`, the proposal is only the `review` section.

## Step 4: Show and confirm

1. Print a summary:
   ```
   Stack:      Laravel (Sail, ./apps/api) + Flutter (./apps/mobile)
   File:       .claude-project.json  (new | update: N keys to add)
   Add:        paths.phase_branch_prefix, commands.test:bg, checks, review
   Checks:     pint → phpstan:changed → test
   Commit:     scope_case lower (commitlint scope-case)
   Not found:  commands.phpstan (no phpstan.neon)
   ```
2. Print the full JSON to add.
3. With `--check`, stop here.
4. Ask with AskUserQuestion: "Write this config?" Options: "Write", "Cancel".

## Step 5: Write

1. Write the file with 2-space indentation and a final newline.
2. Read the file back and check that it is valid JSON.
3. Tell the user:
   - Review the commands, especially Docker and test commands.
   - Add `commands.test:guard` if the project has fast architecture tests.
   - Commit the file.
