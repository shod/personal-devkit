---
name: intent
description: >-
  Create or update the product intent document (docs/intent.md) — the step before the
  PRD and Spec Kit specs: why we build it, for whom, desired outcome, measurable
  success criteria, boundaries — with stable IDs (G-n, SC-n, OOS-n) that specs reference
  in their Traceability section. Also registers the intent and PRD paths in CLAUDE.md.
  Use when starting a new product or project, when the user wants to write, review or
  update the intent, or before the first /speckit-specify in a project.
argument-hint: "[free-text idea | path to a brief/notes] [--update]"
allowed-tools: Read Write Edit Glob Grep Bash(git *) AskUserQuestion
metadata:
  author: shod
  version: "0.1.0"
  category: speckit-workflow
---

# Intent

Intent is the product layer above Spec Kit: **constitution → intent → PRD → specify → plan → tasks → implement**.
One intent feeds many feature specs. It answers *why* and *what success looks like*, never *how*.

Template: `templates/intent-template.md` in this skill's directory.

This skill **never commits**.

## Step 0: Locate

1. If `CLAUDE.md` has a "Product context" block (between the markers in Step 4), take the intent path from it.
   Otherwise use `docs/intent.md`.
2. Intent file exists → **update mode**. Otherwise → **create mode**.
3. Look for a PRD: the path in the Product context block, else the first of `docs/prd.md`, `docs/01-prd.md`,
   `docs/PRD.md`. Remember it for Step 4 (it may not exist yet — that is fine).

## Step 1: Gather input

- `$ARGUMENTS` may contain a free-text idea or a path to source material (brief, notes, PRD, chat export).
  Read the source and draft from it.
- Ask only for what is missing, in plain text, at most 5 questions in one message:
  1. What problem are we solving, and why now?
  2. For whom (users, context of use)?
  3. What should exist at the end?
  4. How will we know it worked? (measurable)
  5. What is explicitly out of scope?
- If the user is not available, draft from the source, mark guesses with `[ASSUMPTION]`, and say so in the report.

## Step 2: Write (create mode)

Fill the template. Rules:
- **Language:** match the user and the existing docs. Headings and IDs stay in English (other tools parse them).
- **IDs:** goals `G-1…`, success criteria `SC-1…`, out-of-scope `OOS-1…`. Specs reference these IDs.
- **Success criteria** must be measurable and technology-agnostic ("add 30 phrases in under 5 minutes", not "fast sync").
- **No solution design:** no stack, no architecture, no screens. Those belong to the PRD and plan.
- Keep it short: 1–2 pages. Link to the PRD for details instead of repeating them.

## Step 3: Update mode

- Edit in place; keep everything that is still true.
- **Never renumber or reuse IDs.** Specs point at them.
  - New item → next free number.
  - Retired item → keep the line, strike it through, append `(retired YYYY-MM-DD: reason)`.
  - Changed meaning → retire the old ID and add a new one.
- Bump `Version` and `Updated` in the header and add one line to `## Changelog` at the bottom.
- If a retired or changed ID is referenced in `specs/*/spec.md` (grep the ID), list those specs in the report
  as needing review.

## Step 4: Register in CLAUDE.md

Insert or replace this block in `CLAUDE.md` (create the file if missing). Keep it idempotent: replace
only what is between the markers.

```markdown
<!-- shod-speckit:product-context:start -->
## Product context
- Intent (why, success criteria, boundaries): docs/intent.md
- PRD (requirements, contracts): <PRD path, or "not written yet">
Specs reference intent/PRD IDs in their "## Traceability" section. Reference IDs, never copy text.
When a spec or plan conflicts with these docs, stop and ask.
Read only the sections relevant to the current feature.
<!-- shod-speckit:product-context:end -->
```

## Step 5: Report

- Created / updated, with the list of IDs (new, changed, retired).
- Open `[ASSUMPTION]` items to confirm.
- Specs that reference retired or changed IDs.
- Next step: the PRD, or `/speckit-specify` for the first feature. If the shod-speckit preset is not
  installed in this project, suggest the `speckit-preset` skill.
