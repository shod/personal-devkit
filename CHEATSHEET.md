# Plugins cheat-sheet

Working reference for `shod/personal-devkit` (GitHub, **public**, default branch `master`).
Marketplace hosts 3 plugins: `workflow-kit`, `laravel-kit`, `flutter-kit`.

---

## Mental model
- **Marketplace** = a git repo with `.claude-plugin/marketplace.json` at its root. Ours: `shod/personal-devkit`.
- **Plugin (kit)** = one entry in that marketplace; bundles skills + agents (+ commands/hooks/MCP).
- **Nothing is copied into a consuming repo** — Claude Code loads plugins by reference, so there is no drift.
- Installed plugin skills are **namespaced**: `laravel-kit:configuring-horizon`, `flutter-kit:flutter-best-practices`.

---

## Everyday commands (interactive, inside Claude Code)
| Goal | Command |
|---|---|
| Open plugin manager UI | `/plugin` |
| Register the marketplace | `/plugin marketplace add shod/personal-devkit` |
| Install a kit | `/plugin install workflow-kit@personal-devkit` |
| Pull latest marketplace metadata | `/plugin marketplace update` |
| Update an installed kit | `/plugin update workflow-kit` |
| Disable a kit (just for me) | `/plugin disable workflow-kit@personal-devkit` |
| Re-enable a kit | `/plugin enable workflow-kit@personal-devkit` |
| Remove marketplace / uninstall | via the `/plugin` menu → Back/Manage |

CLI (non-interactive) equivalents:
```
claude plugin marketplace add shod/personal-devkit --scope project
claude plugin install laravel-kit@personal-devkit --scope project
```

---

## Install scope — which to pick
| Scope | Writes to | Who gets it | Use for |
|---|---|---|---|
| **project** | `<repo>/.claude/settings.json` (committed) | everyone who clones the repo | **default for horoscope** — travels with the repo |
| **user** | `~/.claude/settings.json` | only you, in **every** project on this machine | your personal toolkit in a repo you don't want to commit it to (e.g. the company repo) |
| **local** | `<repo>/.claude/settings.local.json` (gitignored) | only you, only this repo | personal on/off toggles, experiments |

Rule of thumb: **personal projects → project scope. Company repo → user scope** (don't impose your toolkit on teammates / the company repo).

---

## Declarative form (instead of `/plugin install`)
Same effect as project scope — commit this to `<repo>/.claude/settings.json`:
```json
{
  "extraKnownMarketplaces": {
    "personal-devkit": { "source": { "source": "github", "repo": "shod/personal-devkit" } }
  },
  "enabledPlugins": {
    "workflow-kit@personal-devkit": true,
    "laravel-kit@personal-devkit": true,
    "flutter-kit@personal-devkit": true
  }
}
```
New machine/collaborator: clone → trust workspace → accept the install prompt (Claude Code ≥ v2.1.195), or run `/plugin marketplace add shod/personal-devkit`.

---

## The sync loop (improve a skill everywhere)
```
# in C:\Projects\personal-devkit
git add . && git commit -m "improve <skill>" && git push     # master

# in each consuming project (inside Claude Code)
/plugin marketplace update
/plugin update <kit>
```
No file copies → no conflicts to reconcile.

---

## Add a NEW skill to an existing kit
1. `plugins/<kit>/skills/<new-skill>/SKILL.md` (frontmatter: `name`, `description`).
2. Optional: `references/`, `scripts/`, `templates/` beside it.
3. `git commit && push` → `/plugin update <kit>` in projects.
No manifest edit needed — skills are auto-discovered under the plugin.

## Add a NEW agent to a kit
`plugins/<kit>/agents/<name>.md` (frontmatter: `name`, `description`, `tools`). Commit + update.

## Add a NEW kit (plugin) to the marketplace
1. `plugins/<kit>/.claude-plugin/plugin.json` (`name`, `version`, `description`).
2. Add an entry to root `.claude-plugin/marketplace.json` → `plugins[]` with `source: "./plugins/<kit>"`.
3. Commit + push → in projects `/plugin marketplace update` then `/plugin install <kit>@personal-devkit`.

---

## What is NOT in this marketplace (by design)
- **Upstream spec-kit** (`speckit-*`) → installed per project via `specify init/upgrade`; never vendored here.
- **Project-specific experts** (a repo's backend/frontend experts, e2e, find-slot) → live in that repo's `.claude/agents/`, not here.
- Reason + full inventory: see `MAPPING.md`.

---

## Troubleshooting
- **Kit doesn't show up** → `/plugin marketplace update`; confirm the repo/branch is reachable:
  `curl -fsSL https://raw.githubusercontent.com/shod/personal-devkit/master/.claude-plugin/marketplace.json`
- **Skill not triggering** → remember the namespace (`<kit>:<skill>`); check it's enabled in `/plugin`.
- **Private repo later** → consuming machines need read access (SSH key on the account, or a PAT). Public = no auth.
- **Auth on push** → this repo uses HTTPS/SSH like any GitHub repo; SSH key must be attached to the `shod` account.
- **Disable a kit only for me in a shared repo** → `/plugin disable <kit>@personal-devkit` (writes `settings.local.json`).

---

## Cross-host reminder
Marketplace lives on **GitHub** (`shod/personal-devkit`); projects live on **GitLab**. Independent —
Claude Code just needs read access to the GitHub repo. Keep company-authored content in mind before
making the repo private/public (see the IP note in `MAPPING.md`).
