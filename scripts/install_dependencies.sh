#!/usr/bin/env bash
# ============================================================
# One-shot dependency install for this repo (open-source stack only).
#
# Installs on Debian/Ubuntu/WSL:
#   • ansible (apt) — if ansible-playbook is missing
#   • python3-venv (apt) — if venv module is missing
# Then runs bootstrap_aws.sh:
#   • .venv with boto3/botocore/awscli (PEP 668–safe)
#   • all collections in requirements.yml (ansible.posix, community.general, amazon.aws)
#
# Run once per machine, or after apt upgrade / new WSL distro:
#   bash scripts/install_dependencies.sh
# ============================================================
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo ""
echo "========================================================"
echo "  Dependency install — apt + venv + ansible-galaxy"
echo "  Repo: $REPO_ROOT"
echo "========================================================"
echo ""

need_apt_update=false

echo "[apt] Checking ansible-playbook..."
if ! command -v ansible-playbook >/dev/null 2>&1; then
  echo "      Installing package: ansible"
  need_apt_update=true
else
  echo "      OK — $(ansible-playbook --version 2>/dev/null | head -1)"
fi

echo ""
echo "[apt] Checking python3 venv module..."
if ! python3 -c "import venv" 2>/dev/null; then
  echo "      Installing package: python3-venv"
  need_apt_update=true
else
  echo "      OK"
fi

if $need_apt_update; then
  sudo apt-get update -qq
  sudo apt-get install -y ansible python3-venv
fi

echo ""
echo "[bootstrap] AWS Python + collections (requirements.yml)..."
bash "$SCRIPT_DIR/bootstrap_aws.sh"

echo ""
echo "========================================================"
echo "  All dependencies installed."
echo "  Next: cp -n .env.example .env && nano .env"
echo "        bash scripts/check_setup.sh"
echo "========================================================"
echo ""
