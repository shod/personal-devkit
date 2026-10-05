# Errors

## Domain exceptions + handlers

Services should not know about HTTP. Raise domain errors; map them in one place.

```python
class AppError(Exception):
    status_code = 500
    code = "internal_error"

class NotFoundError(AppError):
    status_code = 404
    code = "not_found"

class ConflictError(AppError):
    status_code = 409
    code = "conflict"
```

```python
@app.exception_handler(AppError)
async def app_error_handler(request: Request, exc: AppError) -> JSONResponse:
    return JSONResponse(
        status_code=exc.status_code,
        content={"error": {"code": exc.code, "message": str(exc)}},
    )
```

## HTTPException

Fine for simple cases in dependencies and routers:

```python
raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Item not found")
```

Use the `status` constants and a clear message.

## Consistent format

Pick one error shape for the whole API (`{"error": {"code", "message"}}`) and use it everywhere,
including validation errors (override `RequestValidationError` handler if needed).

## Do not leak internals

Incorrect:
```python
except Exception as e:
    raise HTTPException(500, detail=str(e))     # may show SQL, paths, secrets
```

Correct:
```python
@app.exception_handler(Exception)
async def unhandled(request: Request, exc: Exception) -> JSONResponse:
    logger.exception("Unhandled error on %s %s", request.method, request.url.path)
    return JSONResponse(status_code=500, content={"error": {"code": "internal_error"}})
```

Log the details on the server; return a short message to the client.

## Correct status codes

- `401` not authenticated (add `WWW-Authenticate`), `403` not allowed
- `404` not found, `409` conflict (duplicate), `422` invalid input
- `429` too many requests
- Do not return `200` with `{"error": ...}`
