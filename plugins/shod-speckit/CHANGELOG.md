# Changelog — shod-speckit

All notable changes to this plugin are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/);
this plugin adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0]

### Added

- **Spec Kit preset `shod-speckit` 0.1.0** (requires Spec Kit ≥ 0.8.0), shipped inside the
  `speckit-preset` skill. Composes on top of core files, so `specify` upgrades do not wipe it.
  - `spec-template` (append): every new spec gets `## Traceability` — Intent IDs, PRD items, Deferred.
  - `speckit.analyze` (append): detection pass G — missing or unfilled Traceability (MEDIUM),
    dangling IDs (HIGH), PRD items claimed but without requirements or tasks (HIGH),
    deferrals without a target feature (LOW).
- **`speckit-preset` skill**: install / update (remove + add on version change) / status / remove,
  with verification via `specify preset resolve` and the composed analyze command. Never commits.
- **`intent` skill**: creates or updates `docs/intent.md` from a template with stable IDs
  (`G-n`, `SC-n`, `OOS-n`; never renumbered, retired items struck through) and an idempotent
  "Product context" block in `CLAUDE.md`. Never commits.
