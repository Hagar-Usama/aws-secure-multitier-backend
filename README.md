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

Amazon Linux 2023 keeps `/usr/bin/python3` at Python 3.9; this deployment uses the separately named Python 3.12 runtime and does not alter the system Python. The deployment script installs Python only when `/usr/bin/python3.12` is absent. Application dependencies are always installed from a supplied wheelhouse with `pip --no-index`, never from PyPI on the backend instance.

### Configure the database environment

The service reads `/etc/notes-backend/notes-backend.env`, owned by `root:notesapi` with mode `0640`. It contains exactly the runtime setting:

```bash
DATABASE_URL=postgresql+psycopg://notes_user:REDACTED@database.private.example:5432/notes_app
```

`deploy/notes-backend.env.example` is a placeholder only. On the first deployment run, the script creates the `notesapi` service account, installs this placeholder as the protected environment file, and exits before Python, package, or application installation. Then edit it with the real value:

```bash
chmod +x deploy/deploy-amazon-linux.sh
sudo ./deploy/deploy-amazon-linux.sh
sudoedit /etc/notes-backend/notes-backend.env
```

For AWS, store the complete `DATABASE_URL` as a Secrets Manager secret and attach an EC2 IAM role limited to `secretsmanager:GetSecretValue` for that secret. Retrieve it through an authorized operator/SSM session and write it directly to the protected environment file; do not print it, put it in shell history, or add AWS credentials to this repository. The application and deployment script intentionally do not make AWS SDK/API calls.

### Build a private deployment bundle

Build the bundle on Amazon Linux 2023 with Python 3.12 and the same CPU architecture as the target EC2 instance. This builder downloads only binary wheels, copies the backend source, creates a clean temporary validation environment, installs from the local wheelhouse with `--no-index`, and runs the tests:

```bash
cd backend
chmod +x deploy/build-deployment-bundle.sh
./deploy/build-deployment-bundle.sh deployment-bundle
tar -C deployment-bundle -czf notes-backend-bundle.tar.gz .
```

Do not build the bundle on an incompatible operating system or CPU architecture. Upload `notes-backend-bundle.tar.gz` to a private S3 bucket from the build environment.

### Retrieve and deploy without a NAT Gateway

Give the backend EC2 instance an IAM role limited to `s3:GetObject` for the deployment-bundle object and use an S3 Gateway VPC Endpoint with an endpoint policy limited to that bucket/prefix. No AWS keys are placed in the application, script, or environment file. On the instance, retrieve and extract the bundle using the instance role:

```bash
mkdir -p ~/notes-backend-release
aws s3 cp s3://YOUR_PRIVATE_BUCKET/notes-backend/notes-backend-bundle.tar.gz \
  ~/notes-backend-release/notes-backend-bundle.tar.gz
tar -xzf ~/notes-backend-release/notes-backend-bundle.tar.gz -C ~/notes-backend-release
cd ~/notes-backend-release/source
```

The `aws` command uses the EC2 role; it must already be installed (or included in a prebuilt AMI). The source and wheel bundle cross only the S3 Gateway Endpoint, not the public internet.

On the first run, provide the wheel directory but expect an early exit after the placeholder environment file is created:

```bash
chmod +x deploy/deploy-amazon-linux.sh
sudo WHEELHOUSE="$PWD/../wheels" ./deploy/deploy-amazon-linux.sh
sudoedit /etc/notes-backend/notes-backend.env
```

After securely setting the real `DATABASE_URL`, run the same command again:

```bash
sudo WHEELHOUSE="$PWD/../wheels" ./deploy/deploy-amazon-linux.sh
```

The second run validates `DATABASE_URL` and `WHEELHOUSE` before it installs Python or application dependencies, then installs the systemd unit and enables/restarts it. Rerunning it updates only that application directory and its own service unit; it does not reset PostgreSQL or modify unrelated services.

Remaining package-source requirements are explicit: if Python 3.12 is not baked into the AMI, `dnf install python3.12 python3.12-pip` needs an approved Amazon Linux RPM source. The `aws` CLI must also already be present or installed from an approved source. The wheel bundle removes the need for backend access to PyPI, but this procedure is not fully offline unless Python 3.12 and the AWS CLI are already present on the image.

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


## Ubuntu 24.04 LTS deployment

The backend runs as a systemd service on a private Ubuntu Server 24.04 LTS EC2 instance. PostgreSQL remains a separate private database service.

The backend instance must have these prerequisites already available:

- Python 3.12 at `/usr/bin/python3.12`.
- Python virtual-environment support.
- AWS CLI configured to use the EC2 instance IAM role.
- A route to the S3 Gateway VPC Endpoint.
- Permission to retrieve the deployment bundle from the designated S3 object.

The deployment script does not create AWS resources or install operating-system packages. Prepare these prerequisites in the AMI or another approved provisioning process. Do not depend on a NAT Gateway.

### Build the deployment bundle

On an Ubuntu 24.04 build environment using Python 3.12 and the same CPU architecture as the backend instance:

```bash
chmod +x deploy/build-deployment-bundle.sh
./deploy/build-deployment-bundle.sh deployment-bundle
tar -C deployment-bundle -czf notes-backend-bundle.tar.gz .
```

The bundle contains the application source and prebuilt dependency wheels. The builder installs dependencies offline in a temporary environment and runs the backend tests.

Upload `notes-backend-bundle.tar.gz` to a private S3 bucket using an authorized build environment. The backend EC2 role should have permission to read only the required object or prefix.

### Retrieve the bundle on the backend instance

Use the EC2 instance role to download the bundle through the S3 Gateway VPC Endpoint:

```bash
mkdir -p ~/notes-backend-release

aws s3 cp \
  s3://YOUR_PRIVATE_BUCKET/notes-backend/notes-backend-bundle.tar.gz \
  ~/notes-backend-release/notes-backend-bundle.tar.gz

tar -xzf ~/notes-backend-release/notes-backend-bundle.tar.gz \
  -C ~/notes-backend-release

cd ~/notes-backend-release/source
```

Replace the bucket and object path with the values used for your deployment.

### Configure the database URL

On the first run, the deployment script creates the protected environment file and exits:

```bash
chmod +x deploy/deploy-ubuntu.sh

sudo env WHEELHOUSE="$HOME/notes-backend-release/wheels" \
  ./deploy/deploy-ubuntu.sh
```

Edit `/etc/notes-backend/notes-backend.env` using an approved secure process. It must contain a valid `DATABASE_URL` for the private PostgreSQL endpoint. Do not commit real credentials or put secrets in shell history.

For AWS, retrieve the secret through an authorized mechanism such as SSM Session Manager and AWS Secrets Manager. The EC2 instance needs the appropriate IAM permissions and network connectivity to the relevant services.

After configuring the environment file, rerun the deployment command:

```bash
sudo env WHEELHOUSE="$HOME/notes-backend-release/wheels" \
  ./deploy/deploy-ubuntu.sh
```

The script installs the application dependencies from the local wheelhouse using `pip --no-index`, installs the systemd unit, and enables the service.

### Verify the service

```bash
sudo systemctl status notes-backend
sudo journalctl -u notes-backend -n 100 --no-pager

curl -i http://BACKEND_PRIVATE_DNS_OR_IP:8000/health
```

The backend security group should allow inbound TCP 8000 only from the frontend security group. Do not expose the backend or PostgreSQL to the public internet.

The backend still needs Python 3.12, virtual-environment support, AWS CLI, and S3 access before deployment. The wheel bundle does not supply those operating-system prerequisites.
