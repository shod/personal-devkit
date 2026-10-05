# Performance

## Measure first

Do not guess. Use `cProfile`, `py-spy`, or `timeit`. Fix the real hotspot only.

```
python -m cProfile -s cumtime script.py
```

## Pick the right data structure

Incorrect:
```python
if user_id in user_id_list:     # O(n) for every check
```

Correct:
```python
user_ids = set(user_id_list)
if user_id in user_ids:         # O(1)
```

Use `dict` for lookups, `set` for membership, `deque` for queues, `Counter` for counting.

## Strings

Incorrect:
```python
out = ""
for part in parts:
    out += part
```

Correct:
```python
out = "".join(parts)
```

## Avoid repeated work

```python
@functools.cache
def parse_rule(text: str) -> Rule: ...
```

Use it only for pure functions. On methods, it keeps `self` alive (memory leak).
Move invariant calculations out of loops.

## Lazy over eager

Use generators and `itertools` for big data. Do not build a big list just to loop once.

```python
total = sum(item.price for item in items)    # no intermediate list
```

## I/O

- Batch database and network calls; avoid one query per item (N+1)
- Read big files in streams or chunks
- Use `async` or threads for I/O-bound work, `ProcessPoolExecutor` for CPU-bound work

## Heavy numeric work

Use NumPy / pandas / Polars vectorized operations instead of Python loops.

## Anti-pattern

Do not make code unreadable for a tiny gain. Clear code that is fast enough wins.
