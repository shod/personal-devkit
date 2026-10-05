# Type Hints

## Annotate public APIs

Incorrect:
```python
def find_user(users, name):
    ...
```

Correct:
```python
def find_user(users: Sequence[User], name: str) -> User | None:
    ...
```

## Use modern syntax (3.10+)

Incorrect:
```python
from typing import List, Dict, Optional, Union
def f(a: Optional[List[int]]) -> Dict[str, Union[int, str]]: ...
```

Correct:
```python
def f(a: list[int] | None) -> dict[str, int | str]: ...
```

## Accept abstract, return concrete

Inputs: `Sequence`, `Mapping`, `Iterable` (more flexible for callers).
Outputs: `list`, `dict` (clear for callers).

```python
def total(prices: Iterable[Decimal]) -> Decimal:
    return sum(prices, Decimal(0))
```

## Avoid Any

`Any` turns off type checking. Prefer `object`, generics, `TypedDict`, or `Protocol`.

Incorrect:
```python
def parse(data: Any) -> Any: ...
```

Correct:
```python
class Event(TypedDict):
    id: int
    name: str

def parse(data: str) -> Event: ...
```

## Protocol for duck typing

```python
class SupportsClose(Protocol):
    def close(self) -> None: ...

def shutdown(resource: SupportsClose) -> None:
    resource.close()
```

## Generics (3.12 syntax)

```python
def first[T](items: Sequence[T]) -> T | None:
    return items[0] if items else None
```

On 3.11, use `TypeVar("T")` instead.

## Other useful tools

- `Literal["a", "b"]` for a small fixed set of values
- `Final` for constants, `@override` for overridden methods (3.12)
- `Self` for methods that return the same class
- `# type: ignore[code]` only with a specific code and a reason

## Enforce in CI

```toml
[tool.mypy]
strict = true
```
