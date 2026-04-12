#!/usr/bin/env bash
# If multiple EC2 instances share the same ansible-lab Number tag, terminate the newer
# duplicates (keeps oldest per slot). Dry-run by default; pass --apply to execute.
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=scripts/_env.sh
source "$SCRIPT_DIR/_env.sh"
_load_ansible_env "$REPO_ROOT"
PY="$(_local_aws_python "$REPO_ROOT")"
exec "$PY" "$SCRIPT_DIR/_terminate_duplicate_lab_slots.py" "$@"
