# PydanticAI (v2) in a FastAPI app

PydanticAI is async inside. The DB layer in this stack is sync. These rules keep them apart.

## Define agents once, at module level

```python
@dataclass(frozen=True)
class Deps:
    user_id: int
    session_factory: sessionmaker[Session]

support_agent = Agent(
    settings.llm_model,                     # "<provider>:<model>", from config
    deps_type=Deps,
    output_type=SupportAnswer,              # Pydantic model = validated output
    instructions="You answer support questions. Be short.",
)
```

- Model name **must** have a provider prefix (v2 raises an error on a bare name).
  Keep it in settings, not in code, so a project can switch provider or model without code changes.
- Do not hard-code one provider in shared code; check the PydanticAI docs for the exact prefix.
- Use `output_type` with a Pydantic model; read `result.output`.
- Prefer `instructions` over `system_prompt` (instructions are not repeated in message history).
- Do not create an `Agent` per request.

## Calling the agent from an endpoint

LLM calls are slow (seconds). Do not block a thread-pool thread for that time.

Incorrect:
```python
@router.post("/ask")
async def ask(data: AskIn):
    return support_agent.run_sync(data.question).output   # run_sync inside a running loop fails
```

Also not good:
```python
@router.post("/ask")
def ask(data: AskIn):
    return support_agent.run_sync(data.question).output   # works, but holds a thread for seconds
```

Correct:
```python
@router.post("/ask", response_model=SupportAnswer)
async def ask(data: AskIn, user: CurrentUser) -> SupportAnswer:
    deps = Deps(user_id=user.id, session_factory=SessionLocal)
    result = await support_agent.run(data.question, deps=deps)
    return result.output
```

- `run_sync` is only for scripts and CLI, never inside FastAPI.
- In this `async def` endpoint, do not use the request `DbSession` directly (sync calls block the loop).
  Load data with `await run_in_threadpool(...)` before or after the run.
- `CurrentUser` here must not do sync DB work inside an `async def` dependency.
  A plain `def` dependency is fine: FastAPI runs it in the thread pool.

## Tools with the sync DB

PydanticAI runs plain `def` tools in a thread, so sync SQLAlchemy is fine there.
Each tool opens its **own short session**; do not pass the request session into tools.

```python
@support_agent.tool
def find_orders(ctx: RunContext[Deps], limit: int = 5) -> list[OrderBrief]:
    """Return the latest orders of the current user."""
    with ctx.deps.session_factory() as db:
        stmt = (select(Order).where(Order.user_id == ctx.deps.user_id)
                .order_by(Order.id.desc()).limit(min(limit, 20)))
        return [OrderBrief.model_validate(o) for o in db.scalars(stmt)]
```

- Take the user id from `ctx.deps`, **never from tool arguments**: the model could ask for another user's data.
- Return small, typed data (Pydantic models), not ORM objects.
- Cap sizes (`limit`) — the LLM chooses the arguments.
- Raise `ModelRetry("...")` to tell the model to fix its arguments.
- Use `@agent.tool_plain` when the tool does not need `ctx`.

## Limits, errors, cost

- Set `usage_limits=UsageLimits(...)` on `run()` (requests, tokens) to stop runaway loops.
- Set timeouts and retries on the model/provider; map provider errors to a `502`/`503` for the client.
- Log usage (`result.usage`) per request for cost tracking.
- Treat LLM output as untrusted input: validate it (via `output_type`), never `eval` it,
  never put it into SQL or shell commands.

## Streaming

For chat UIs, stream with `agent.run_stream(...)` and FastAPI `StreamingResponse`
(or SSE). Keep the DB out of the streaming generator.

## Testing

Never call a real LLM in tests:

```python
from pydantic_ai import models
from pydantic_ai.models.test import TestModel

models.ALLOW_MODEL_REQUESTS = False      # in conftest.py

def test_ask(client):
    with support_agent.override(model=TestModel()):
        response = client.post("/ask", json={"question": "Where is my order?"})
    assert response.status_code == 200
```

- `TestModel` calls all tools and returns valid data for `output_type`.
- `FunctionModel` (`pydantic_ai.models.function`) when you need exact model behavior.
- Test tools as normal functions too.
