---
name: spec-prepare
description: >-
  Prepare a feature for implementation with one command: run the main Spec Kit
  skills in sequence — speckit-specify → (optional speckit-clarify) →
  speckit-plan → speckit-tasks → speckit-analyze — with a check gate after
  each stage. Runs speckit-clarify automatically when spec.md has
  [NEEDS CLARIFICATION] markers, or always with --clarify. Stops on a missing
  artifact, markers left after clarify, or CRITICAL analyze findings.
  Use when the user says "prepare the feature", "run specify, plan, tasks and
  analyze", "full spec-kit prep", "подготовь фичу к имплементации", or wants
  the whole spec-kit preparation chain in one run. Resume from a later stage
  with --from=<stage>. Does not implement code and does not commit.
argument-hint: "<feature description> [--clarify] [--from=specify|clarify|plan|tasks|analyze] [--to=specify|clarify|plan|tasks|analyze] [--yes]"
allowed-tools: Skill Read Glob Grep Bash PowerShell AskUserQuestion TodoWrite
metadata:
  author: Oleg Shmyk
  version: "1.0"
  category: speckit-workflow
---

# Spec Prepare — Spec Kit preparation chain

Runs the Spec Kit preparation stages in a fixed order:

| # | Stage     | Skill             | Artifact it must produce            |
|---|-----------|-------------------|-------------------------------------|
| 1 | specify   | `speckit-specify` | `{FEATURE_DIR}/spec.md`             |
| 2 | clarify   | `speckit-clarify` | updated `spec.md` (**optional**)    |
| 3 | plan      | `speckit-plan`    | `{FEATURE_DIR}/plan.md`             |
| 4 | tasks     | `speckit-tasks`   | `{FEATURE_DIR}/tasks.md`            |
| 5 | analyze   | `speckit-analyze` | analysis report (read-only, no file)|

> **clarify is optional.** It runs only when one of these is true:
> - `spec.md` has open `[NEEDS CLARIFICATION` markers before the plan stage.
>   Then clarify runs **automatically**, without a question, also with `--yes`;
> - the user gives `--clarify`;
> - `--from=clarify` or `--to=clarify`.
>
> In all other cases the run skips clarify and marks it ⏭.

> **Why tasks comes before analyze.** `speckit-analyze` checks consistency between
> `spec.md`, `plan.md` and `tasks.md`. It needs `tasks.md`, so it always runs last.

This skill is an orchestrator only. It does not change the upstream `speckit-*`
skills, and it does not write spec content itself. Each stage does its own work.
Hooks from `.specify/extensions.yml` (for example `graphify-spec-context` before
specify) run as usual inside each stage.

## Arguments

Parse `$ARGUMENTS`:
- `--clarify` — always run the `clarify` stage after `specify`, also when `spec.md` has no markers.
- `--from=<stage>` — start at this stage. Default: `specify`.
- `--to=<stage>` — stop after this stage. Default: `analyze`.
- `--yes` / `-y` / `--auto` — do not pause between stages. Gates still stop the run.
- All other text — the **feature description**. Required only when the run includes `specify`.

Stage names in order: `specify`, `clarify`, `plan`, `tasks`, `analyze`.

## Algorithm

### Step 1: Parse the arguments

1. Remove the flags from `$ARGUMENTS`. Save `FROM`, `TO`, `AUTO` and `CLARIFY`.
   Set `CLARIFY = true` if `--clarify` is present, or if `FROM` or `TO` is `clarify`.
2. Save the remaining text as `DESCRIPTION`.
3. If `FROM` comes after `TO` — **STOP**: "`--from` must come before `--to`."
4. If the run includes `specify` and `DESCRIPTION` is empty:
   - Use the feature description from the current conversation, if there is a clear one.
   - Otherwise **STOP** and ask: `/spec-prepare <feature description>`.

### Step 2: Preflight

1. Make sure that `.specify/` exists at the repo root.
   If it does not exist — **STOP**: "Spec Kit is not initialized. Run `specify init` first."
2. Make sure that the `speckit-*` skills of the range are available
   (`speckit-clarify` only if `CLARIFY` is true). Look in the available
   skills list, `.claude/skills/speckit-*`, or `.claude/commands/speckit.*`.
   If one is missing — **STOP** and name it. Tell the user to run `specify upgrade`.
3. If `FROM` is not `specify`:
   - Read `.specify/feature.json`, field `feature_directory` → `FEATURE_DIR`.
   - If the file or the folder does not exist — **STOP** and ask which feature to use.
   - Make sure that the input artifacts of the earlier stages exist
     (`clarify` and `plan` need `spec.md`; `tasks` needs `spec.md` + `plan.md`;
     `analyze` needs all three). If one is missing — **STOP** and name it.
   - If `FROM` is `plan` and `spec.md` has `[NEEDS CLARIFICATION` markers:
     set `FROM = clarify` and `CLARIFY = true`. Tell the user that clarify runs first.
   - If `FROM` is `tasks` or `analyze` and `spec.md` has markers: do not run clarify.
     Show the markers as a warning in the summary.
4. Create a TodoWrite list with one item for each stage in the range `FROM`..`TO`.
   Leave out `clarify` if `CLARIFY` is false.
5. Show the plan to the user: the stages, the feature description or `FEATURE_DIR`.

### Step 3: Run the stages

