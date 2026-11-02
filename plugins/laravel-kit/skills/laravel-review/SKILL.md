---
name: laravel-review
description: >-
  Laravel stack rules for code review. Loaded by the workflow-kit `review` skill when
  `.claude-project.json` lists `laravel-kit:laravel-review` in `review.rules`. Adds
  Laravel-specific checks (Eloquent, mass assignment, Blade XSS, policies, queues, N+1)
  to the framework-agnostic review. Not a standalone reviewer.
user-invocable: false
metadata:
  author: olegs
  version: "1.0"
  category: quality
---

# Laravel Review Rules

This skill gives Laravel rules to the `workflow-kit:review` skill.
It does not run a review by itself.

## How to apply the rules

1. Read [checklist.md](references/checklist.md).
2. Apply each check to the changed PHP and Blade files in the review scope.
3. Report each finding in the format of the `review` skill, with category and severity.

## Laravel Boost (optional)

1. Call the `application-info` tool of the Laravel Boost MCP server.
2. If the tool is available, use `search-docs` to confirm Laravel and PHP best practices.
3. If the tool is not available, continue the review without it.
   Write the line `Laravel Boost: unavailable` in the report header.

## Severity rules

- A security issue that an attacker can exploit is **CRITICAL**.
  Examples: SQL injection, missing authorization, `$request->all()` into `create()`.
- A missing `$fillable` or `$guarded` on a new model is **WARNING**.
- A missing factory or seeder for a new model is **INFO**.
