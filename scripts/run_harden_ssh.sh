#!/bin/bash
# Harden sshd_config on all Linux hosts.
# Dry-run first is strongly recommended:
#   bash scripts/run_harden_ssh.sh --check --diff
# Then apply:
#   bash scripts/run_harden_ssh.sh
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/_env.sh"

_load_ansible_env "$REPO_ROOT"
_require_ec2_hosts || exit 1
PEM="$(_pem_for_ssh)" || exit 1

bash "$SCRIPT_DIR/render_inventory_from_env.sh"

export ANSIBLE_COLLECTIONS_PATH="${HOME}/.ansible/collections"
cd "$REPO_ROOT"
ansible-playbook -i inventory/hosts.autogen.yml playbooks/harden_ssh.yml \
  -e "ansible_ssh_private_key_file=${PEM}" "$@"
