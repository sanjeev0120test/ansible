#!/usr/bin/env bash
# DESTRUCTIVE — terminate all ansible-lab instances and clear .env IPs.
# Dry-run first: bash scripts/run_ec2_terminate.sh --check
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/_env.sh"
_load_ansible_env "$REPO_ROOT"
AWS_PYTHON="$(_local_aws_python "$REPO_ROOT")"
export ANSIBLE_COLLECTIONS_PATH="${HOME}/.ansible/collections"
cd "$REPO_ROOT"
echo "WARNING: This will TERMINATE all EC2 instances tagged Project=ansible-lab."
echo "Press Ctrl+C to abort, or wait 5 seconds to continue..."
sleep 5
ansible-playbook -i localhost, playbooks/ec2_terminate.yml \
  -e "ansible_connection=local" \
  -e "ansible_python_interpreter=$AWS_PYTHON" \
  "$@"
