
#!/usr/bin/env bash
set -euo pipefail

bundle_directory="${1:-deployment-bundle}"
python_command="${PYTHON_BIN:-python3.12}"

script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
validation_directory=""

cleanup() {
    if [[ -n "$validation_directory" ]]; then
        rm -rf "$validation_directory"
    fi
}

require_compatible_python() {
    if ! command -v "$python_command" >/dev/null 2>&1; then
        echo "Python 3.12 is required to build this bundle." >&2
        exit 1
    fi

    if ! "$python_command" -c \
        'import sys; raise SystemExit(sys.version_info[:2] != (3, 12))'; then
        echo "Use Python 3.12 for the Ubuntu 24.04 target." >&2
        exit 1
    fi

    if [[ ! -f "$script_directory/requirements.txt" ]]; then
        echo "requirements.txt not found." >&2
        exit 1
    fi
}

create_bundle() {
    if [[ -e "$bundle_directory" ]]; then
        echo "Bundle output already exists: $bundle_directory" >&2
        echo "Choose another output directory or remove the old bundle manually." >&2
        exit 1
    fi

    mkdir -p "$bundle_directory/source" "$bundle_directory/wheels"

    tar -C "$script_directory" -cf - \
        app deploy tests requirements.txt README.md .env.example |
        tar -C "$bundle_directory/source" -xf -

    "$python_command" -m pip download \
        --only-binary=:all: \
        --dest "$bundle_directory/wheels" \
        -r "$script_directory/requirements.txt"
}

validate_bundle() {
    validation_directory="$(mktemp -d)"

    "$python_command" -m venv "$validation_directory/venv"

    "$validation_directory/venv/bin/python" -m pip install \
        --no-index \
        --find-links "$bundle_directory/wheels" \
        -r "$bundle_directory/source/requirements.txt"

    (
        cd "$bundle_directory/source"
        DATABASE_URL=sqlite:// \
            "$validation_directory/venv/bin/python" -m pytest -q
    )
}

trap cleanup EXIT

require_compatible_python
create_bundle
validate_bundle

echo "Validated bundle: $bundle_directory"
echo "Source: $bundle_directory/source"
echo "Wheels: $bundle_directory/wheels"
