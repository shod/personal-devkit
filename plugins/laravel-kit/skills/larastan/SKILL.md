---
name: larastan
description: >-
  Run LaraStan (PHPStan) for static code analysis. By default analyses changed files.
  Use /larastan to check changed files, /larastan --all for the entire project,
  /larastan path/to/file.php for specific files.
disable-model-invocation: true
argument-hint: "[--all] [paths...]"
allowed-tools: Bash(vendor/bin/phpstan *) Bash(git *)
metadata:
  author: speckit
  version: "1.0"
  category: quality
---

# LaraStan Skill

Runs LaraStan (PHPStan) — a PHP static analysis tool.

**By default analyses only changed files** (dirty mode). With the `--all` flag — the entire project.

## Modes

### Argument parsing

Parse `$ARGUMENTS` into:
- **Flags**: `--all` (entire project)
- **Paths**: everything else — paths to files/directories

### Mode 1: No arguments (dirty mode, default)

Analyse only changed PHP files:

1. Get list of changed files:
   ```bash
   git diff --name-only --diff-filter=ACMR HEAD
   ```
2. Filter to `*.php` only
3. If no files — output "No changed PHP files to analyse" and exit
4. Pass files to phpstan:
   ```bash
   vendor/bin/phpstan analyse --no-progress --error-format=json {files}
   ```

> **Note**: if there are too many files (> 50), run phpstan without explicit paths (analyse entire project) to avoid command line length issues.

### Mode 2: Specific paths

```bash
vendor/bin/phpstan analyse --no-progress --error-format=json {paths}
```

### Mode 3: Entire project (`--all`)

```bash
vendor/bin/phpstan analyse --no-progress --error-format=json
```

## Algorithm

### Step 1: Determine scope

1. If `$ARGUMENTS` contains `--all` → entire project (mode 3)
2. If `$ARGUMENTS` contains paths → specific files (mode 2)
3. If `$ARGUMENTS` is empty → dirty mode (mode 1)

### Step 2: Run analysis

1. Build phpstan command
2. Run via Bash
3. Parse JSON output

### Step 3: Output result

**If no errors:**

```
✓ LaraStan: no errors found ({N} files analysed)
```

**If errors exist:**

```
✗ LaraStan: {N} errors found in {M} files

  path/to/file1.php
    :{line} — {message}
    :{line} — {message}

  path/to/file2.php
    :{line} — {message}
```

## Rules

### No code modification (NON-NEGOTIABLE)
- **PROHIBITED** to use Edit/Write on any project files
- Skill only runs analysis and shows results
- Fixing errors is the responsibility of the developer or another skill

### Language
- Communication with user — **English**
