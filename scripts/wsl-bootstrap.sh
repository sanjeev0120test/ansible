#!/bin/bash
# One-shot: normalize CRLF on shell scripts, install collections, run main playbook.
# From Windows: wsl -e bash /mnt/c/dev/ansible/ansible/scripts/wsl-bootstrap.sh
set -e
REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO"
for f in scripts/*.sh scripts/_env.sh; do
  [ -f "$f" ] && sed -i 's/\r$//' "$f" 2>/dev/null || true
done
export ANSIBLE_COLLECTIONS_PATH="${HOME}/.ansible/collections"
ansible-galaxy collection install -r requirements.yml -p "${HOME}/.ansible/collections"
bash scripts/run_configure_managed_identity.sh
