---
name: sdd-archive
description: >-
  Archive a completed feature following the SDD guidelines. Checks tasks.md for completion,
  moves the folder to _archive/{year}, updates FS-000-map-spec.md and core/ documentation.
  Usage: /sdd-archive <feature-folder> <core-section>
argument-hint: <spec-folder> <core-section>
user-invocable: true
disable-model-invocation: true
allowed-tools: Read Glob Grep Bash(mv *) Bash(mkdir *) Bash(date *) Bash(ls *) Edit Write
metadata:
  author: Oleg Shmyk
  version: "1.0"
  category: spec-management
---

# SDD Archive — Archiving a Specification

Archives a completed feature according to the `specs/SDD_GUIDELINES.md` policy.

## Arguments

- `$1` — feature folder name inside `specs/` (e.g. `FS-001-cart`)
- `$2` — section name inside `core/` to update (e.g. `cart`)

## Workflow

### Step 1: Validate input

1. Check that folder `specs/$1` exists
2. Check that folder `specs/core/$2` exists
3. If anything is missing — **STOP**, print an error

### Step 2: Check task completion

1. Read file `specs/$1/tasks.md`
2. If the file is not found — **STOP**, print: "File tasks.md not found in specs/$1"
3. Count tasks:
   - Completed: lines with `- [x]` (case-insensitive)
   - Incomplete: lines with `- [ ]`
4. If there are incomplete tasks — **STOP**, print:

```
⛔ Archiving is not possible.
Incomplete tasks: {count} of {total}
Complete all tasks before archiving.
```

5. If all tasks are complete — continue

### Step 3: Move to archive

1. Determine current year: `date +%Y`
2. Create folder if it does not exist: `specs/_archive/{year}/`
3. Move: `specs/$1` → `specs/_archive/{year}/$1`
4. Confirm the move

### Step 4: Update FS-000-map-spec.md

1. Read `specs/FS-000-map-spec.md`
2. In the **Feature Map** table, update the link for this feature:
   - Old link: `$1/spec.md` (or equivalent)
   - New link: `_archive/{year}/$1/spec.md`
3. Add a `✅ Archived` marker to the description or a dedicated column
4. If the feature is not in the table — add a new row with the archive link

### Step 5: Update core/ documentation

This is the **key step** for preserving context. Before archiving, transfer the current system state to `specs/core/$2/`.

1. Review the contents of the archived folder `specs/_archive/{year}/$1/`
2. Find planning artefacts: `plan.md`, `data-model.md`, `contracts/`, `spec.md`
3. Based on the found artefacts, update or create files in `specs/core/$2/`:

#### domain-model.md
- Extract the final data model from `data-model.md` or `plan.md`
- Describe entities, relations, key fields
- **Format**: current state, not development history

#### business-rules.md
- Extract business rules and constraints from `spec.md`
- Describe validations, limits, conditions
- **Format**: rules as they work now

#### state-machine.md
- If the feature contains status transitions — describe the state machine
- States, transitions, conditions
- Skip if not applicable

#### api-contract.md
- Extract API endpoint descriptions from `contracts/` or `spec.md`
- Methods, URLs, parameters, responses
- **Format**: current contract

**Important**: `core/` describes HOW the system works NOW. Do not copy decision history — only the final result.

### Step 6: Report

Print the final report:

```
✅ Archiving complete

Feature: $1
Archive: specs/_archive/{year}/$1/
Core:    specs/core/$2/

Updated files:
- specs/FS-000-map-spec.md (link updated)
- specs/core/$2/domain-model.md
- specs/core/$2/business-rules.md
- specs/core/$2/state-machine.md (if applicable)
- specs/core/$2/api-contract.md (if applicable)
```
