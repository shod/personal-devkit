# Security

## Authentication

Use `OAuth2PasswordBearer` + JWT with a short life (e.g. 15 min) plus refresh tokens,
or server-side sessions. Do not invent your own token format.

```python
oauth2_scheme = OAuth2PasswordBearer(tokenUrl="auth/token")

def get_current_user(token: Annotated[str, Depends(oauth2_scheme)], db: DbSession) -> User:
    try:
        payload = jwt.decode(token, settings.secret_key.get_secret_value(), algorithms=["HS256"])
    except jwt.InvalidTokenError:          # PyJWT
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Invalid token",
                            headers={"WWW-Authenticate": "Bearer"}) from None
    ...
```

Always pass `algorithms=[...]` explicitly when decoding.

## Passwords

Hash with argon2 or bcrypt, e.g. `pwdlib` (`passlib` is no longer maintained and breaks
with new `bcrypt` versions). Never store or log plain passwords.
Use constant-time comparison; give the same error for "wrong user" and "wrong password".

## Authorization

Check permissions in dependencies, not inside business code:

```python
def require_role(role: Role):
    def checker(user: CurrentUser) -> User:
        if user.role != role:
            raise HTTPException(status.HTTP_403_FORBIDDEN, "Not allowed")
        return user
    return checker
```

Check **object ownership** too (user A must not read user B's order). This is the most common bug.

## LLM features

Prompt injection is real: text from users or documents can tell the model to do bad things.
Agent tools must check permissions themselves (user id from deps, not from arguments).
See `pydantic-ai.md`.

## CORS

Incorrect:
```python
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_credentials=True)
```

Correct:
```python
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origins,      # explicit list
    allow_credentials=True,
    allow_methods=["GET", "POST", "PUT", "DELETE"],
    allow_headers=["Authorization", "Content-Type"],
)
```

## Input limits

- Constrain strings, lists, and numbers in schemas (`max_length`, `le`)
- Limit upload size; check content type; never trust file names
- Rate limit login and expensive endpoints (e.g. `slowapi` or at the proxy)

## Secrets and config

Load from environment with `pydantic-settings`. Use `SecretStr`. Never commit `.env`.

## Production hardening

- HTTPS only; set security headers at the proxy
- Disable docs in production if the API is private: `FastAPI(docs_url=None, redoc_url=None)`
- Keep dependencies updated; run `pip-audit` in CI
