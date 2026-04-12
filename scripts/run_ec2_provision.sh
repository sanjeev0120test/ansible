#!/usr/bin/env bash
# Provision EC2 instances (see EC2_INSTANCE_TYPE in .env; default t3.micro).
# Requires: boto3 + AWS credentials + EC2_KEY_PAIR_NAME in .env
# Run bootstrap first if not done: bash scripts/bootstrap_aws.sh
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/_env.sh"
_load_ansible_env "$REPO_ROOT"
AWS_PYTHON="$(_local_aws_python "$REPO_ROOT")"

# Fail fast with a clear message (playbook assert is easy to misread).
if [ -z "${AWS_DEFAULT_REGION:-}" ]; then
  echo "ERROR: Set AWS_DEFAULT_REGION in .env to match your EC2 console (e.g. us-east-1 for US East N. Virginia)." >&2
  exit 1
fi
if [ -z "${EC2_KEY_PAIR_NAME:-}" ]; then
  echo "ERROR: Set EC2_KEY_PAIR_NAME in .env." >&2
  echo "  This is the Key pair NAME in AWS Console → EC2 → Key Pairs (e.g. my-laptop-key)." >&2
  echo "  It is NOT the path to your .pem — use EC2_SSH_PRIVATE_KEY or ~/.ssh/ec2-keypair.pem for SSH." >&2
  exit 1
fi
if [ -z "${AWS_ACCESS_KEY_ID:-}" ] || [ -z "${AWS_SECRET_ACCESS_KEY:-}" ]; then
  echo "ERROR: AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY must both be set in .env for provisioning." >&2
  exit 1
fi
_aws_sts_verify_env_or_exit "$AWS_PYTHON"

export ANSIBLE_COLLECTIONS_PATH="${HOME}/.ansible/collections"
cd "$REPO_ROOT"
ansible-galaxy collection install -r requirements.yml \
  -p "${HOME}/.ansible/collections" --upgrade
ansible-playbook -i localhost, playbooks/ec2_provision.yml \
  -e "ansible_connection=local" \
  -e "ansible_python_interpreter=$AWS_PYTHON" \
  "$@"
