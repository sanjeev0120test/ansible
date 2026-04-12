#!/usr/bin/env bash
# ============================================================
# Bootstrap AWS + Ansible collection dependencies in WSL.
#
# Debian/Ubuntu 24.04+ blocks `pip3 install --user` (PEP 668). This script
# creates a repo-local virtualenv at .venv/ and installs boto3 there.
#
# Installs: boto3, botocore, awscli (inside .venv)
# Then: ansible-galaxy install -r requirements.yml (posix, community.general, amazon.aws)
#
# Prefer: bash scripts/install_dependencies.sh (also ensures apt ansible + python3-venv).
# Run standalone after deleting .venv or to refresh collections / Python deps.
# ============================================================
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
VENV="$REPO_ROOT/.venv"

echo "========================================================"
echo "  AWS Bootstrap — installing dependencies in WSL"
echo "  venv : $VENV"
echo "========================================================"
echo ""

# ── python3-venv (required for `python3 -m venv`) ─────────────────────────────
echo "[1/5] Ensuring python3-venv is installed..."
if ! python3 -c "import venv" 2>/dev/null; then
  sudo apt-get update -qq
  sudo apt-get install -y python3-venv
fi
echo "      OK"

# ── Create virtualenv ─────────────────────────────────────────────────────────
echo ""
echo "[2/5] Creating repo virtualenv (.venv)..."
if [ ! -x "$VENV/bin/python" ]; then
  python3 -m venv "$VENV"
fi
echo "      $VENV"

# ── pip packages (inside venv — no PEP 668 conflict) ──────────────────────────
echo ""
echo "[3/5] Installing boto3 + botocore + awscli into .venv..."
# Use `python -m pip` (not `.venv/bin/pip`) — on WSL + NTFS (/mnt/c/...) the pip
# launcher script can fail with "No such file or directory" while the venv python works.
"$VENV/bin/python" -m pip install -q -U pip wheel
"$VENV/bin/python" -m pip install -q boto3 botocore awscli
BOTO3_VER=$("$VENV/bin/python" -c "import boto3; print(boto3.__version__)")
echo "      boto3 $BOTO3_VER"

# ── AWS CLI sanity check ───────────────────────────────────────────────────────
echo ""
echo "[4/5] AWS CLI (pip package awscli)..."
AWSCLI_VER=$("$VENV/bin/python" -m pip show awscli 2>/dev/null | awk -F': ' '/^Version:/{print $2}')
echo "      awscli ${AWSCLI_VER:-installed}"
if [ -x "$VENV/bin/aws" ]; then
  "$VENV/bin/aws" --version 2>&1 || echo "      (tip: if aws launcher fails on /mnt/c, use: $VENV/bin/python -m pip show awscli)"
fi

# ── Ansible collections (required by ansible.cfg callbacks + roles + EC2) ─────
echo ""
echo "[5/5] Installing collections from requirements.yml..."
export ANSIBLE_CONFIG="$REPO_ROOT/ansible.cfg"
ansible-galaxy collection install -r "$REPO_ROOT/requirements.yml" \
  -p "${HOME}/.ansible/collections" --upgrade 2>&1 | tail -15

# ── Credential guidance ───────────────────────────────────────────────────────
echo ""
echo "========================================================"
echo "  Setup complete. EC2 playbooks use: $VENV/bin/python"
echo "========================================================"
echo ""
echo "  Use AWS CLI from venv (optional):"
echo "    $VENV/bin/aws --version"
echo "    $VENV/bin/aws sts get-caller-identity"
echo ""
echo "  Option A — add to .env (recommended for this repo):"
echo "    AWS_ACCESS_KEY_ID=AKIA..."
echo "    AWS_SECRET_ACCESS_KEY=..."
echo "    AWS_DEFAULT_REGION=us-east-1   # US East (N. Virginia); must match console region"
echo "    EC2_KEY_PAIR_NAME=your-keypair-name  # name in AWS console"
echo "    EC2_INSTANCE_COUNT=2                 # 1–4 (free tier: max 2)"
echo "    EC2_INSTANCE_TYPE=t3.micro           # AWS Free Tier lab standard (us-east-1)"
echo ""
echo "  Option B — AWS CLI interactive (use venv binary):"
echo "    $VENV/bin/aws configure"
echo "    (then add EC2_KEY_PAIR_NAME + EC2_INSTANCE_COUNT + EC2_INSTANCE_TYPE to .env)"
echo ""
echo "  Get keys from:"
echo "    AWS Console → IAM → Users → Security Credentials → Access keys"
echo ""
echo "  After setup, verify: bash scripts/check_setup.sh"
echo ""
