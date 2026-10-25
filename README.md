# Notes Backend

FastAPI and SQLAlchemy provide the Notes API. Startup calls SQLAlchemy `create_all` to create the small demo schema. PostgreSQL is the normal local persistence store; tests use isolated in-memory SQLite.

## Local setup and server

From this directory, after PostgreSQL has started from the parent project:

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
export DATABASE_URL='postgresql+psycopg://notes_user:YOUR_POSTGRES_PASSWORD@127.0.0.1:5432/notes_app'
uvicorn app.main:app --reload --host 127.0.0.1 --port 8000
```

Set `YOUR_POSTGRES_PASSWORD` to the value in the parent `.env`. `DATABASE_URL` is required and must not be hardcoded or committed. `backend/.env.example` shows the expected host-run URL, but Uvicorn requires the value to be exported or loaded into the environment.

For a future backend container on the Compose network, use `postgres` instead of `127.0.0.1` as the hostname.

## API

- `GET /health` returns `{"status":"healthy"}`.
- `GET /notes` returns notes newest first.
- `POST /notes` accepts `{"content":"..."}` (1–500 characters) and returns 201.
- `DELETE /notes/{note_id}` returns 204 or 404 when the note does not exist.

Open <http://127.0.0.1:8000/docs> for the interactive schema.

## Tests

With the virtual environment active:

```bash
pytest
```

