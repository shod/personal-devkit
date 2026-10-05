# Routes and Dependencies

## Use Annotated dependencies

Incorrect:
```python
@router.get("/me")
def me(user: User = Depends(get_current_user), db: Session = Depends(get_db)): ...
```

Correct:
```python
CurrentUser = Annotated[User, Depends(get_current_user)]
DbSession = Annotated[Session, Depends(get_db)]

@router.get("/me", response_model=UserRead)
def me(user: CurrentUser) -> User:
    return user
```

Define aliases once, reuse everywhere.

## def or async def

Endpoints and dependencies that use the sync DB are plain `def`.
`async def` only when everything inside is awaited. Details in `database.md`.

## Be explicit on routes

```python
@router.post(
    "/",
    status_code=status.HTTP_201_CREATED,
    response_model=ItemRead,
    summary="Create an item",
)
```

Use correct codes: `201` create, `204` delete (no body), `404` not found, `409` conflict, `422` validation.

## Validate params

```python
@router.get("/{item_id}")
def get_item(
    item_id: Annotated[int, Path(gt=0)],
    include: Annotated[str | None, Query(max_length=50)] = None,
): ...
```

## Dependencies for shared checks

Incorrect (same lookup copied into many routes):
```python
item = db.get(Item, item_id)
if not item:
    raise HTTPException(404)
```

Correct:
```python
def valid_item(item_id: int, db: DbSession) -> Item:
    item = db.get(Item, item_id)
    if item is None:
        raise ItemNotFound(item_id)
    return item

ValidItem = Annotated[Item, Depends(valid_item)]

@router.get("/{item_id}", response_model=ItemRead)
def read_item(item: ValidItem) -> Item:
    return item
```

FastAPI caches a dependency per request, so it runs once even if used several times.

## Dependencies on a whole router

```python
router = APIRouter(dependencies=[Depends(require_admin)])
```

## Yield dependencies for resources

```python
def get_db() -> Iterator[Session]:
    with SessionLocal() as session:
        yield session
```

The code after `yield` runs after the response is sent (default `scope="request"`).
Use `Depends(get_db, scope="function")` to clean up before the response. See `database.md`.

## Pagination dependency

```python
class Pagination(BaseModel):
    limit: int = Field(20, ge=1, le=100)
    offset: int = Field(0, ge=0)

PageParams = Annotated[Pagination, Query()]
```

## Content type

Since FastAPI 0.132, JSON requests must have `Content-Type: application/json`
(`strict_content_type`). Keep it on; disable only for old clients you cannot fix.
