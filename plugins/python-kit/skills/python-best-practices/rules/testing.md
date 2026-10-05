# Testing

## Use pytest

Plain `assert`, no `unittest.TestCase` boilerplate.

```python
def test_total_includes_tax():
    order = Order(items=[Item(price=Decimal("10"))], tax_rate=Decimal("0.2"))
    assert order.total() == Decimal("12")
```

## Name tests by behavior

Incorrect: `test_1`, `test_order`.
Correct: `test_total_includes_tax`, `test_empty_cart_raises_error`.

## Parametrize instead of loops

Incorrect:
```python
def test_is_even():
    for n in (2, 4, 6):
        assert is_even(n)
```

Correct:
```python
@pytest.mark.parametrize("n", [2, 4, 6])
def test_is_even(n):
    assert is_even(n)
```

## Fixtures for setup

```python
@pytest.fixture
def user(db) -> User:
    return User.create(email="a@example.com")
```

Put shared fixtures in `conftest.py`. Use `tmp_path` for files, `monkeypatch` for env vars.

## Test exceptions

```python
with pytest.raises(ValidationError, match="age"):
    CreateUser(email="a@b.com", age=10)
```

## Mock only at boundaries

Mock network, clock, filesystem, third-party APIs. Do not mock your own internal classes:
the test then checks the mock, not the code.

Prefer fakes (small in-memory implementations) over deep `MagicMock` chains.
Patch where the name is *used*, not where it is defined.

## Test properties

- **Fast**: unit tests in milliseconds
- **Isolated**: no order dependency, no shared state
- **Deterministic**: no real time, no random without a seed, no real network

## Structure

Arrange / Act / Assert. One main reason to fail per test.
Layout: `tests/` mirrors the package. Mark slow tests: `@pytest.mark.slow`.

## Coverage

Use `pytest --cov` as a signal, not a goal. Cover branches and error paths, not getters.
