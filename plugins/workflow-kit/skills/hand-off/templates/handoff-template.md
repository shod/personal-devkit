# Hand-off: {title}

> Snapshot: {YYYY-MM-DD HH:MM} · Feature: `{FEATURE_DIR}` · Branch: `{branch}`
> Resume: read this file, check "Git state", start from "Next steps" #1.

## 1. Goal

{What we are trying to achieve and why. 2–4 lines.}

## 2. Current state

{Where the work is right now: done / in progress / blocked. One short paragraph or bullets.}

## 3. Done in this session

- {change} — `{path}` ({commit sha if committed})

## 4. Decisions (with reasons)

| Decision | Why | Rejected options |
|---|---|---|
| {decision} | {reason} | {option — why not} |

## 5. Problems and solutions

- **{problem}** — {exact error / symptom} → {how it was solved, or "open"}

## 6. Open questions

- {question} — {who decides / what is needed to answer}

## 7. Next steps

1. {first concrete step — doable right away; exact command or file}
2. {...}

## 8. Git state

- Branch: `{branch}` (base: `{base}`)
- Last commits:
  ```
  {git log --oneline -5}
  ```
- Uncommitted changes: {none | list from git status --short}

## 9. Tasks progress

{If tasks.md exists: Phase {N}; done {x}/{total}; next open: T0xx, T0yy. Otherwise: "no tasks.md".}

## 10. Key files

- `{path}` — {why it matters}

## 11. Promote to docs (optional)

- {long-lived decision that should move to spec.md / plan.md / ADR}
