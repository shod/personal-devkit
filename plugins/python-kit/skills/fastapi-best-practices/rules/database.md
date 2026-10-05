# Database (SQLAlchemy 2 sync + psycopg 3)

The stack uses the **sync** SQLAlchemy ORM (`Session`, not `AsyncSession`) with the psycopg 3 driver.

## def vs async def

FastAPI runs a plain `def` endpoint (and a plain `def` dependency) in a thread pool.
A sync DB call inside `async def` blocks the event loop, so every other request waits.

Incorrect:
```python
@router.get("/{item_id}")
async def read_item(item_id: int, db: DbSession):
    return db.get(Item, item_id)          # blocking call in the event loop
```

Correct:
```python
@router.get("/{item_id}", response_model=ItemRead)
def read_item(item_id: int, db: DbSession) -> Item:
    return db.get(Item, item_id)
```

Rule: an endpoint that touches the DB is `def`. Use `async def` only when everything inside
is awaited (e.g. an LLM call with PydanticAI — see `pydantic-ai.md`). There, run DB work with
`await run_in_threadpool(func, ...)` (`from fastapi.concurrency import run_in_threadpool`).

## Engine and URL

Use the explicit psycopg 3 dialect in the URL:

```python
# postgresql+psycopg://user:pass@host:5432/db
engine = create_engine(
    settings.database_url,
    pool_pre_ping=True,
    pool_size=10,
    max_overflow=10,
)
SessionLocal = sessionmaker(engine, expire_on_commit=False)
```

- `postgresql+psycopg://` = psycopg 3. `postgresql+psycopg2://` is the old driver.
  (SQLAlchemy 2.1 uses psycopg 3 for plain `postgresql://` too, but be explicit.)
- Create the engine **once** per process (module level or `lifespan`), never per request.
- Pool size and the FastAPI thread pool (40 threads by default) work together:
  if 40 threads wait for 20 connections, requests queue up. See `performance-deploy.md`.

## One session per request

```python
def get_db() -> Iterator[Session]:
    with SessionLocal() as session:
        yield session

DbSession = Annotated[Session, Depends(get_db)]
```

- Since FastAPI 0.118, the code after `yield` runs **after** the response is sent.
  So do **not** commit after `yield`: the client would get `200` even if the commit fails.
- To return the connection to the pool earlier, use `Depends(get_db, scope="function")`
  (exit code runs before the response). Do not use it if you stream data from the DB.
- Never share a session between requests or threads.

## Transactions

Commit in the service layer, once per use case:

```python
class OrderService:
    def __init__(self, db: Session) -> None:
        self._db = db

    def create(self, data: OrderCreate) -> Order:
        order = Order(**data.model_dump())
        self._db.add(order)
        self._db.commit()
        return order
```

Do all steps of a use case, then commit **once**. If an error happens before the commit,
nothing is saved: `with SessionLocal()` rolls back on close.

## Models: typed declarative style

```python
class Order(Base):      # Base is defined below, in "Migrations"
    __tablename__ = "orders"

    id: Mapped[int] = mapped_column(primary_key=True)
    status: Mapped[OrderStatus]
    note: Mapped[str | None]
    items: Mapped[list["OrderItem"]] = relationship(back_populates="order", lazy="raise")
```

Use `Mapped[...]` + `mapped_column`, not the old `Column(...)` style.
Use the 2.0 query style: `select(...)` + `session.scalars()/execute()`, not `session.query()`.

## Avoid N+1

In sync SQLAlchemy, lazy loading works silently: one extra query per row.

Incorrect:
```python
orders = db.scalars(select(Order)).all()
for o in orders:
    print(len(o.items))          # one query per order
```

Correct:
```python
stmt = select(Order).options(selectinload(Order.items))
orders = db.scalars(stmt).all()
```

Tip: `lazy="raise"` on relationships turns a hidden N+1 into an error you see in tests.

## Queries

- Select only the columns you need for big lists
- Always paginate list endpoints
- Index columns used in filters and sorting

## Migrations (Alembic)

- Never use `Base.metadata.create_all()` in production
- `alembic revision --autogenerate`, then **review the file by hand** (renames, enums, data)
- In `env.py`, set `target_metadata = Base.metadata` and read the URL from settings
- Add a naming convention to `MetaData` so constraint names are stable:

```python
class Base(DeclarativeBase):
    metadata = MetaData(naming_convention={
        "ix": "ix_%(column_0_label)s",
        "uq": "uq_%(table_name)s_%(column_0_name)s",
        "ck": "ck_%(table_name)s_%(constraint_name)s",
        "fk": "fk_%(table_name)s_%(column_0_name)s_%(referred_table_name)s",
        "pk": "pk_%(table_name)s",
    })
```
