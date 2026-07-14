---
name: pint
description: >-
  Run Laravel Pint for code formatting. By default fixes changed files (fix mode).
  Use /pint to fix, /pint --test to check without changes,
  /pint path/to/file.php for specific files.
disable-model-invocation: true
argument-hint: "[--test] [paths...]"
allowed-tools: Bash(vendor/bin/pint *)
metadata:
  author: speckit
  version: "1.0"
  category: quality
---

# Pint Skill

Runs Laravel Pint — a code formatting tool (PSR-12).

**By default fixes files** (fix mode). With the `--test` flag — checks only without changes.

## Modes

### Argument parsing

Parse `$ARGUMENTS` into:
- **Flags**: `--test` (check only), `--dirty` (changed files only, default)
- **Paths**: everything else — paths to files/directories

### Mode 1: No arguments (default)

Fix all changed files:

```bash
vendor/bin/pint --dirty --format agent
```

### Mode 2: With specific paths

Fix specified files/directories:

```bash
vendor/bin/pint {paths} --format agent
```

### Mode 3: Check only (`--test`)

Check without modifying files:

```bash
# Changed files
vendor/bin/pint --dirty --test --format agent

# Or specific paths
vendor/bin/pint --test --format agent {paths}
```

## Algorithm

### Step 1: Determine command

1. If `$ARGUMENTS` is empty → `vendor/bin/pint --dirty --format agent`
2. If it contains `--test` → add `--test` to command
3. If it contains paths → replace `--dirty` with explicit paths
4. Build the final command

### Step 2: Execute

1. Run the command via Bash
2. Read output

### Step 3: Output result

**If fix mode (without `--test`):**

```
✓ Pint: {N} files fixed
```

or

```
✓ Pint: all clean, no changes needed
```

**If test mode (`--test`):**

```
✓ Pint: check passed, no errors
```

or

```
✗ Pint: {N} files with style violations found
  - path/to/file1.php
  - path/to/file2.php
```

## Rules

### No code modification (NON-NEGOTIABLE)
- **PROHIBITED** to use Edit/Write on any project files
- Pint fixes files in fix mode — that is the only way to make changes
- Skill only runs the command and shows the result

### Language
- Communication with user — **English**
