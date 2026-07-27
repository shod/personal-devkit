# Changelog — workflow-kit

All notable changes to this plugin are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/);
this plugin adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
