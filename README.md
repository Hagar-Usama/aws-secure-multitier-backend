# Notes Backend

FastAPI and SQLAlchemy provide the private Notes API. PostgreSQL is the normal persistence store; tests use isolated in-memory SQLite. The selected EC2 runtime is a Python 3.12 virtual environment supervised by `systemd`, which is smaller and simpler than requiring Docker/image retrieval in the private subnet.

## Local development

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

The local server binds to `127.0.0.1` because its browser frontend is also local. The EC2 service instead binds to `0.0.0.0:8000`; binding only `127.0.0.1` there would prevent the separate frontend EC2 instance from reaching it over the private network.

`DATABASE_URL` is required and must never be committed. The local command derives it without printing the password and URL-encodes special characters.

## Tests and API

Run tests with:

```bash
.venv/bin/python -m pytest
```

- `GET /health` returns `{"status":"healthy"}` after successful application startup.
- `GET /notes` returns notes newest first.
- `POST /notes` accepts `{"content":"..."}` (1–500 characters) and returns 201.
- `DELETE /notes/{note_id}` returns 204 or 404 when the note does not exist.

Database request failures return a generic 503 response and log only the error class, not credentials or a stack trace to API users. Open <http://127.0.0.1:8000/docs> during local development.

## Amazon Linux 2023 deployment

Prerequisites: a private-subnet Amazon Linux 2023 backend EC2 instance, this repository present on the instance, a PostgreSQL private endpoint reachable from it, and permission to use `sudo`. This deployment creates no AWS resources and does not install PostgreSQL.

Amazon Linux 2023 keeps `/usr/bin/python3` at Python 3.9; this deployment installs the separately named Python 3.12 package and does not alter the system Python. The script needs a package source for `dnf` and `pip`. In a private subnet, provide that through a prebuilt AMI, an internal package/wheel mirror, or a temporarily authorized egress path; the application itself has no ordinary public-internet dependency and does not require a NAT Gateway.

### Configure the database environment

The service reads `/etc/notes-backend/notes-backend.env`, owned by `root:notesapi` with mode `0640`. It contains exactly the runtime setting:

```bash
DATABASE_URL=postgresql+psycopg://notes_user:REDACTED@database.private.example:5432/notes_app
```

`deploy/notes-backend.env.example` is a placeholder only. On the first deployment run, the script creates the `notesapi` service account, installs this placeholder as the protected environment file, and exits without starting the service. Then edit it with the real value:

```bash
chmod +x deploy/deploy-amazon-linux.sh
sudo ./deploy/deploy-amazon-linux.sh
sudoedit /etc/notes-backend/notes-backend.env
```

For AWS, store the complete `DATABASE_URL` as a Secrets Manager secret and attach an EC2 IAM role limited to `secretsmanager:GetSecretValue` for that secret. Retrieve it through an authorized operator/SSM session and write it directly to the protected environment file; do not print it, put it in shell history, or add AWS credentials to this repository. The application and deployment script intentionally do not make AWS SDK/API calls.

### Deploy and operate

From the repository root on the backend instance:

```bash
sudo ./deploy/deploy-amazon-linux.sh
```

This second run installs the systemd unit and enables/restarts it. The script installs Python 3.12, creates the unprivileged `notesapi` account, deploys only application code and dependencies under `/opt/notes-backend`, validates the protected environment file, and manages its own service unit. Rerunning it updates only that application directory and its own service unit; it does not reset PostgreSQL or modify unrelated services.

Manage and inspect the service:

```bash
sudo systemctl status notes-backend
sudo systemctl restart notes-backend
sudo systemctl stop notes-backend
sudo journalctl -u notes-backend -n 100 --no-pager
sudo journalctl -u notes-backend -f
```

From the frontend EC2 instance or another authorized private host, verify:

```bash
curl -i http://BACKEND_PRIVATE_DNS_OR_IP:8000/health
```

If the service does not start, first inspect `journalctl`. For database connectivity failures, verify the private database DNS/endpoint, port, security-group rule, and exact `DATABASE_URL` in the protected file. Do not expose port 8000 publicly, expose PostgreSQL to the frontend/public internet, or use wildcard CORS as a workaround.

The backend security group should permit inbound TCP 8000 only from the frontend security group. The backend requires no public IP. SSM Session Manager access additionally requires an appropriate instance IAM role, connectivity to the SSM services through available network paths/endpoints, and the relevant SSM Agent support; it is not configured by this repository.

## Schema initialization limitation

Startup retains the demo's SQLAlchemy `create_all` call. It only creates missing tables; it is not a migration system and does not perform destructive schema operations. For a shared or production database, run reviewed migrations separately rather than treating application restarts as schema management.

