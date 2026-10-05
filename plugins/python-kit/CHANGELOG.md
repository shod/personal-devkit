# Changelog — python-kit

All notable changes to this plugin are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/);
this plugin adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.0]

### Added

- **`fastapi-best-practices` skill.** Rules for the stack Python 3.12, FastAPI, Uvicorn,
  SQLAlchemy 2 (sync), Alembic, psycopg 3, PydanticAI v2 — checked against FastAPI 0.142,
  SQLAlchemy 2.1, Alembic 1.20, psycopg 3.3, Pydantic 2.13, PydanticAI 2.54.
  - `structure` — domain folders, thin routers, services, settings.
  - `routing-dependencies` — `Annotated` dependencies, `def` vs `async def`, `yield` scope.
  - `schemas` — separate Create/Update/Read models, `response_model`, validation.
  - `database` — sync `Session` per request, `postgresql+psycopg://`, no commit after `yield`,
    N+1, Alembic naming convention.
  - `errors`, `security` — domain exceptions, one error format, auth, CORS, prompt injection.
  - `testing` — `TestClient`, `dependency_overrides`, rollback per test, no real LLM calls.
  - `performance-deploy` — thread pool vs DB pool, `lifespan`, Uvicorn workers.
  - `pydantic-ai` — agents at module level, `await agent.run()` in endpoints, tools with
    their own DB session, provider-neutral model config, `TestModel`.

### Changed

- `python-best-practices` targets **Python 3.12+** (PEP 695 generics, `requires-python = ">=3.12"`).

## [0.1.0]

### Added

- **`python-best-practices` skill.** Rules by topic: style, typing, errors, data modeling,
  functions/classes, async, testing, packaging/tooling (uv, ruff, mypy), performance, security.
