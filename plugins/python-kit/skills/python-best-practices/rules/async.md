# Async

## Do not block the event loop

Incorrect:
```python
async def fetch(url: str) -> str:
    return requests.get(url).text     # blocks every other task
```

Correct:
```python
async def fetch(client: httpx.AsyncClient, url: str) -> str:
    response = await client.get(url)
    return response.text
```

For unavoidable blocking code (CPU, old libraries), use `asyncio.to_thread(func, ...)`.

## Concurrency with TaskGroup (3.11+)

Incorrect:
```python
for url in urls:
    results.append(await fetch(client, url))   # sequential
```

Correct:
```python
async with asyncio.TaskGroup() as tg:
    tasks = [tg.create_task(fetch(client, url)) for url in urls]
results = [t.result() for t in tasks]
```

`TaskGroup` cancels the other tasks if one fails, and does not lose exceptions.

## Keep references to tasks

`asyncio.create_task()` alone can be garbage collected. Store the task, or use a `TaskGroup`.

## Always set timeouts

```python
async with asyncio.timeout(5):
    data = await fetch(client, url)
```

Also set timeouts on the client (`httpx.AsyncClient(timeout=10)`).

## Limit concurrency

```python
sem = asyncio.Semaphore(10)

async def limited(url: str) -> str:
    async with sem:
        return await fetch(client, url)
```

## Do not swallow cancellation

Do not catch `asyncio.CancelledError` unless you re-raise it after cleanup.

## Share clients

Create one `AsyncClient` / connection pool and reuse it. Do not create one per request.

## Entry point

One `asyncio.run(main())` at the top. Never call it inside async code.
