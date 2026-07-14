---
name: review
description: >-
  AI code review for speckit tasks. Checks Laravel best practices, security (OWASP),
  performance, and architecture. Use /review for git diff review
  or /review {task-id} for a specific task (e.g., T012, T045, etc.).
  For formatting and static analysis use /pint and /larastan separately.
disable-model-invocation: true
argument-hint: "[task-id]"
allowed-tools: Bash(git *) Read Grep Glob mcp__laravel-boost__application-info mcp__laravel-boost__search-docs
metadata:
  author: speckit
  version: "2.0"
  category: quality
---

# Code Review Skill

Conducts AI code review of code generated/changed within speckit tasks.
Checks 4 categories: Laravel best practices, security, performance, architecture.

**Does NOT fix code** — only reports issues with recommendations.

> **Formatting and static analysis** are extracted to separate skills:
> `/pint` — Laravel Pint, `/larastan` — LaraStan (PHPStan).

## Modes

### Mode 1: Git Diff (no arguments)

If `$ARGUMENTS` is empty — review all uncommitted changes:

1. Get list of changed files: `git diff --name-only` and `git diff --cached --name-only`
2. Filter to PHP files only (`*.php`)
3. Review each file

### Mode 2: Task ID (with argument)

If `$ARGUMENTS` contains a task ID (e.g., `T012`):

1. Find the task in `specs/*/tasks.md` by ID
2. From the task description determine the affected files (paths in description)
3. If files are not specified explicitly — use `git diff --name-only` for latest changes
4. Review those files

## Review algorithm

### Step 0: Check Laravel Boost

1. Call `application-info` to verify Laravel Boost MCP server availability
2. If Laravel Boost MCP server is unavailable or returns error:
   - **STOP review immediately**
   - Output message: "Laravel Boost MCP server is unavailable. Review is not possible without access to current documentation. Ensure Laravel Boost is installed (`composer require --dev laravel/boost`) and the MCP server is running."
   - **DO NOT continue** — review without Laravel Boost may produce incorrect recommendations
3. If Laravel Boost is available — proceed to Step 1

### Step 1: Scope determination and context loading

1. Find FEATURE_DIR — directory `specs/FS-*` in the project
2. Determine mode from `$ARGUMENTS`
3. Collect list of PHP files for review
4. **Load project constitution** — find file `.specify/memory/constitution.md`:
   - If file exists — read and extract project requirements (strict_types, folder structure, API format, performance targets, auth strategy, testing standards, etc.)
   - These requirements are checked **in addition to** universal checklists
   - Violations of NON-NEGOTIABLE constitution requirements always have severity **CRITICAL**
   - If file not found — review works only from universal checklists in [checklists.md](references/checklists.md)
5. Show user the list of files that will be checked

### Step 2: AI code analysis

For each PHP file in the list:

1. Read the full file contents
2. Check against **universal checklists** from [checklists.md](references/checklists.md)
3. Check against **project requirements from the constitution** (if loaded in Step 1)
4. Record found issues with severity level

Use `search-docs` when needed to clarify Laravel 12 / PHP 8.4 best practices.

### Step 3: Output results

Output the AI analysis result in chat in the format:

```
═══ Code Review: {mode} ═══

Files checked: {N}

--- {category} ---

[SEVERITY] {issue description}
  File: path/to/file.php:{line}
  Recommendation: {what to do}

--- Summary ---

CRITICAL: {N} | WARNING: {N} | INFO: {N}
{brief MUST FIX list if any}
```

## Severity levels

| Level | Description | Action |
|-------|-------------|--------|
| CRITICAL | Bug, vulnerability, data loss | MUST fix |
| WARNING | Best practice violation, potential issue | Recommended to fix |
| INFO | Style improvement, minor refactoring | At discretion |

## Important rules

### No code modification (NON-NEGOTIABLE)

- **PROHIBITED** to modify, edit, or fix any project files
- **PROHIBITED** to use Edit/Write on any project files
- If something needs fixing — describe the issue and recommendation in chat

### General rules

- Output in **English**
- Check compliance with **PHP 8.4** and **Laravel 12** standards
- Follow rules from CLAUDE.md and Laravel Boost guidelines
- Config files (.env, docker-compose, pint.json, phpstan.neon) — check for correctness, but without security/performance analysis

## Additional resources

- Detailed checklists for all categories: [checklists.md](references/checklists.md)
- Report template (used by `review-agent` sub-agent): [report-template.md](templates/report-template.md)
