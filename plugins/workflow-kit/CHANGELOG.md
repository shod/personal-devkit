# Changelog — workflow-kit

All notable changes to this plugin are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/);
this plugin adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.6.0]

### Added

- **Per-task guard: fast constitution/architecture tests run before every task commit, even
  with `--defer-checks`.** Root cause: in a multi-phase `phase-runner` run a task added
  `Request::create(...)` to an admin adapter; the project's fast scan test
  (`FilamentWritesThroughDomainTest`) would have flagged it in seconds, but with checks
  deferred it surfaced only in the full suite at phase CHECKS, costing an extra fix-and-rerun
  of the whole suite.
  - New optional project command **`commands.test:guard`** in `.claude-project.json`: the
    project's own short list of fast tests (seconds). The plugin never names test classes —
    each project decides what belongs in its guard. Not defined → nothing changes.
  - `task-work`: under `DEFER_CHECKS=true` Pint / PHPStan / the suite are still skipped, but
    `commands.test:guard` runs after implementing and before the commit. Red → fix inside the
    task scope and re-run; never weaken a guard test; still red → STOP without committing.
    The summary gets a **Guard** line with the raw `Tests:` summary.
  - `task-runner` agent: must not commit while the guard is red; pastes the raw guard line.
  - `phase-runner` (1.5 → 1.6): the task prompt includes the GUARD rule; after each sequential
    task the orchestrator re-runs `commands.test:guard` itself (step 7.4.c2) and STOPs on red —
    the agent's pasted line is not evidence. With `--parallel`, the guard runs once more on
    `PHASE_BRANCH` after the batch's merge-back, because merged changes can combine into a
    violation no single worker saw.
  - Example (Laravel Sail) — keep only fast scan tests; slow `arch()` dependency checks stay in
    the full suite:
    ```json
    "test:guard": "docker compose -f \"./docker-compose.yml\" exec -u sail laravel.test php artisan test --compact --colors=never tests/Arch/FilamentWritesThroughDomainTest.php tests/Arch/NoDirectStatusWritesTest.php tests/Arch/NoCyrillicLiteralsTest.php 2>&1"
    ```

## [0.5.0]

### Changed

- **Full test suite runs detached inside the container when the project supports it.**
  Root cause: during a multi-phase `phase-runner` run the full suite was started as a
  host-side `docker compose exec ... php artisan test` and the host client was killed
  "because the system is running low on memory" — the output was lost and the PHP process
  kept running orphaned in the container. A detached run writing a plain-text log finished
  reliably on every following phase.
  - `task-git` (1.3 → 1.4): phase-scope **CHECKS** now uses `commands.test:bg` (start the
    suite with `exec -d`, log ends with `EXIT=<code>`) + `commands.test:bg:wait`
    (`run_in_background: true`) when both are defined, and falls back to `commands.test`
    otherwise — existing `.claude-project.json` files keep working. A missing `Tests:` line
    counts as a failure. Documents how to stop an orphaned run: `ps` + `kill <PID>`, never
    `pkill -f` with a pattern that also matches its own `sh -c` command line.
  - `phase-runner` (1.4 → 1.5): Step 7.5 describes the new test command selection and forbids
    re-running the full suite in the foreground from the host when `commands.test:bg` exists.
  - `task-runner` agent: tests run through `commands.test:filter` / `commands.test:bg` instead
    of a hard-coded `php artisan test --compact`.
  - Example `.claude-project.json` commands (Laravel Sail):
    ```json
    "test:bg":      "docker compose -f \"./docker-compose.yml\" exec -d -u sail laravel.test sh -c 'rm -f storage/logs/test-run.log; php artisan test --compact --colors=never > storage/logs/test-run.log 2>&1; echo EXIT=$? >> storage/logs/test-run.log'",
    "test:bg:wait": "until grep -q '^EXIT=' storage/logs/test-run.log 2>/dev/null; do sleep 15; done; grep -E 'Tests:|Duration|FAILED|EXIT=' storage/logs/test-run.log"
    ```

### Fixed

