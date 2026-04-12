#!/usr/bin/env bash
# DESTRUCTIVE — terminates ALL EC2 instances + EBS volumes + EIPs + Ansible SGs in the
# configured AWS region. Zeroes all billable resources created by this lab.
#
# Safety: shows a dry-run preview first, then requires you to type "yes".
# Dry-run only (no changes): bash scripts/run_ec2_nuke.sh --check
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/_env.sh"
_load_ansible_env "$REPO_ROOT"
AWS_PYTHON="$(_local_aws_python "$REPO_ROOT")"
export ANSIBLE_COLLECTIONS_PATH="${HOME}/.ansible/collections"
cd "$REPO_ROOT"

REGION="${AWS_DEFAULT_REGION:-<not set>}"

# ── Dry-run / --check passthrough ─────────────────────────────────────────────
if [[ "${1:-}" == "--check" ]]; then
  echo ""
  echo "====================================================="
  echo "  DRY-RUN: ec2_nuke — region: ${REGION}"
  echo "  No changes will be made."
  echo "====================================================="
  echo ""
  ansible-playbook -i localhost, playbooks/ec2_nuke.yml \
    -e "ansible_connection=local" \
    -e "ansible_python_interpreter=$AWS_PYTHON" \
    --check
  echo ""
  echo "Re-run without --check to proceed with actual deletion."
  exit 0
fi

# ── Interactive mode ──────────────────────────────────────────────────────────
echo ""
echo "╔════════════════════════════════════════════════════════════════════╗"
echo "║  ⚠  AWS ACCOUNT NUKE — IRREVERSIBLE OPERATION                    ║"
echo "╠════════════════════════════════════════════════════════════════════╣"
echo "║  Region : ${REGION}"
echo "║  Deletes: ALL EC2 instances, detached EBS volumes, unassociated   ║"
echo "║           Elastic IPs, and Ansible-managed security groups.       ║"
echo "╚════════════════════════════════════════════════════════════════════╝"
echo ""
echo "Running dry-run preview first..."
echo "---------------------------------------------------------------------"
ansible-playbook -i localhost, playbooks/ec2_nuke.yml \
  -e "ansible_connection=local" \
  -e "ansible_python_interpreter=$AWS_PYTHON" \
  --check
echo "---------------------------------------------------------------------"
echo ""
echo "The above shows what WILL BE DELETED."
echo ""
read -r -p "Type 'yes' to proceed with ACTUAL deletion, or anything else to abort: " answer
if [[ "$answer" != "yes" ]]; then
  echo "Aborted. Nothing was deleted."
  exit 0
fi

echo ""
echo "Proceeding with deletion in region: ${REGION}..."
echo ""
NUKE_CONFIRMED=yes ansible-playbook -i localhost, playbooks/ec2_nuke.yml \
  -e "ansible_connection=local" \
  -e "ansible_python_interpreter=$AWS_PYTHON" \
  -e "nuke_confirmed=yes" \
  "$@"
