#!/usr/bin/env bash
set -euo pipefail

script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
application_directory="/opt/notes-backend"
environment_directory="/etc/notes-backend"
environment_file="$environment_directory/notes-backend.env"
service_file="/etc/systemd/system/notes-backend.service"
wheelhouse="${WHEELHOUSE:-}"

require_root() {
  if [[ "$EUID" -ne 0 ]]; then
    echo "Run this script with sudo." >&2
    exit 1
  fi
}

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing prerequisite command: $1" >&2
    exit 1
  fi
}

create_service_user() {
  if ! id notesapi >/dev/null 2>&1; then
    useradd --system --home-dir "$application_directory" --shell /sbin/nologin notesapi
  fi
}

prepare_environment_file() {
  install -d -o root -g notesapi -m 0750 "$environment_directory"
  if [[ ! -f "$environment_file" ]]; then
    install -o root -g notesapi -m 0640 "$script_directory/deploy/notes-backend.env.example" "$environment_file"
    echo "Create $environment_file with the real DATABASE_URL, then rerun this script." >&2
    exit 1
  fi
  chown root:notesapi "$environment_file"
  chmod 0640 "$environment_file"
}

validate_deployment_inputs() {
  local database_url
  database_url="$(sed -n 's/^DATABASE_URL=//p' "$environment_file" | tail -n 1)"
  if [[ -z "$database_url" ]] || [[ "$database_url" == *"replace-with-secret"* ]]; then
    echo "DATABASE_URL is not configured in $environment_file." >&2
    exit 1
  fi
  if [[ "$database_url" != postgresql+psycopg://* ]]; then
    echo "DATABASE_URL must use the postgresql+psycopg:// scheme." >&2
    exit 1
  fi
  if [[ -z "$wheelhouse" ]] || [[ ! -d "$wheelhouse" ]]; then
    echo "Set WHEELHOUSE to the deployment bundle's wheels directory." >&2
    exit 1
  fi
  if [[ ! -d "$script_directory/app" ]] || [[ ! -f "$script_directory/requirements.txt" ]]; then
    echo "Run this script from the deployment bundle's source directory." >&2
    exit 1
  fi
}

install_python_if_needed() {
  if [[ ! -x /usr/bin/python3.12 ]]; then
    require_command dnf
    dnf install -y python3.12 python3.12-pip
  fi
}

deploy_application() {
  install -d -o notesapi -g notesapi -m 0755 "$application_directory"
  tar -C "$script_directory" -cf - app requirements.txt | tar -C "$application_directory" -xf -
  chown -R notesapi:notesapi "$application_directory/app" "$application_directory/requirements.txt"
  runuser -u notesapi -- /usr/bin/python3.12 -m venv "$application_directory/.venv"
  runuser -u notesapi -- "$application_directory/.venv/bin/python" -m pip install \
    --no-index --find-links "$wheelhouse" -r "$application_directory/requirements.txt"
}

install_service() {
  install -o root -g root -m 0644 "$script_directory/deploy/notes-backend.service" "$service_file"
  systemctl daemon-reload
  systemctl enable notes-backend
  systemctl restart notes-backend
}

require_root
create_service_user
prepare_environment_file
validate_deployment_inputs
require_command install
require_command runuser
require_command sed
require_command systemctl
require_command tar
install_python_if_needed
deploy_application
install_service
echo "Notes backend is managed by systemd as notes-backend."
