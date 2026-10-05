# Schemas (Pydantic v2)

## Separate input and output models

Incorrect (one model for all; leaks the password hash):
```python
class User(BaseModel):
    id: int
    email: str
    password_hash: str
```

Correct:
```python
class UserBase(BaseModel):
    email: EmailStr

class UserCreate(UserBase):
    password: SecretStr = Field(min_length=12)

class UserUpdate(BaseModel):
    email: EmailStr | None = None

class UserRead(UserBase):
    model_config = ConfigDict(from_attributes=True)
    id: int
```

## Always set response_model

It filters the output, so extra fields (secrets, internal data) never leave the API.

```python
@router.get("/{id}", response_model=UserRead)
```

Better: use the return type annotation (`-> UserRead`) when you return a matching model.

## Partial updates

```python
changes = data.model_dump(exclude_unset=True)
for key, value in changes.items():
    setattr(user, key, value)
```

Use `exclude_unset=True` so the client can tell "not sent" from "set to null".

## Validation

```python
class ItemCreate(BaseModel):
    name: str = Field(min_length=1, max_length=100)
    price: Decimal = Field(gt=0, max_digits=10, decimal_places=2)
    tags: list[str] = Field(default_factory=list, max_length=20)
```

Cross-field rules with `model_validator`:

```python
class PeriodCreate(BaseModel):
    start: datetime
    end: datetime

    @model_validator(mode="after")
    def check_dates(self) -> Self:
        if self.end <= self.start:
            raise ValueError("end must be after start")
        return self
```

Use `Literal` or `StrEnum` for fixed sets of values.

## Forbid unknown fields on input

```python
model_config = ConfigDict(extra="forbid")
```

## Pagination response

```python
class Page[T](BaseModel):          # Python 3.12 generic syntax
    items: list[T]
    total: int
    limit: int
    offset: int
```

## Money and time

`Decimal` for money, not `float`. Timezone-aware `datetime` (UTC) in the API.
