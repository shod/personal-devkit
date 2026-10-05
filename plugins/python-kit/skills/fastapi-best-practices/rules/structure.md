# Project Structure

## Group by domain

Incorrect (by file type, grows into a mess):
```
app/
├── routers/users.py, orders.py
├── models/users.py, orders.py
└── schemas/users.py, orders.py
```

Correct (by domain):
```
src/
├── main.py
├── config.py
├── database.py
├── exceptions.py
├── users/
│   ├── router.py
│   ├── schemas.py
│   ├── models.py
│   ├── service.py
│   ├── dependencies.py
│   └── exceptions.py
├── ai/                    # PydanticAI agents, their deps and tools
│   └── support_agent.py
└── orders/
    └── ...
```

Import across domains with explicit module names: `from src.users import service as users_service`.

## Thin routers, logic in services

Incorrect:
```python
@router.post("/orders")
def create_order(data: OrderCreate, db: Session = Depends(get_db)):
    user = db.execute(select(User).where(User.id == data.user_id)).scalar_one()
    total = sum(i.price * i.qty for i in data.items)
    ...
```

Correct:
```python
@router.post("/orders", status_code=status.HTTP_201_CREATED, response_model=OrderRead)
def create_order(data: OrderCreate, service: OrderServiceDep) -> Order:
    return service.create(data)
```

The router parses HTTP and calls the service. The service holds business rules and can be tested without HTTP.

## App factory and routers

```python
def create_app() -> FastAPI:
    app = FastAPI(title="My API", lifespan=lifespan)
    app.include_router(users_router, prefix="/users", tags=["users"])
    app.include_router(orders_router, prefix="/orders", tags=["orders"])
    return app

app = create_app()
```

## Versioning

Prefix the API: `/api/v1`. Keep old versions in separate routers when you make breaking changes.

## Settings

One `Settings` class (`pydantic-settings`) in `config.py`, loaded once and cached:

```python
class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env")
    database_url: str              # postgresql+psycopg://...
    secret_key: SecretStr
    llm_model: str                 # PydanticAI model name with provider prefix

@lru_cache
def get_settings() -> Settings:
    return Settings()
```
