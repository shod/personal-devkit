# workflow-kit

Framework-agnostic dev workflow skills + workflow agents.

## Skills (populated)
- **graphify** — codebase → knowledge graph (query/path/explain); update after edits
- **skill-generator** — author new Agent Skills (validator, templates, examples)
- **review** — framework-agnostic AI code review (spec, correctness, security, performance,
  tests); stack rules come from `review.rules`; phase-runner runs it once per phase
- **analytic-bft** — business-requirements analyst (FR/NFR extraction, graphify-grounded)
- **task-work** — implement one task from tasks.md
- **task-runner-parallel** — run [P] tasks in isolated worktrees
- **phase-runner** — orchestrate a whole phase (parallel + sequential) ⚠ see prereq
- **time-log** — record task execution time
- **todo-plans** — todo-plan management
- **squash-commits** — squash a branch into one commit vs a base; `--scope=phase` makes one commit per phase (used by phase-runner)
- **git-cleanup** — remove merged `task/*`, `phase/*`, `worktree-*` branches and worktrees (plan first, never force)
- **project-setup** — create or update `.claude-project.json` (detects the stack, uses examples, adds only missing keys, writes after a yes)
- **hand-off** — save a session snapshot into `specs/<feature>/handoffs/` (active feature or by name)
- spec-kit OVERLAY (yours, not upstream): **graphify-spec-context**,
  **sh-speckit-archive**, **sdd-archive**, **spec-prepare** (runs
  specify → (clarify) → plan → tasks → analyze in one command, with a gate after each stage)

## Agents (populated)
- **task-runner** — full single-task lifecycle (branch → implement → commit → merge)
- **task-runner-parallel** — parallel [P]-task execution across worktrees

## ⚠ Prerequisite for phase-runner (and the task-* flow)
`phase-runner` reads a **`.claude-project.json`** at the consuming repo root for:
- `paths.phase_branch_prefix`, `paths.task_branch_prefix`
- `commands.*` (Docker/tests/lint/artisan — so agents never hand-write them)
- `checks` (recommended) — the `commands` keys that phase CHECKS runs, in order, for any
  stack: `"checks": ["format", "lint", "typecheck", "test"]`. Without it, the legacy list
  `pint` → `phpstan` (changed files) → `test` is used (only keys that exist).
- `review` (optional) — the phase review step. Without it, phase-runner runs
  `workflow-kit:review` in `report` mode:
  ```json
  "review": {
    "mode": "report",
    "rules": ["laravel-kit:laravel-review"],
    "providers": [
      { "skill": "workflow-kit:review", "args": "--base={base} --phase={N} --out={out} --auto", "can_block": true },
      { "skill": "mattpocock-skills:code-review", "args": "{base} — spec: {spec_path}" }
    ]
  }
  ```
  - `mode`: `off` | `report` (never stops) | `block` (STOP on CRITICAL from `can_block` providers).
  - `autofix` / `max_fix_rounds` (`block` only): an agent fixes CRITICAL findings, then CHECKS
    and REVIEW run again, up to `max_fix_rounds` (default 2). Without `autofix`, phase-runner asks.
  - `rules`: stack-rule skills that `workflow-kit:review` loads (for example `laravel-kit:laravel-review`).
  - `providers`: review skills to run, each in its own subagent. Reports go to
    `specs/<feature>/reviews/phase-<N>-<skill>.md` and into the phase commit.
    No `providers` key → only `workflow-kit:review`. An empty list `[]` → no review.
    A provider skill must be model-invocable, accept the diff base in its args, and not ask questions.

Phase branches are named **`{phase_branch_prefix}{N}-{feature-slug}`** (e.g.
`phase/3-007-bookings-export-fields`), where the slug is the spec directory holding the
`tasks.md` being run. The slug makes the name unique per feature, so a leftover `phase/3`
from another spec can never be reused by accident.

Run **`/project-setup`** to create the file. The full format is in
`skills/project-setup/references/schema.md`; ready configs are in `skills/project-setup/examples/`.
phase-runner checks the file at start and offers `/project-setup` when it is missing.

Projects without that file: either add one, or use `task-work` directly (it does
not require it). horoscope does NOT have `.claude-project.json` yet — add one
before using phase-runner there.

## NOT here
Upstream `speckit-*` — installed per project via `specify init/upgrade`; never vendor.
