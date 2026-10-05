# Functions and Classes

## Small functions, early return

Incorrect:
```python
def process(order):
    if order:
        if order.is_paid:
            if order.items:
                ...
```

Correct:
```python
def process(order: Order) -> None:
    if not order.is_paid:
        return
    if not order.items:
        return
    ...
```

## Keyword-only arguments

Boolean flags are hard to read at the call site. Force names with `*`.

Incorrect:
```python
send(user, True, False)
```

Correct:
```python
def send(user: User, *, urgent: bool = False, dry_run: bool = False) -> None: ...

send(user, urgent=True)
```

## Composition over inheritance

Incorrect:
```python
class EmailSender(Logger, Retrier, HttpClient): ...
```

Correct:
```python
class EmailSender:
    def __init__(self, client: HttpClient, retry: RetryPolicy) -> None:
        self._client = client
        self._retry = retry
```

Use inheritance only for a real "is-a" relation or to implement an abstract interface.

## Inject dependencies

Incorrect:
```python
class Service:
    def __init__(self):
        self.db = Database(os.environ["DB_URL"])
```

Correct:
```python
class Service:
    def __init__(self, db: Database) -> None:
        self._db = db
```

This makes testing easy: pass a fake.

## Generators for lazy data

Incorrect:
```python
def read_lines(path):
    return [line.strip() for line in open(path)]   # loads everything
```

Correct:
```python
def read_lines(path: Path) -> Iterator[str]:
    with path.open(encoding="utf-8") as f:
        for line in f:
            yield line.strip()
```

## Avoid global state

Module-level mutable state makes code hard to test. Pass state explicitly.
Module-level constants and `if __name__ == "__main__":` for entry points are fine.

## Properties

Use `@property` for cheap computed attributes. Do not write Java-style `get_x()` / `set_x()`.
Do not do slow work (network, disk) in a property.
