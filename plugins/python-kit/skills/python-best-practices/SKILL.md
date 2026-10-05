---
name: python-best-practices
description: "Apply this skill whenever writing, reviewing, or refactoring Python code. Covers style and naming, type hints, error handling, dataclasses and Pydantic models, functions and classes, async/await, pytest testing, project layout and tooling (uv, ruff, mypy), performance, and security. Use for Python code reviews, fixing mutable-default or exception-handling bugs, adding type hints, structuring packages, and any task involving .py files or pyproject.toml."
license: MIT
metadata:
  author: Oleg Shmyk
---

# Python Best Practices

Best practices for modern Python (3.12+), grouped by topic. Each rule says what to do and why.
For exact API details, check the official docs for the Python version the project uses.

## Consistency First

Before applying any rule, check what the project already does: Python version, formatter,
type checker, test framework, folder layout. Follow the existing pattern, even if another one
is better in theory. These rules are defaults for when no pattern exists yet.

## Quick Reference

### 1. Style and Naming → `rules/style.md`
- Follow PEP 8; let `ruff format` do the formatting, do not argue about it
- `snake_case` for functions/variables, `PascalCase` for classes, `UPPER_CASE` for constants
- Absolute imports, grouped: stdlib, third-party, local
- f-strings for formatting; `pathlib` for paths
- Comprehensions for simple cases, plain loops when logic is complex

### 2. Type Hints → `rules/typing.md`
- Annotate all public functions (arguments and return)
- Built-in generics: `list[str]`, `dict[str, int]`, `X | None`
- Prefer `Protocol`, `Sequence`, `Mapping` for inputs; concrete types for outputs
- Avoid `Any`; use `object`, generics, or `TypedDict`
- Run `mypy --strict` (or pyright) in CI

### 3. Error Handling → `rules/errors.md`
- Catch specific exceptions; never bare `except:`
- Keep `try` blocks small
- Raise with context: `raise NewError(...) from err`
- Custom exception hierarchy for your domain
- Context managers (`with`) for cleanup

### 4. Data Modeling → `rules/data-modeling.md`
- `dataclass(slots=True, frozen=True)` for plain data
- Pydantic at the boundary (API, config, files) to validate input
- `Enum` / `StrEnum` instead of magic strings
- Never use mutable default arguments

### 5. Functions and Classes → `rules/functions-classes.md`
- Small functions, one job; early return over deep nesting
- Keyword-only arguments for flags
- Composition over inheritance
- Inject dependencies; avoid global state
- Generators for large or lazy data

### 6. Async → `rules/async.md`
- Never block the event loop (no `requests`, `time.sleep`)
- `asyncio.TaskGroup` for concurrent tasks
- Always set timeouts on I/O
- Use `asyncio.to_thread` for unavoidable blocking code

### 7. Testing → `rules/testing.md`
- `pytest`, plain `assert`, fixtures, `parametrize`
- Test behavior, not implementation
- Mock only at system boundaries
- Fast, isolated, deterministic tests

### 8. Project Layout and Tooling → `rules/packaging-tooling.md`
- `pyproject.toml` as the single config file
- `src/` layout for libraries; `uv` or `poetry` with a lock file
- One virtual environment per project
- `ruff` (lint + format), `mypy`, `pytest` in pre-commit and CI

### 9. Performance → `rules/performance.md`
- Measure first (`cProfile`, `timeit`), then optimize
- Right data structure: `set`/`dict` for lookups
- Avoid string concatenation in loops; use `"".join`
- `functools.cache` for pure, repeated calls

### 10. Security → `rules/security.md`
- Never put secrets in code; use environment variables or a secret manager
- Parameterized SQL queries only
- `subprocess` with a list of args, never `shell=True` with user input
- No `pickle` / `eval` / `yaml.load` on untrusted data
- `secrets` module for tokens; audit dependencies

## How to Apply

1. Identify the topic of the task, read the matching `rules/*.md` file.
2. When reviewing, report violations with file and line, and show the fix.
3. Do not rewrite unrelated code. Keep changes focused.
