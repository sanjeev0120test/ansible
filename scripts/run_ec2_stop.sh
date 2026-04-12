#!/usr/bin/env bash
# Stop ansible-lab EC2 instances (saves compute cost, preserves data).
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/_env.sh"
_load_ansible_env "$REPO_ROOT"
AWS_PYTHON="$(_local_aws_python "$REPO_ROOT")"
export ANSIBLE_COLLECTIONS_PATH="${HOME}/.ansible/collections"
cd "$REPO_ROOT"
ansible-playbook -i localhost, playbooks/ec2_stop.yml \
  -e "ansible_connection=local" \
  -e "ansible_python_interpreter=$AWS_PYTHON" \
  "$@"
