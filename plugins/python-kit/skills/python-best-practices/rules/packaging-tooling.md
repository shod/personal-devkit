# Project Layout and Tooling

## pyproject.toml is the single config

No `setup.py`, `setup.cfg`, or hand-maintained `requirements.txt`.

```toml
[project]
name = "myapp"
version = "0.1.0"
requires-python = ">=3.11"
dependencies = ["httpx>=0.27", "pydantic>=2"]

[dependency-groups]
dev = ["pytest", "pytest-cov", "ruff", "mypy"]

[tool.ruff]
line-length = 100

[tool.ruff.lint]
select = ["E", "F", "I", "B", "UP", "SIM", "ASYNC", "S", "RUF"]

[tool.mypy]
strict = true

[tool.pytest.ini_options]
addopts = "-ra --strict-markers"
testpaths = ["tests"]
```

## Layout

```
myapp/
├── pyproject.toml
├── uv.lock
├── src/myapp/
│   ├── __init__.py
│   └── ...
└── tests/
```

`src/` layout stops you from importing the package by accident from the working directory.

## Dependencies

- Use `uv` (or poetry) and **commit the lock file** for apps
- Put dev tools in a dev group, not in runtime dependencies
- Set lower bounds in libraries; avoid tight upper pins
- One virtual environment per project (`.venv`); never install into system Python

## Quality gate (local + CI)

```
ruff format --check .
ruff check .
mypy src
pytest
```

Run the same commands in pre-commit and in CI.

## Configuration

Read config from environment variables (`pydantic-settings`), once, at startup.
Keep `.env` out of git; commit `.env.example`.

## Logging setup

Configure logging once in the entry point, not in library modules.
Libraries only use `logger = logging.getLogger(__name__)`.

## Entry points

```toml
[project.scripts]
myapp = "myapp.cli:main"
```
