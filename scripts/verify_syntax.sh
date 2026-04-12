#!/usr/bin/env bash
# Syntax-check every playbook (no SSH, no AWS calls).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
export ANSIBLE_CONFIG="$REPO_ROOT/ansible.cfg"
cd "$REPO_ROOT"

SSH_INV=(inventory/hosts.SAMPLE.yml)
LOCAL_INV=(localhost,)

for f in \
  playbooks/ping.yml \
  playbooks/gather_facts.yml \
  playbooks/site.yml \
  playbooks/harden_ssh.yml \
  playbooks/create_linux_users.yml \
  playbooks/configure_managed_identity.yml \
  playbooks/report_audit.yml \
  playbooks/report_security.yml
do
  ansible-playbook --syntax-check -i "${SSH_INV[@]}" "$f"
  echo "OK $f"
done

for f in \
  playbooks/ec2_status.yml \
  playbooks/ec2_provision.yml \
  playbooks/ec2_stop.yml \
  playbooks/ec2_start.yml \
  playbooks/ec2_terminate.yml \
  playbooks/ec2_nuke.yml
do
  ansible-playbook --syntax-check -i "${LOCAL_INV[@]}" "$f" \
    -e ansible_connection=local
  echo "OK $f"
done

echo "All playbooks: syntax OK"
