---
id: personal-devkit
project: personal-devkit
type: code
status: active
stage: workflow-kit 0.11.0 in PR #6, waiting for merge and a real-phase test
repo: https://github.com/shod/personal-devkit
---

# personal-devkit

## Last step
Prepared workflow-kit 0.11.0 with the fixes F1–F7 from the shod-brain runs and opened PR #6. The fixes: commit scope case, case-insensitive verify-task, time-log without php, short commits, no background shells, pre-flight checks.

## Next step
Merge PR #6 and update the plugin to 0.11.0 in Claude Code. Then run `/phase-runner` on a small phase in shod-brain with `commit.scope_case: "lower"` and check that the finisher commits on the first try.

## Blocker
—
