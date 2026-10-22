# shod-speckit

Oleg's extensions to GitHub Spec Kit. Adds a product layer above the specs and keeps every spec
traceable to it:

```
constitution → intent → PRD → specify → clarify → plan → tasks → analyze → implement
                 ▲                 │                                  │
                 └── IDs (G-n, SC-n, US-n, FR-n) ◄── ## Traceability ─┘ (checked by analyze)
```

## Skills

| Skill | What it does |
|---|---|
| **intent** | Creates or updates `docs/intent.md` (why, for whom, goals `G-n`, success criteria `SC-n`, out of scope `OOS-n`) and registers the intent and PRD paths in `CLAUDE.md` |
| **speckit-preset** | Installs, updates, checks or removes the Spec Kit preset below in the current project |

## The Spec Kit preset (`skills/speckit-preset/preset/`)

A regular Spec Kit preset (id `shod-speckit`, requires Spec Kit ≥ 0.8.0). It composes on top of
the core files instead of editing them, so `specify` upgrades do not wipe it.

| Target | Strategy | Effect |
|---|---|---|
| `spec-template` | `append` | Every new `spec.md` ends with `## Traceability` (Intent / PRD / Deferred) |
| `speckit.analyze` | `append` | Extra detection pass G: missing or unfilled Traceability, dangling IDs, PRD items without requirements or tasks |

Core updates to the spec template and the analyze command still flow in: the preset adds, never replaces.

## Use in a project

```text
/plugin install shod-speckit@personal-devkit
/shod-speckit:speckit-preset            # install the preset (once per project)
/shod-speckit:intent                    # write docs/intent.md + Product context in CLAUDE.md
/speckit-specify ...                    # specs now include ## Traceability
```

Commit `.specify/presets/` and the changed agent files (for Claude: `.claude/skills/speckit-analyze/`).

## Update flow

1. Change the preset here → bump `preset.version` in `preset.yml` **and** the plugin version → CHANGELOG → push.
2. In each project: `/plugin update shod-speckit`, then `/shod-speckit:speckit-preset`
   (it sees the version change and reinstalls: `preset remove` + `preset add --dev`).

## After upgrading Spec Kit

`specify integration upgrade <agent>` stops with "files modified since installation": the preset
re-composed the analyze command. This is expected. Run it with `--force`; Spec Kit re-applies
installed presets afterwards. Then check with `/shod-speckit:speckit-preset status`.

## Tested

Spec Kit 1.1.4.dev0, Claude integration (skills mode): install, `resolve` composition, new spec
contains Traceability, analyze contains pass G, reinstall of a new version, `integration upgrade --force`
keeps the preset.

## Relation to workflow-kit

workflow-kit keeps the existing spec-kit overlay skills (`graphify-spec-context`, `sh-speckit-archive`,
`sdd-archive`). New Spec Kit process extensions go here.
