---
name: speckit-preset
description: >-
  Install, update, check or remove the shod-speckit Spec Kit preset in the current
  project. The preset appends an intent/PRD Traceability section to every new spec.md
  and a traceability pass to /speckit-analyze, without editing core Spec Kit files, so
  it survives `specify` upgrades. Use when setting up Spec Kit in a project, after
  updating the shod-speckit plugin, after `specify integration upgrade`, or when the
  user asks about the traceability preset.
argument-hint: "[install|status|remove] [--force]"
allowed-tools: Bash(specify *) Bash(git *) Bash(grep *) Bash(ls *) Bash(cat *) Read AskUserQuestion
metadata:
  author: shod
  version: "0.1.0"
  category: speckit-workflow
---

# shod-speckit preset manager

The preset ships inside this skill: `PRESET_DIR = <this skill's base directory>/preset`
(Claude Code shows the base directory when the skill loads). Its id is `shod-speckit`.

`specify preset add --dev` **copies** `PRESET_DIR` into `.specify/presets/shod-speckit/`,
so the project does not depend on the plugin cache path afterwards.

This skill **never commits**. The user commits the result.

## Arguments

Parse `$ARGUMENTS`:
- `install` (default) — install, or update when the bundled version differs.
- `status` — read-only report.
- `remove` — uninstall the preset.
- `--force` — reinstall even when versions match.

## Step 0: Preconditions

1. `specify version` must work. Missing → STOP: "Spec Kit CLI not found. Install it: `uv tool install specify-cli --from git+https://github.com/github/spec-kit.git`".
2. Spec Kit must be **≥ 0.8.0** (composition strategies). Older → STOP and suggest `specify self upgrade`.
3. `.specify/` must exist in the repo root. Missing → STOP: "Not a Spec Kit project. Run `specify init --here` first."
4. Read the bundled version from `PRESET_DIR/preset.yml` (`preset.version`).
5. Read the installed version from `.specify/presets/.registry` (JSON, `presets["shod-speckit"].version`).
   No registry or no entry → not installed.

## Step 1: Act

### status
Report: bundled version, installed version (or "not installed"), and the output of
`specify preset resolve spec-template`. Then run the checks from Step 2 and stop.

### install
| State | Action |
|---|---|
| Not installed | `specify preset add --dev "PRESET_DIR" --priority 5` |
| Installed, same version, no `--force` | Report "up to date", go to Step 2 |
| Installed, different version, or `--force` | `specify preset remove shod-speckit`, then `specify preset add --dev "PRESET_DIR" --priority 5` |

`preset add` refuses to overwrite an installed preset, so the remove step is required.
Priority 5 keeps this preset above default-priority (10) presets.

### remove
Confirm with AskUserQuestion, then `specify preset remove shod-speckit`.
Existing `spec.md` files keep their Traceability sections. Only new specs and the analyze command change.

## Step 2: Verify (install and status)

1. `specify preset resolve spec-template` must list `[append] shod-speckit` in the composition chain.
2. The analyze command in the agent directory must contain the traceability pass:
   `grep -rl "Detection Pass G: Traceability" .claude .agents .github .gemini .cursor 2>/dev/null`
   No match → warn: "analyze command was not re-composed; run `specify integration upgrade <agent> --force`".
3. Product docs: check whether `CLAUDE.md` (or `AGENTS.md`) contains a "Product context" block.
   Missing → suggest running the `intent` skill of this plugin. Traceability works without it, but the
   agent will not know where the intent and PRD live.

## Step 3: Report

- What was done (installed / updated old → new / up to date / removed).
- Verification results.
- `git status --short` for `.specify/presets/` and the agent directory, with a reminder to commit them.

## Notes for upgrades

- `specify integration upgrade <agent>` **stops** with "files modified since installation" because the
  preset re-composed the analyze command. This is expected. Run it with `--force`: Spec Kit re-applies
  installed presets after the upgrade (verified on 1.1.x). Then run this skill with `status`.
- After updating the shod-speckit plugin (`/plugin update shod-speckit`), run this skill with
  `install` in each project to pick up the new preset version.