Run each stage in the range in order. Run only one stage at a time.
Skip `clarify` if `CLARIFY` is false.
For each stage:

1. Mark the stage `in_progress` in TodoWrite.
2. Invoke the stage skill with the Skill tool:
   - `specify` → `skill: "speckit-specify"`, `args: DESCRIPTION`.
   - `clarify` → `skill: "speckit-clarify"`, no args.
     The clarify skill asks the user questions one by one. Ask each one and wait for the answer.
   - `plan` → `skill: "speckit-plan"`, no args.
   - `tasks` → `skill: "speckit-tasks"`, no args.
   - `analyze` → `skill: "speckit-analyze"`, no args.
3. Follow the instructions of the stage skill until it is complete.
   If the stage skill asks the user a question, ask it and wait for the answer.
4. Run the gate for this stage (Step 4).
5. If the gate passes, mark the stage `completed`.
6. If `AUTO` is false and another stage follows, ask with AskUserQuestion.
   Exception: do not ask when the specify gate found markers. Then clarify starts at once.
   "Stage `<stage>` is done. Continue with `<next stage>`?"
   Options: "Continue (Recommended)", "Stop here".
   If the user selects "Stop here" — go to Step 5.

### Step 4: Gates

A gate failure stops the run. Do not go to the next stage.
Tell the user the reason and the command to resume (Step 5).

**After specify:**
1. Read `.specify/feature.json` again → `FEATURE_DIR`.
   The specify stage creates a new feature, so the value is new.
2. Make sure that `{FEATURE_DIR}/spec.md` exists and is not empty.
3. Search `spec.md` for `[NEEDS CLARIFICATION`.
4. If markers remain — the gate passes. Set `CLARIFY = true`.
   Add `clarify` to TodoWrite if it is not there.
   Tell the user the number of markers and that clarify runs next.
   Do not ask. Do not pause, also when `AUTO` is false.
5. If `TO` is `specify`, the run ends here. Give the resume command `--from=clarify`.

**After clarify:**
1. Make sure that `{FEATURE_DIR}/spec.md` still exists and is not empty.
2. Search `spec.md` for `[NEEDS CLARIFICATION` again.
   If markers remain — **STOP**. List them.
   Tell the user to answer them, then resume with `--from=clarify` or `--from=plan`.

**After plan:**
1. Make sure that `{FEATURE_DIR}/plan.md` exists and is not empty.
2. Search `plan.md` for `NEEDS CLARIFICATION` and for a failed Constitution Check
   (`ERROR`, `FAIL`, or a violation without a justification).
   If found — **STOP** and list them.

**After tasks:**
1. Make sure that `{FEATURE_DIR}/tasks.md` exists.
2. Make sure that it has at least one task line (`- [ ] T001` style).
   If there are no tasks — **STOP**.
3. Count the phases. A phase is a heading line in `tasks.md` that starts with
   `## Phase <N>` (for example `## Phase 3: User Story 1 (Priority: P1)`).
   For each phase, save the number, the title and the number of task lines under it.
   Save the total as `PHASE_COUNT`.
4. If `PHASE_COUNT` is 0 — do not stop. Show "phases: not found" in the summary as a warning,
   because `phase-runner` needs `## Phase <N>` headings.

**After analyze:**
1. Read the severity table of the analysis report.
2. If there is a **CRITICAL** finding — **STOP**. List the CRITICAL findings.
   Tell the user to fix the artifacts, then resume with `--from=analyze`.
3. If there are only HIGH, MEDIUM or LOW findings — the gate passes.
   Show the HIGH findings in the summary as warnings.

> **Do not fix artifacts automatically.** `speckit-analyze` is read-only. This skill is
> read-only too. If the user asks for fixes, do them as a separate step, outside this run.

### Step 5: Summary

Show a short summary:

```markdown
## Spec prepare: <feature name>

**Feature folder:** `{FEATURE_DIR}`
**Stages:** specify ✅ · clarify ⏭ · plan ✅ · tasks ✅ · analyze ✅   (⏭ skipped, ⛔ stopped)
**Phases:** <PHASE_COUNT>
**Tasks:** <N> tasks

| Phase | Title | Tasks |
|-------|-------|-------|
| 1     | Setup | 4     |
| 2     | Foundational | 6 |
| …     | …     | …     |
**Analyze:** <C> critical · <H> high · <M> medium · <L> low

**Warnings:** <HIGH findings, or "none">

**Next step:** `/phase-runner 1`, or all phases: `/phase-runner 1-<PHASE_COUNT>`
(or the resume command, if the run stopped)
```

Show the phases block only if `tasks.md` exists. If the run stopped before tasks,
leave it out.

If the run stopped, give the exact resume command:
`/spec-prepare --from=<stage>`.

## Rules

- Run the stages in the fixed order. Never skip a stage inside the range.
- Never run `speckit-implement`. This skill only prepares the feature.
- Never commit, push or create branches yourself. Branches come only from `speckit-specify`.
- Never edit `spec.md`, `plan.md` or `tasks.md` yourself. Only the stage skills write them.
- Report the real result of each gate. Do not mark a stage `completed` if its gate failed.

## Done When

- [ ] Each stage in the range ran, or the run stopped at a gate with a clear reason.
- [ ] Each artifact in the range exists in `{FEATURE_DIR}`.
- [ ] The summary shows the stage status, the number of phases, the analyze counts and the next command.
