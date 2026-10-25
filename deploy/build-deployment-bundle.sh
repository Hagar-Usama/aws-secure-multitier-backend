#!/usr/bin/env bash
set -euo pipefail

bundle_directory="${1:-deployment-bundle}"
python_command="${PYTHON_BIN:-python3.12}"
script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
validation_directory=""

cleanup_validation_directory() {
  if [[ -n "$validation_directory" ]]; then
    rm -rf "$validation_directory"
  fi
}

require_compatible_python() {
  if ! command -v "$python_command" >/dev/null 2>&1; then
    echo "Install Python 3.12 or set PYTHON_BIN to a compatible Python 3.12 executable." >&2
    exit 1
  fi
  if ! "$python_command" -c 'import sys; raise SystemExit(sys.version_info[:2] != (3, 12))'; then
    echo "Build the bundle with Python 3.12, matching the Amazon Linux deployment runtime." >&2
    exit 1
  fi
}

create_bundle() {
  if [[ -e "$bundle_directory" ]]; then
    echo "Bundle output already exists: $bundle_directory" >&2
    exit 1
  fi
  mkdir -p "$bundle_directory/source" "$bundle_directory/wheels"
  tar -C "$script_directory" -cf - app deploy tests requirements.txt README.md .env.example | \
    tar -C "$bundle_directory/source" -xf -
  "$python_command" -m pip download --only-binary=:all: --dest "$bundle_directory/wheels" \
    -r "$script_directory/requirements.txt"
}

validate_bundle() {
  validation_directory="$(mktemp -d)"
  "$python_command" -m venv "$validation_directory/venv"
  "$validation_directory/venv/bin/python" -m pip install --no-index \
    --find-links "$bundle_directory/wheels" -r "$bundle_directory/source/requirements.txt"
  (
    cd "$bundle_directory/source"
    DATABASE_URL=sqlite:// "$validation_directory/venv/bin/python" -m pytest -q
  )
}

trap cleanup_validation_directory EXIT
require_compatible_python
create_bundle
validate_bundle
echo "Validated deployment bundle: $bundle_directory"
