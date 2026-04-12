#!/bin/bash
# Gather and display EC2 instance facts (OS, vCPUs, RAM, disk, network).
# Pass extra flags: bash scripts/run_facts.sh -v
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
ansible-playbook -i inventory/hosts.autogen.yml playbooks/gather_facts.yml \
  -e "ansible_ssh_private_key_file=${PEM}" "$@"
