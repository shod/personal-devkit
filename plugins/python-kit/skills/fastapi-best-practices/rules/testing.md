# Testing

## TestClient

The stack is sync, so use FastAPI's `TestClient` (no async test setup needed):

```python
@pytest.fixture
def client(app: FastAPI) -> Iterator[TestClient]:
    with TestClient(app) as c:      # "with" also runs lifespan
        yield c

def test_create_item(client):
    response = client.post("/items", json={"name": "Pen", "price": "1.50"})
    assert response.status_code == 201
    assert response.json()["name"] == "Pen"
```

## Override dependencies

Do not patch internals. Replace dependencies:

```python
app.dependency_overrides[get_current_user] = lambda: User(id=1, role=Role.ADMIN)
...
app.dependency_overrides.clear()     # in fixture teardown
```

## Database per test

Use a real PostgreSQL test database (same driver, psycopg 3) and roll back after each test:

```python
@pytest.fixture
def db(app: FastAPI) -> Iterator[Session]:
    with engine.connect() as conn:
        trans = conn.begin()
        session = Session(bind=conn, join_transaction_mode="create_savepoint")
        app.dependency_overrides[get_db] = lambda: session
        yield session
        session.close()
        trans.rollback()
        app.dependency_overrides.pop(get_db, None)
```

`create_savepoint` lets the code under test call `commit()`; the outer transaction still rolls back.
Create the schema once per test session with Alembic (`alembic upgrade head`), not `create_all()`,
so migrations are tested too.

## PydanticAI

No real LLM calls in tests: `models.ALLOW_MODEL_REQUESTS = False` in `conftest.py`,
and `agent.override(model=TestModel())`. See `pydantic-ai.md`.

## What to test

- Success path: status code and response body
- Validation errors (`422`), not found (`404`), conflicts (`409`)
- Auth: no token (`401`), wrong role (`403`), other user's data (`403`/`404`)
- Services directly, without HTTP, for business rules

## Tips

- Test the `response_model`: check that secret fields are **not** in the response
- Keep tests independent; build data with factories/fixtures
- If some tests are `async def` (e.g. calling an agent directly), use `pytest.mark.anyio`
  or `pytest-asyncio`; with `pytest-asyncio`, set `asyncio_mode = "auto"`
