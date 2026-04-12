#!/usr/bin/env bash
# Shared helpers — source from repo scripts: source "$(dirname "$0")/_env.sh"
# Requires REPO_ROOT (repo root directory) to be set before calling _load_ansible_env.

_load_ansible_env() {
  local root="${1:?REPO_ROOT required}"
  # Explicitly point Ansible at our cfg so it is never skipped due to
  # world-writable directory permissions on NTFS/WSL mounts (/mnt/c/...).
  export ANSIBLE_CONFIG="${root}/ansible.cfg"
  if [ -f "$root/.env" ]; then
    set -a
    # shellcheck disable=SC1090
    . "$root/.env"
    set +a
  fi
  # Windows CRLF in .env breaks SSH / YAML
  [ -n "${EC2_HOST_SERVER1:-}" ] && export EC2_HOST_SERVER1="$(printf '%s' "$EC2_HOST_SERVER1" | tr -d '\r')"
  [ -n "${EC2_HOST_SERVER2:-}" ] && export EC2_HOST_SERVER2="$(printf '%s' "$EC2_HOST_SERVER2" | tr -d '\r')"
  [ -n "${EC2_HOST_SERVER3:-}" ] && export EC2_HOST_SERVER3="$(printf '%s' "$EC2_HOST_SERVER3" | tr -d '\r')"
  [ -n "${EC2_HOST_CLIENT:-}" ] && export EC2_HOST_CLIENT="$(printf '%s' "$EC2_HOST_CLIENT" | tr -d '\r')"
  if [ -n "${EC2_SSH_PRIVATE_KEY:-}" ]; then
    export EC2_SSH_PRIVATE_KEY="$(printf '%s' "$EC2_SSH_PRIVATE_KEY" | tr -d '\r')"
  fi
  # Strip CR from AWS / EC2 vars (Windows-saved .env)
  for v in AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_DEFAULT_REGION EC2_KEY_PAIR_NAME EC2_INSTANCE_TYPE EC2_INSTANCE_COUNT; do
    if [ -n "${!v:-}" ]; then
      export "$v"="$(printf '%s' "${!v}" | tr -d '\r')"
    fi
  done
  # Static keys in .env must win over ~/.aws named profiles (avoids confusing STS/EC2 failures).
  if [ -n "${AWS_ACCESS_KEY_ID:-}" ]; then
    unset AWS_PROFILE AWS_DEFAULT_PROFILE 2>/dev/null || true
  fi
}

# Prefer EC2_SSH_PRIVATE_KEY, then ~/.ssh/ec2-keypair.pem
_resolve_pem() {
  if [ -n "${EC2_SSH_PRIVATE_KEY:-}" ] && [ -f "${EC2_SSH_PRIVATE_KEY}" ]; then
    printf '%s' "${EC2_SSH_PRIVATE_KEY}"
    return 0
  fi
  if [ -f "${HOME}/.ssh/ec2-keypair.pem" ]; then
    printf '%s' "${HOME}/.ssh/ec2-keypair.pem"
    return 0
  fi
  echo "ERROR: Set EC2_SSH_PRIVATE_KEY in .env or copy your EC2 key to ~/.ssh/ec2-keypair.pem" >&2
  return 1
}

# OpenSSH/Ansible often break on paths with spaces — copy to a no-space path in $HOME.
_pem_for_ssh() {
  local pem
  pem="$(_resolve_pem)" || return 1
  case "$pem" in
    *" "*)
      local dest="${HOME}/.ec2-ansible-nospace.pem"
      cp -f "$pem" "$dest"
      chmod 600 "$dest"
      printf '%s' "$dest"
      ;;
    *)
      chmod 600 "$pem" 2>/dev/null || true
      printf '%s' "$pem"
      ;;
  esac
}

_require_ec2_hosts() {
  local count="${EC2_INSTANCE_COUNT:-4}"
  local vars=(EC2_HOST_SERVER1 EC2_HOST_SERVER2 EC2_HOST_SERVER3 EC2_HOST_CLIENT)
  local needed=()
  # Map instance index to variable name
  case "$count" in
    1) needed=(EC2_HOST_SERVER1) ;;
    2) needed=(EC2_HOST_SERVER1 EC2_HOST_SERVER2) ;;
    3) needed=(EC2_HOST_SERVER1 EC2_HOST_SERVER2 EC2_HOST_SERVER3) ;;
    *) needed=(EC2_HOST_SERVER1 EC2_HOST_SERVER2 EC2_HOST_SERVER3 EC2_HOST_CLIENT) ;;
  esac
  local v
  for v in "${needed[@]}"; do
    if [ -z "${!v:-}" ]; then
      echo "ERROR: Missing $v. Run: bash scripts/run_ec2_provision.sh first." >&2
      return 1
    fi
  done
  return 0
}

# Python interpreter for localhost EC2 modules (amazon.aws needs boto3).
# After bootstrap_aws.sh, boto3 lives in repo .venv — not system python3.
_local_aws_python() {
  local root="${1:?REPO_ROOT required}"
  if [ -x "$root/.venv/bin/python" ]; then
    printf '%s' "$root/.venv/bin/python"
  else
    command -v python3
  fi
}

# STS preflight using keys from the environment only (matches amazon.aws + .env workflow).
# Args: path to python (e.g. "$(_local_aws_python "$REPO_ROOT")"). Prints errors to stderr; exit 1 on failure.
_aws_sts_verify_env_or_exit() {
  local py sts_err
  py="${1:?python required}"
  sts_err=$("$py" -c "
import os, sys
import boto3
from botocore.exceptions import BotoCoreError, ClientError
k = os.environ.get('AWS_ACCESS_KEY_ID', '').strip()
s = os.environ.get('AWS_SECRET_ACCESS_KEY', '').strip()
r = os.environ.get('AWS_DEFAULT_REGION', '').strip()
if not k or not s:
    print('AWS_ACCESS_KEY_ID or AWS_SECRET_ACCESS_KEY is empty', file=sys.stderr)
    sys.exit(1)
try:
    boto3.client(
        'sts', region_name=r,
        aws_access_key_id=k, aws_secret_access_key=s,
    ).get_caller_identity()
except (ClientError, BotoCoreError) as e:
    print(e, file=sys.stderr)
    sys.exit(1)
" 2>&1) || {
    echo "ERROR: AWS credentials failed STS. Details:" >&2
    echo "$sts_err" >&2
    exit 1
  }
}
