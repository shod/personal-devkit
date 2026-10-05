# Data Modeling

## Dataclasses for plain data

Incorrect:
```python
class Point:
    def __init__(self, x, y):
        self.x = x
        self.y = y
```

Correct:
```python
@dataclass(frozen=True, slots=True)
class Point:
    x: float
    y: float
```

Use `frozen=True` unless you really need mutation. `slots=True` saves memory.

## Pydantic at the boundary

Validate data where it enters the system (HTTP body, config, file, queue message).
Inside the app, pass trusted typed objects.

```python
class CreateUser(BaseModel):
    email: EmailStr
    age: int = Field(ge=18)
```

Do not use dicts with string keys as your domain model.

## Enums instead of magic strings

Incorrect:
```python
if order.status == "shipped": ...
```

Correct:
```python
class Status(StrEnum):
    PENDING = "pending"
    SHIPPED = "shipped"

if order.status is Status.SHIPPED: ...
```

## Mutable default arguments

This is a classic bug: the default value is created once and shared.

Incorrect:
```python
def add(item, items=[]):
    items.append(item)
    return items
```

Correct:
```python
def add(item, items: list | None = None):
    if items is None:
        items = []
    items.append(item)
    return items
```

Same in dataclasses:
```python
tags: list[str] = field(default_factory=list)
```

## Money and precision

Use `Decimal` for money, never `float`. Create it from a string: `Decimal("0.10")`.

## Dates and time

Use timezone-aware datetimes. Store UTC.

Incorrect:
```python
now = datetime.utcnow()      # naive, deprecated
```

Correct:
```python
now = datetime.now(UTC)
```
