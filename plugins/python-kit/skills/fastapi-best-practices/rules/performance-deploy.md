# Performance and Deployment

## Lifespan, not on_event

Incorrect (deprecated):
```python
@app.on_event("startup")
async def startup(): ...
```

Correct:
```python
@asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncIterator[None]:
    app.state.http = httpx.AsyncClient(timeout=10)
    yield
    await app.state.http.aclose()

app = FastAPI(lifespan=lifespan)
```

Create shared clients and pools once, at startup.

## Thread pool and DB pool (sync stack)

Every `def` endpoint and `def` dependency runs in the AnyIO thread pool: **40 threads** per worker by default.
With the sync DB, this pool limits how many requests run at the same time.

- Keep the DB pool (`pool_size + max_overflow`) close to the thread limit. Too few connections:
  threads wait for a connection. Too many: PostgreSQL `max_connections` runs out across workers.
- Count: `workers × (pool_size + max_overflow)` must fit in PostgreSQL `max_connections`.
- To change the thread limit, set it in `lifespan`:

```python
@asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncIterator[None]:
    anyio.to_thread.current_default_thread_limiter().total_tokens = 60
    yield
```

- Never hold a thread for a long time (LLM calls, slow HTTP): use `async def` + `await` for those.
- Set a DB statement timeout (e.g. `connect_args={"options": "-c statement_timeout=5000"}`).

## Background work

- `BackgroundTasks` — small, fast jobs after the response (send email, write audit log)
- Queue (Celery, ARQ, Dramatiq, RQ) — long, heavy, or must-not-be-lost jobs

Background tasks die if the process restarts. Do not use them for important work.

## Response speed

- Paginate lists; never return unlimited rows
- Cache stable data (Redis, `Cache-Control`, ETag)
- Return only the fields the client needs; avoid huge payloads
- Set a `response_model` or return type: since FastAPI 0.130, JSON is then serialized by
  Pydantic in Rust (about 2× faster). `ORJSONResponse` / `UJSONResponse` are deprecated (0.131)
- Stream large files with `StreamingResponse` / `FileResponse`
- Add `GZipMiddleware` for large JSON, or do it at the proxy

## Observability

- Health endpoints: `/health` (alive) and `/ready` (DB reachable)
- Structured (JSON) logs with a request ID per request
- Metrics (Prometheus) and tracing (OpenTelemetry; FastAPI 0.142+ has native support, check its docs)
- PydanticAI supports OpenTelemetry too — trace LLM calls and token usage

```python
@app.middleware("http")
async def request_id(request: Request, call_next):
    request_id = request.headers.get("x-request-id", str(uuid4()))
    request.state.request_id = request_id      # use it in logs
    response = await call_next(request)
    response.headers["x-request-id"] = request_id
    return response
```

## Running in production

```
uvicorn app.main:app --host 0.0.0.0 --port 8000 --workers 4
```

or gunicorn with the `uvicorn-worker` package (`-k uvicorn_worker.UvicornWorker`);
`uvicorn.workers` is deprecated.

- Run behind a reverse proxy (nginx, Traefik); use `--proxy-headers` with `--forwarded-allow-ips`
- Never use `--reload` in production
- Kubernetes / many containers: one worker per container, scale by containers
- One VM: several workers, about one per CPU core
- Docker: small image, non-root user
- Keep the app stateless so you can scale

## Config check at startup

Fail fast: `Settings()` raises if env vars are missing, so the app does not start in a broken state.
