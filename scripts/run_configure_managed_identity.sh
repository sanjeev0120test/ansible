#!/bin/bash
# Supported: run inside WSL (bash). Not intended for PowerShell.
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=scripts/_env.sh
source "$SCRIPT_DIR/_env.sh"

_load_ansible_env "$REPO_ROOT"
_require_ec2_hosts || exit 1
PEM_WSL="$(_pem_for_ssh)" || exit 1

bash "$SCRIPT_DIR/render_inventory_from_env.sh"

export ANSIBLE_COLLECTIONS_PATH="${HOME}/.ansible/collections"
cd "$REPO_ROOT"
ansible-galaxy collection install -r requirements.yml \
  -p "${HOME}/.ansible/collections" --upgrade
ansible-playbook -i inventory/hosts.autogen.yml playbooks/configure_managed_identity.yml \
  -e "ansible_ssh_private_key_file=${PEM_WSL}" "$@"