- **`task-git` could not run its own quality gates under a strict permission mode.** Its
  `allowed-tools` was `Bash(git *)`, but the phase-scope **CHECKS** action runs the
  project-defined `commands.pint` / `commands.phpstan` / `commands.test` (e.g.
  `docker compose ... exec ...`, `bash bin/phpstan-changed.sh`), which that pattern does not
  cover. It only worked in auto mode. `allowed-tools` is now `Bash PowerShell Read Grep Glob
  AskUserQuestion`: the commands come from each project's `.claude-project.json`, so no fixed
  prefix list can cover them, and PowerShell is needed on Windows. The "No code modification"
  rules of the skill are unchanged.

- **Hardened `phase-runner` / `task-git` against false-positive test status from agent
  prose.** Root-caused by a production incident: a `task-runner` agent whose task was "run
  tests and verify no regressions" reported a task-notification summary of "completed
  successfully" while its own result body embedded raw test output showing real failures
  (`5 failed, 1206 passed`). The orchestrator initially trusted the prose and reported the
  phase green; a real product bug (a service silently failing to persist a row) shipped
  uncaught until an unrelated later re-read of the raw output caught the mismatch.
  - `phase-runner` (1.3 → 1.4): new Rules subsection **"Never trust agent prose for
    pass/fail"** — the pass/fail verdict for any test/lint/build/CHECKS step must come from
    directly parsing raw command output, never from a subagent's prose ("passed",
    "completed successfully", etc.), whether that prose is the task-notification
    `<summary>` line or inside the result body. Added explicit "read the full result body,
    not just the summary line" call-outs at Step 6 (parallel batch) and Step 7 (sequential
    tasks). A mismatch between an agent's prose and its own embedded raw output is now
    treated as a signal to re-verify neighboring tasks that agent touched, not just the one
    contradiction.
  - `task-git` (1.2 → 1.3): phase-scope **CHECKS** action now states explicitly that Pint /
    PHPStan / Tests verdicts must be read from each command's raw captured stdout/stderr
    (failure markers, "N failed" summary lines, non-zero exit codes) — not inferred from
    "the command didn't crash" or paraphrased — since CHECKS is the one place in the chain
    where the gate is authoritative.

## [0.4.0]

### Changed

- **Phase branches are now named `{phase_branch_prefix}{N}-{feature-slug}`** (e.g.
  `phase/3-007-bookings-export-fields`) instead of the flat `{phase_branch_prefix}{N}`
  (`phase/3`). The slug is the basename of the spec directory holding the `tasks.md` being
  run (`$TASKS_PATH`), normalized for a git ref. Because the name now carries the feature, a
  phase branch from a *different* spec can no longer collide with the current run — which was
  the whole reason the 0.3.0 stale-branch guard existed.
  - `phase-runner` (1.2 → 1.3): Step 5.5 derives `FEATURE_SLUG` from `$TASKS_PATH` and builds
    `PHASE_BRANCH`; Step 5.55 shrinks from "detect and rename a foreign `phase/N`" to
    "an existing `PHASE_BRANCH` is *ours* — reuse it (merging the feature branch in if it is
    behind)", plus a non-destructive note when a legacy flat `phase/N` still exists.
  - `task-git` (1.1 → 1.2): new **`--phase-branch=<name>`** flag — `phase-runner` resolves the
    name once and passes it to every phase-scope call (CREATE / COMMIT / CHECKS / MERGE), which
    use it verbatim. Without the flag the skill derives the same `{N}-{slug}` name from the spec
    dir; the bare legacy form is never produced. Phase-scope CREATE still STOPs on a
    pre-existing branch, but now reports it as this feature's interrupted run.
  - `task-runner` / `task-runner-parallel`: `PHASE_BRANCH` from the prompt context must be used
    verbatim, never rebuilt from the phase number; the COMMIT call passes `--phase-branch=`.

  **Migration:** branches created under the old scheme are left alone (never renamed, never
  deleted). A phase interrupted mid-run under the old naming will not be picked up by the new
  name — merge or finish it manually, or re-run the phase on the new branch.

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
