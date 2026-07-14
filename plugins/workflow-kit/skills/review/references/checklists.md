# Code Review Checklists

Universal review rules across 4 categories. Claude uses this file during AI code analysis (Step 3).

> **This file contains only universal checks** applicable to any Laravel project.
> Project-specific requirements (strict_types, folder structure, API format, performance targets, etc.)
> come from the **project constitution** (`.specify/memory/constitution.md`) — see Step 1 in SKILL.md.
>
> **Priority**: Laravel Boost guidelines > Constitution > This checklist.
> When rules conflict — the higher-priority source wins.

---

## 1. Laravel Best Practices

> Core Laravel rules come from **Laravel Boost guidelines** (CLAUDE.md) and `search-docs`.
> Below — only additional checks that Boost does not cover.

### Additional checks (not in Boost)

- Factories and seeders created for new models
- `$fillable` or `$guarded` defined on every model
- Custom error messages in Form Requests
- Named routes and `route()` for URL generation
- Files created via `php artisan make:*` commands

---

## 2. Security (OWASP)

### Injection

- No raw SQL without binding (`DB::raw()`, `whereRaw()` with user data)
- Parameterised queries via Eloquent/Query Builder
- No `eval()`, `exec()`, `shell_exec()` with user data
- No dynamic class/method name construction from user input

### XSS

- Blade `{{ }}` instead of `{!! !!}` for user data
- Validation and sanitisation of input data
- Content-Type headers set correctly for APIs

### Mass Assignment

- `$fillable` or `$guarded` on all models
- No `Model::create($request->all())` without filtering
- Use `$request->validated()` after Form Request
- No `$request->except()` instead of `$request->only()` or `validated()`

### Authentication & Authorization

- Gates/Policies for authorising access to resources
- Middleware protecting routes
- No hardcoded secrets, tokens, or passwords in code
- Rate limiting on public endpoints

### Data Exposure

- API Resources hide sensitive fields
- No `toArray()` or `->toJson()` without field filtering
- Logs do not contain PII / secrets / tokens
- Error responses do not expose internal structure

---

## 3. Performance

### Queries

- No N+1 queries (eager loading: `with()`, `load()`)
- Indexes for fields in WHERE, ORDER BY, JOIN (check migrations)
- `select()` to limit selected columns where appropriate
- Pagination for large data sets
- `chunk()` or `lazy()` for processing large collections
- `limit()` on eager loaded relations where possible (Laravel 12)

### Caching

- Redis caching for frequently requested data
- Cache tags for group invalidation
- TTL set for all cache entries
- No caching of volatile data without an invalidation strategy

### Queue & Jobs

- Heavy operations offloaded to queues (email, API calls, reports)
- Jobs have a retry/backoff strategy
- Timeout set for long-running jobs
- Failed job handler defined

### General

- No `sleep()` or blocking operations in the request lifecycle
- Response time within acceptable limits (see constitution for specific targets)
- No extra DB queries inside loops
- No loading an entire table into memory (`::all()` on large tables)

---

## 4. Code Style & Architecture

> PSR-12, PHP 8.4 features (constructor promotion, return types, type hints, enums) —
> covered by **Laravel Boost guidelines**. Below — additional checks.

### SOLID

- Single Responsibility — class/method does one thing
- Open/Closed — extension via inheritance/interfaces
- Dependency Injection via constructor
- Interface segregation — small, specific interfaces
- No god-classes with 10+ methods of mixed responsibility

### Naming & Conventions

- Descriptive variable and method names (`isRegisteredForDiscounts`, not `discount()`)
- Consistent naming with sibling files in the project
- Check for existing components before creating new ones
- Follow the project directory structure
