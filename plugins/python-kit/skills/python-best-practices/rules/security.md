# Security

## Secrets

Incorrect:
```python
API_KEY = "sk-live-abc123"
```

Correct:
```python
API_KEY = os.environ["API_KEY"]
```

Never commit secrets. Use env vars or a secret manager. Do not log secrets or tokens.

## SQL injection

Incorrect:
```python
cursor.execute(f"SELECT * FROM users WHERE email = '{email}'")
```

Correct:
```python
cursor.execute("SELECT * FROM users WHERE email = %s", (email,))
```

With an ORM, use its query API. Never build SQL with f-strings.

## Shell commands

Incorrect:
```python
subprocess.run(f"convert {filename} out.png", shell=True)
```

Correct:
```python
subprocess.run(["convert", filename, "out.png"], check=True, timeout=30)
```

## Unsafe deserialization and eval

Never use these on untrusted data:
- `pickle.load`, `marshal` — can run arbitrary code
- `eval`, `exec`
- `yaml.load` — use `yaml.safe_load`

Use JSON or validated Pydantic models instead.

## Paths from users

Incorrect:
```python
open(UPLOAD_DIR / user_filename)      # "../../etc/passwd"
```

Correct:
```python
target = (UPLOAD_DIR / user_filename).resolve()
if not target.is_relative_to(UPLOAD_DIR.resolve()):
    raise PermissionError("Invalid path")
```

## Randomness and passwords

- Tokens and keys: `secrets.token_urlsafe()`, never `random`
- Passwords: hash with `argon2` or `bcrypt`; never MD5/SHA1; compare secrets with `hmac.compare_digest`

## HTTP clients

- Always set a timeout
- Keep TLS verification on (`verify=True`); do not disable it to "fix" an error

## Dependencies

- Pin with a lock file; run `pip-audit` in CI
- Add `bandit` or ruff's `S` rules to find common problems

## Validate input

Check type, size, and range at the boundary (Pydantic). Reject early.
