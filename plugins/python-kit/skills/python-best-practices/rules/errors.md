# Error Handling

## Catch specific exceptions

Incorrect:
```python
try:
    data = load(path)
except:
    pass
```

Correct:
```python
try:
    data = load(path)
except FileNotFoundError:
    logger.warning("Config not found: %s", path)
    data = DEFAULT_CONFIG
```

Bare `except:` and `except Exception: pass` hide bugs. Bare `except:` also catches `KeyboardInterrupt`.

## Keep try blocks small

Incorrect:
```python
try:
    user = fetch_user(id)
    send_email(user)
    update_stats(user)
except KeyError:
    ...
```

Correct:
```python
try:
    user = fetch_user(id)
except KeyError:
    raise UserNotFoundError(id) from None
send_email(user)
update_stats(user)
```

## Keep the cause

Use `raise ... from err` to keep the original error in the traceback.

```python
try:
    value = int(raw)
except ValueError as err:
    raise ConfigError(f"Invalid port: {raw!r}") from err
```

## Domain exceptions

```python
class AppError(Exception):
    """Base class for all application errors."""

class NotFoundError(AppError): ...
class ValidationError(AppError): ...
```

Callers can catch `AppError`, or one specific child.

## EAFP over LBYL

Incorrect:
```python
if key in data:
    value = data[key]
else:
    value = default
```

Correct:
```python
value = data.get(key, default)
```

Use `try/except` when the check and the use can race (files, network).

## Clean up with context managers

Incorrect:
```python
f = open(path)
data = f.read()
f.close()
```

Correct:
```python
with open(path, encoding="utf-8") as f:
    data = f.read()
```

## Logging

- Use `logging`, not `print`. Use `logger.exception(...)` inside `except` to log the traceback.
- Pass arguments lazily: `logger.info("User %s", user_id)`.
- Log an error once, at the place where you handle it. Do not log and re-raise.
