# Style and Naming

## Let the tools format

Use `ruff format` and `ruff check`. Do not hand-format or debate line length.

## Naming

Incorrect:
```python
class user_service: ...
def GetUser(userId): ...
maxRetries = 3
```

Correct:
```python
class UserService: ...
def get_user(user_id): ...
MAX_RETRIES = 3
```

## Imports

Absolute imports, three groups (stdlib, third-party, local), no `from x import *`.

```python
import json
from pathlib import Path

import httpx

from myapp.users import UserService
```

## Paths and strings

Incorrect:
```python
path = base_dir + "/" + name + ".json"
msg = "Hello, %s. You have %d items." % (name, count)
```

Correct:
```python
path = base_dir / f"{name}.json"   # base_dir is a Path
msg = f"Hello, {name}. You have {count} items."
```

## Comprehensions

Use them for simple map/filter. If you need nested loops plus conditions, write a normal loop.

Incorrect:
```python
result = [transform(x) for row in rows for x in row if x and check(x) and x.ok]
```

Correct:
```python
result = []
for row in rows:
    for x in row:
        if x and check(x) and x.ok:
            result.append(transform(x))
```

## Truthiness and None

Incorrect:
```python
if x == None: ...
if len(items) == 0: ...
```

Correct:
```python
if x is None: ...
if not items: ...
```

Use `is None` for None checks, because `if not x` is also true for `0` and `""`.

## Docstrings

Public modules, classes, and functions get a short docstring: what it does, not how.
Comments explain *why*, not *what*.
