# workflow-kit

Framework-agnostic dev workflow skills + workflow agents.

## Skills (populated)
- **graphify** — codebase → knowledge graph (query/path/explain); update after edits
- **skill-generator** — author new Agent Skills (validator, templates, examples)
- **review** — AI code review (checklists + report template)
- **analytic-bft** — business-requirements analyst (FR/NFR extraction, graphify-grounded)
- **task-work** — implement one task from tasks.md
- **task-runner-parallel** — run [P] tasks in isolated worktrees
- **phase-runner** — orchestrate a whole phase (parallel + sequential) ⚠ see prereq
- **time-log** — record task execution time
- **todo-plans** — todo-plan management
- **squash-commits** — squash a branch into one commit vs a base
- spec-kit OVERLAY (yours, not upstream): **graphify-spec-context**,
  **sh-speckit-archive**, **sdd-archive**

## Agents (populated)
- **task-runner** — full single-task lifecycle (branch → implement → commit → merge)
- **task-runner-parallel** — parallel [P]-task execution across worktrees

## ⚠ Prerequisite for phase-runner (and the task-* flow)
`phase-runner` reads a **`.claude-project.json`** at the consuming repo root for:
- `paths.phase_branch_prefix`, `paths.task_branch_prefix`
- `commands.*` (Docker/tests/lint/artisan — so agents never hand-write them)

Projects without that file: either add one, or use `task-work` directly (it does
not require it). horoscope does NOT have `.claude-project.json` yet — add one
before using phase-runner there.

## NOT here
Upstream `speckit-*` — installed per project via `specify init/upgrade`; never vendor.
