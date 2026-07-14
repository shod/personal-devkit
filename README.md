# personal-devkit

Oleg's personal Claude Code toolkit — one **marketplace** hosting several **plugins**.
Single source of truth. Consumed by any project; improvements sync via `/plugin update`.

## Plugins
| Plugin | Scope | Consumed by |
|---|---|---|
| `workflow-kit` | framework-agnostic (graphify, task/phase runners, spec-kit overlay, time-log, squash) | every project |
| `laravel-kit`  | Laravel (best-practices, Horizon, Pint, larastan) | Laravel backends |
| `flutter-kit`  | Flutter (best-practices, Patrol E2E, flutter-expert) | Flutter frontends |

## Hosting
Personal **GitHub** (this toolkit is personal; the actual projects live on GitLab).
Push this whole repo; it IS the marketplace (`.claude-plugin/marketplace.json` at root).

```
git init
git remote add origin git@github.com:shod/personal-devkit.git
git add . && git commit -m "init personal-devkit marketplace"
git push -u origin main
```

## Consume in a project
In `<project>/.claude/settings.json` (committed) or `~/.claude/settings.json` (personal, all projects):
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
CLI fallback: `/plugin marketplace add shod/personal-devkit`
then `/plugin install flutter-kit@personal-devkit`.

> Cross-host note: the marketplace on GitHub and the consuming project on GitLab
> are fully independent — Claude Code just needs read access to the GitHub repo
> (public, or a PAT for private). Nothing couples the two hosts.

## Update flow
Edit a skill here → commit → push. In each project:
`/plugin marketplace update` then `/plugin update <plugin>`.
No files are copied into consuming repos → no drift.

See MAPPING.md for what goes where (and the IP note on project-1-authored skills).
