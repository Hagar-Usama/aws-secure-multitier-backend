# Notes Backend

FastAPI and SQLAlchemy provide the Notes API. Startup calls SQLAlchemy `create_all` to create the small demo schema. PostgreSQL is the normal local persistence store; tests use isolated in-memory SQLite.

## Local setup and server

From this directory, after PostgreSQL has started from the parent project:

```bash
python3 -m venv .venv
.venv/bin/python -m pip install -r requirements.txt
set -a
. ../.env
set +a
export DATABASE_URL="$(.venv/bin/python -c 'import os; from urllib.parse import quote; print("postgresql+psycopg://{}:{}@127.0.0.1:{}/{}".format(quote(os.environ["POSTGRES_USER"], safe=""), quote(os.environ["POSTGRES_PASSWORD"], safe=""), os.environ["POSTGRES_PORT"], quote(os.environ["POSTGRES_DB"], safe="")))')"
.venv/bin/python -m uvicorn app.main:app --reload --host 127.0.0.1 --port 8000
```

This derives `DATABASE_URL` from the parent `.env` without printing the password, including URL encoding for special characters. `DATABASE_URL` is required and must not be hardcoded or committed. In AWS, store the complete URL in Secrets Manager and inject it into the backend as `DATABASE_URL`.

For a future backend container on the Compose network, use `postgres` instead of `127.0.0.1` as the hostname.

## API

- `GET /health` returns `{"status":"healthy"}`.
- `GET /notes` returns notes newest first.
- `POST /notes` accepts `{"content":"..."}` (1–500 characters) and returns 201.
- `DELETE /notes/{note_id}` returns 204 or 404 when the note does not exist.

Open <http://127.0.0.1:8000/docs> for the interactive schema.

## Tests

Using the virtual environment directly:

```bash
.venv/bin/python -m pytest
```

