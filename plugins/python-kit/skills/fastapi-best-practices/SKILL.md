---
name: fastapi-best-practices
description: "Apply this skill whenever writing, reviewing, or refactoring FastAPI code. Covers project structure, routers, dependency injection, Pydantic schemas, def vs async def endpoints, sync SQLAlchemy 2 sessions with psycopg 3, Alembic migrations, error handling, authentication and security, settings, background tasks, PydanticAI agents and tools, testing with TestClient, and deployment with Uvicorn. Use for creating endpoints, fixing blocking-event-loop or thread-pool problems, designing request/response models, adding LLM features with PydanticAI, and any task involving FastAPI, Starlette, or uvicorn."
license: MIT
metadata:
  author: Oleg Shmyk
---

# FastAPI Best Practices

Best practices for FastAPI. General Python rules are in the `python-best-practices` skill;
this skill covers only FastAPI-specific topics.

**Target stack:** Python 3.12, FastAPI (0.130+), Uvicorn, Pydantic v2, SQLAlchemy 2 **sync** ORM,
Alembic, psycopg 3, PydanticAI v2. Checked against: FastAPI 0.142, SQLAlchemy 2.1,
Alembic 1.20, psycopg 3.3, Pydantic 2.13, PydanticAI 2.54 (October 2026).

## Consistency First

Check what the project already does: folder layout, ORM, auth method, test setup.
Follow the existing pattern. These rules are defaults when no pattern exists yet.

## Quick Reference

### 1. Project Structure → `rules/structure.md`
- Group by domain (`users/`, `orders/`), not by file type
- Each domain: `router.py`, `schemas.py`, `service.py`, `models.py`, `dependencies.py`
- Thin routers: HTTP only; business logic in services
- `create_app()` factory; routers included with `prefix` and `tags`

### 2. Routes and Dependencies → `rules/routing-dependencies.md`
- Use `Depends` for DB sessions, auth, pagination, services
- Use `Annotated[T, Depends(...)]` and reuse the aliases
- Explicit `status_code`, `response_model`, and `tags`
- Validate path/query params with `Path`, `Query`
- Dependencies for validation (e.g. "item exists") shared by many routes

### 3. Schemas → `rules/schemas.md`
- Separate models: `Create`, `Update`, `Read` — never expose the DB model
- Always set `response_model` to stop data leaks
- `model_config = ConfigDict(from_attributes=True)`
- `Field` constraints for validation; `model_validator` for cross-field rules
- Pagination: `limit` / `offset` with caps

### 4. Database → `rules/database.md`
- Sync DB ⇒ endpoints and dependencies are plain `def` (run in the thread pool)
- Never call the sync ORM inside `async def` (use `run_in_threadpool` if you must)
- `postgresql+psycopg://` URL; one engine per process; `Session` per request via `yield`
- Commit in the service, never after `yield` (that code runs after the response)
- `Mapped[...]` models, `select()` queries; avoid N+1 (`selectinload`, `lazy="raise"`)
- Alembic for migrations, reviewed by hand

### 5. Errors → `rules/errors.md`
- `HTTPException` with the right status code
- Domain exceptions + `@app.exception_handler` to map them to HTTP
- One consistent error JSON format
- Never return stack traces or internal details

### 6. Security → `rules/security.md`
- OAuth2 + JWT (short-lived) or sessions; hash passwords with argon2/bcrypt
- Authorize in dependencies (`get_current_user`, role checks)
- Restrictive CORS (no `*` with credentials)
- Rate limiting; request size limits
- Secrets from `pydantic-settings`, never in code

### 7. Testing → `rules/testing.md`
- `TestClient` (sync); `with TestClient(app)` to run lifespan
- Use `app.dependency_overrides` to fake DB/auth
- Real PostgreSQL test DB, rollback per test (`join_transaction_mode="create_savepoint"`)
- Test status codes, response bodies, and validation errors

### 8. Performance and Deployment → `rules/performance-deploy.md`
- Thread pool (40) and DB pool sizes must match; count connections across workers
- `response_model` / return type ⇒ fast Rust serialization; `ORJSONResponse` is deprecated
- `BackgroundTasks` for small jobs; a queue for heavy ones
- `lifespan` for startup/shutdown (not `on_event`)
- Health endpoints; structured logging; request IDs
- Run with `uvicorn --workers` behind a proxy; do not use `--reload` in production

### 9. PydanticAI → `rules/pydantic-ai.md`
- Agents at module level; model name with provider prefix, from settings
- In endpoints: `async def` + `await agent.run(...)`; never `run_sync` inside FastAPI
- Tools are plain `def` with their own short DB session; user id from `deps`, not from arguments
- `output_type` for validated output; `UsageLimits`; treat LLM output as untrusted
- Tests: `ALLOW_MODEL_REQUESTS = False` + `agent.override(model=TestModel())`

## How to Apply

1. Pick the topic, read the matching `rules/*.md` file.
2. In reviews, report file and line, and show the fix.
3. Keep changes focused; do not rewrite unrelated code.
