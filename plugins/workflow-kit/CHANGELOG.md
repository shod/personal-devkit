# Changelog — workflow-kit

All notable changes to this plugin are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/);
this plugin adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.3.0]

### Fixed

- **`phase-runner` (1.1 → 1.2): data loss — the skill wiped its own tasks.md completion
  marks.** Step 7.5 rewrote `- [ ] {TASK_ID}` → `- [x] {TASK_ID}` after the phase merge but
  never committed `tasks.md`, so the marks stayed in the working tree. The skill's own
  out-of-scope cleanup (Step 6.1, Step 7.4d, Rules → "Verifying task completion") restores
  every tracked file outside the *current task's* scope — and `tasks.md` is never in any
  task's scope — so the next phase's `git checkout HEAD -- specs/*/tasks.md` reverted them.

  *Observed in production:* Phase 1 marked T001–T004 `[x]` uncommitted; Phase 2's cleanup
  reverted `tasks.md`; T001–T004 silently went back to `[ ]` while Phase 2's own (committed)
  marks survived — Phase 1 looked unrun.

  Three changes: marking now ends with an explicit
  `git commit -m "chore(phase-{N}): mark … complete"` on the feature branch; all three
  restore sites exclude `$TASKS_PATH` (`specs/*/tasks.md`) alongside `.claude/worktrees/`
  and `.claude/agent-memory/`, and **flag** a dirty `tasks.md` (agent scope violation, or a
  prior phase's uncommitted marks) instead of discarding it; the final report gains a
  `tasks.md marks:` row showing the commit sha or `✗ NOT COMMITTED`.

  No other skill was affected — the restore-without-exclusion pattern exists only in
  `phase-runner`.

### Added

- **`phase-runner`: multiple phases in one invocation.** `$ARGUMENTS` now accepts a list
  (`/phase-runner 4 5 6`, `Phase 4, Phase 5`) and inclusive ranges (`3-5`). Phases run in
  order, each fully completing (CHECKS → merge → marks) before the next starts, each on its
  own phase branch, with `$TASKS_PATH` resolved once. The run stops before the remaining
  phases on an INCOMPLETE task, a CHECKS failure or a merge conflict, and reports which
  phases completed and which were not attempted.
- **`phase-runner`: `--auto` / `--yes` / `-y` / `--no-confirm`** to skip the start-of-phase
  confirmation. Passing more than one phase implies it — asking per phase defeats the point
  of queueing them. Auto-confirm suppresses **only** that prompt: STOP points (errors,
  INCOMPLETE tasks, failed CHECKS, merge conflicts, ambiguous spec) still halt and ask.

## [0.2.0]

### Changed

- **`phase-runner` (1.0 → 1.1): parallel execution is now OPT-IN.** By default every
  pending task of a phase — including `[P]`-marked ones — runs **sequentially** on the
  phase branch via `task-runner`: no worktrees, no task branches, no merge-back. The old
  behaviour is available behind the explicit **`--parallel`** flag
  (`/phase-runner 4 --parallel`). A `[P]` marker in tasks.md is now advisory metadata
  ("no ordering dependency"), not a trigger.

  *Why:* in real monorepo runs, worktree parallelism produced a durable class of failures
  — merge-back races, false "success" on empty or wrong commits, and shared-file conflicts
  surfacing only at merge — for very little wall-time gain (small tasks; worktree setup on
  Windows and `RefreshDatabase` test runs dominate). The value of `phase-runner` is the
  batching (one branch, one CHECKS run, one merge), which is orthogonal to parallelism.

- **Task-completion verification hardened.** A task now counts as done only when the
  `feat({TASK_ID})` commit is present on the phase branch **AND** its diff versus the
  feature branch is non-empty **AND** at least one changed file falls inside the task's
  declared SCOPE. An empty commit, or one touching only out-of-scope files, is
  `✗ INCOMPLETE` and stops the run. Applies to both sequential and parallel tasks.

- **`task-runner-parallel` (agent + skill 1.0 → 1.1)** documented as opt-in, now calls the
  helper scripts for merge-back and verification, and its Phase 2 file-conflict check no
  longer skips silently when a task's SCOPE cannot be extracted — it warns that a parallel
  conflict is not guaranteed to be excluded and requires explicit confirmation.

- **`task-git` (1.0 → 1.1)** — contract unchanged (`--scope=phase`,
  `--phase-action=CREATE|CHECKS|MERGE`). Phase-scope CREATE now stops on a pre-existing
  phase branch instead of failing opaquely, and MERGE reports new migrations in its output.

### Added

- **`scripts/verify-task.{sh,ps1}`** — `{FEATURE_BRANCH} {PHASE_BRANCH} {TASK_ID}
  [SCOPE_GLOB…]`; exit 0 when the commit exists, the diff is non-empty and it touches the
  scope; exit 1 on verification failure; exit 2 on usage/repo errors. Read-only and
  idempotent.
- **`scripts/merge-back.{sh,ps1}`** — `{PHASE_BRANCH} {BRANCH} {TASK_ID}`; checkout +
  `git merge --no-ff`, refuses `development`/`master`/`main`, aborts on conflict and lists
  the conflicting files (exit 1) so the phase branch is never left mid-merge; re-runs are
  no-ops.

  Both ship in bash and PowerShell (the primary environment is Windows/PowerShell, and the
  Bash tool is also used). `phase-runner` and `task-runner-parallel` now call them and read
  the **exit code** rather than interpreting git state in prose; a manual fallback is
  documented for when the scripts cannot run.

- **Stale phase-branch guard** (`phase-runner` Step 5.55) — `{phase_branch_prefix}{N}` is a
  flat, reusable name, so a `phase/4` left over from an earlier feature is common. It is now
  detected (via merge-base distance and whether its log references this spec's task IDs) and
  renamed to `…-stale` before the new phase branch is created, so commits never land on an
  obsolete base. The old branch is renamed, never deleted.

- **Post-merge migration step** (`phase-runner` Step 7.5.3) — when a phase adds
  `database/migrations/*.php`, the dev database is migrated via `commands.migrate` with an
  explicit warning to the user. Phase tests run on `RefreshDatabase`, which migrates only a
  throwaway schema and leaves the dev database behind.

### Unchanged (invariants)

Branch-per-phase is intact: ONE phase branch per phase, CHECKS run once, exactly ONE
`--no-ff` merge into the feature branch, `--squash` prohibited, and tasks marked `[x]` only
after that merge succeeds.

## [0.1.2] and earlier

Not tracked in this file; see git history.
