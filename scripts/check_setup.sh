#!/usr/bin/env bash
# ============================================================
# Pre-flight checker — run this FIRST before any Ansible work.
# Checks every dependency and prints [PASS] / [WARN] / [FAIL].
# ============================================================
set +e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/_env.sh"
_load_ansible_env "$REPO_ROOT"

PASS=0; WARN=0; FAIL=0

ok()   { printf "  [PASS] %s\n" "$*"; PASS=$((PASS+1)); }
warn() { printf "  [WARN] %s\n" "$*"; WARN=$((WARN+1)); }
fail() { printf "  [FAIL] %s\n" "$*"; FAIL=$((FAIL+1)); }

echo "========================================================"
echo "  Ansible Repo Pre-flight Check"
echo "  Repo : $REPO_ROOT"
echo "  Date : $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
echo "========================================================"
echo ""

# ── 1. Linux / WSL ────────────────────────────────────────────────────────────
echo "[1] Environment"
if [ "$(uname -s)" = "Linux" ]; then
  ok "Running on Linux/WSL"
else
  fail "Not Linux — open a WSL terminal in Cursor"
fi

# ── 2. Ansible ────────────────────────────────────────────────────────────────
echo ""
echo "[2] Ansible"
if command -v ansible-playbook >/dev/null 2>&1; then
  ANSIBLE_VER=$(ansible --version 2>/dev/null | head -1)
  ok "ansible-playbook: $ANSIBLE_VER"
else
  fail "ansible-playbook not found  →  bash scripts/install_dependencies.sh"
fi

# ── 3. .env file ──────────────────────────────────────────────────────────────
echo ""
echo "[3] .env configuration"
if [ -f "$REPO_ROOT/.env" ]; then
  ok ".env file exists"
else
  fail ".env missing  →  cp .env.example .env && nano .env"
fi

# Determine expected host count from .env
_ec2_count="${EC2_INSTANCE_COUNT:-2}"
case "$_ec2_count" in
  1) _needed_hosts=(EC2_HOST_SERVER1) ;;
  2) _needed_hosts=(EC2_HOST_SERVER1 EC2_HOST_SERVER2) ;;
  3) _needed_hosts=(EC2_HOST_SERVER1 EC2_HOST_SERVER2 EC2_HOST_SERVER3) ;;
  *) _needed_hosts=(EC2_HOST_SERVER1 EC2_HOST_SERVER2 EC2_HOST_SERVER3 EC2_HOST_CLIENT) ;;
esac

_ec2_hosts_all_set=true
_ec2_hosts_all_empty=true
for v in "${_needed_hosts[@]}"; do
  val="${!v:-}"
  if [ -n "$val" ]; then
    _ec2_hosts_all_empty=false
  else
    _ec2_hosts_all_set=false
  fi
done
if $_ec2_hosts_all_set; then
  for v in "${_needed_hosts[@]}"; do
    ok "$v = ${!v}"
  done
elif $_ec2_hosts_all_empty; then
  warn "EC2_HOST_* empty — expected before first provision (EC2_INSTANCE_COUNT=$_ec2_count); run: bash scripts/run_ec2_provision.sh"
else
  fail "EC2_HOST_* partially set (EC2_INSTANCE_COUNT=$_ec2_count) — set all ${#_needed_hosts[@]} IPs or clear them all, then re-run provision"
fi

# ── 4. SSH private key ────────────────────────────────────────────────────────
echo ""
echo "[4] SSH key"
PEM=""
if [ -n "${EC2_SSH_PRIVATE_KEY:-}" ] && [ -f "${EC2_SSH_PRIVATE_KEY}" ]; then
  PEM="${EC2_SSH_PRIVATE_KEY}"
elif [ -f "${HOME}/.ssh/ec2-keypair.pem" ]; then
  PEM="${HOME}/.ssh/ec2-keypair.pem"
fi

if [ -n "$PEM" ]; then
  PERM=$(stat -c %a "$PEM" 2>/dev/null || echo "unknown")
  if [ "$PERM" = "600" ]; then
    ok "SSH key: $PEM (600) — for SSH playbooks only; not needed for run_ec2_*.sh"
  else
    warn "SSH key $PEM has perms $PERM (should be 600)  →  chmod 600 \"$PEM\""
  fi
else
  fail "SSH key not found  →  copy your EC2 .pem to ~/.ssh/ec2-keypair.pem and chmod 600 (skip only if you never run SSH playbooks)"
fi

# ── 5. Managed-user public key ────────────────────────────────────────────────
echo ""
echo "[5] Managed-user public key"
if [ -f "$REPO_ROOT/.keys/appoperator_ed25519.pub" ]; then
  ok ".keys/appoperator_ed25519.pub exists"
else
  warn ".keys/appoperator_ed25519.pub missing"
  warn "  Generate:  ssh-keygen -t ed25519 -f .keys/appoperator_ed25519 -N '' -C ansible-managed"
fi

# ── 6. Collections ────────────────────────────────────────────────────────────
echo ""
echo "[6] Ansible collections"
COLL_LIST=$(ANSIBLE_CONFIG="$REPO_ROOT/ansible.cfg" ansible-galaxy collection list 2>/dev/null)

echo "$COLL_LIST" | grep -q "ansible\.posix" \
  && ok "ansible.posix installed" \
  || fail "ansible.posix missing  →  bash scripts/install_dependencies.sh"

echo "$COLL_LIST" | grep -q "community\.general" \
  && ok "community.general installed" \
  || fail "community.general missing  →  bash scripts/install_dependencies.sh"

echo "$COLL_LIST" | grep -q "amazon\.aws" \
  && ok "amazon.aws installed (EC2 ops ready)" \
  || warn "amazon.aws not installed  →  bash scripts/install_dependencies.sh (EC2 playbooks)"

# ── 7. Python boto3 ───────────────────────────────────────────────────────────
echo ""
echo "[7] Python boto3 (for EC2 playbooks)"
AWS_PY="$(_local_aws_python "$REPO_ROOT")"
if "$AWS_PY" -c "import boto3" 2>/dev/null; then
  BOTO3_VER=$("$AWS_PY" -c "import boto3; print(boto3.__version__)" 2>/dev/null)
  if [ -x "$REPO_ROOT/.venv/bin/python" ] && [ "$AWS_PY" = "$REPO_ROOT/.venv/bin/python" ]; then
    ok "boto3 $BOTO3_VER (repo .venv)"
  else
    ok "boto3 $BOTO3_VER (system python)"
  fi
else
  warn "boto3 not available for EC2 modules  →  bash scripts/install_dependencies.sh"
fi

# ── 8. AWS credentials ────────────────────────────────────────────────────────
echo ""
echo "[8] AWS credentials (for EC2 playbooks)"
if [ -n "${AWS_ACCESS_KEY_ID:-}" ] && [ -n "${AWS_SECRET_ACCESS_KEY:-}" ]; then
  ok "AWS_ACCESS_KEY_ID + AWS_SECRET_ACCESS_KEY set in .env"
elif "$AWS_PY" -c "import boto3; boto3.client('sts').get_caller_identity()" 2>/dev/null; then
  ok "AWS credentials available via boto3 default chain (CLI/role)"
else
  warn "AWS credentials not configured  →  add AWS_ACCESS_KEY_ID + AWS_SECRET_ACCESS_KEY to .env"
  warn "  OR run:  $REPO_ROOT/.venv/bin/aws configure"
fi

# ── 8b. EC2 provisioning (.env) ─────────────────────────────────────────────
echo ""
echo "[8b] EC2 provisioning (bash scripts/run_ec2_provision.sh)"
if [ -n "${EC2_KEY_PAIR_NAME:-}" ]; then
  ok "EC2_KEY_PAIR_NAME set (matches EC2 → Key Pairs in console)"
else
  warn "EC2_KEY_PAIR_NAME empty  →  set to the key's NAME in EC2 → Key Pairs (not the .pem file path)"
fi

# ── 8c. EC2 IAM (must allow at least ec2:DescribeInstances) ──────────────────
echo ""
echo "[8c] EC2 IAM permissions (ec2:DescribeInstances)"
if ! "$AWS_PY" -c "import boto3; boto3.client('sts').get_caller_identity()" 2>/dev/null; then
  warn "Skip EC2 IAM check — no working AWS credentials yet"
elif [ -z "${AWS_DEFAULT_REGION:-}" ]; then
  warn "Skip EC2 IAM check — set AWS_DEFAULT_REGION in .env"
else
  _ec2_check_py="${TMPDIR:-/tmp}/_ansible_check_ec2.py"
  cat > "$_ec2_check_py" <<'PYEOF'
import os, sys
import boto3
from botocore.exceptions import ClientError, BotoCoreError

region = os.environ.get("AWS_DEFAULT_REGION", "").strip()
k = os.environ.get("AWS_ACCESS_KEY_ID", "").strip().strip("'\"")
s = os.environ.get("AWS_SECRET_ACCESS_KEY", "").strip().strip("'\"")
kw = {"region_name": region}
if k and s:
    kw["aws_access_key_id"] = k
    kw["aws_secret_access_key"] = s
try:
    boto3.client("ec2", **kw).describe_instances(MaxResults=5)
except ClientError as e:
    code = e.response.get("Error", {}).get("Code", "")
    if code in ("UnauthorizedOperation", "AccessDenied"):
        sys.exit(3)
    print(f"ClientError: {e}", file=sys.stderr)
    sys.exit(2)
except (BotoCoreError, Exception) as e:
    print(f"Exception: {e}", file=sys.stderr)
    sys.exit(2)
sys.exit(0)
PYEOF
  ec2_rc=0
  ec2_err=$("$AWS_PY" "$_ec2_check_py" 2>&1) || ec2_rc=$?
  rm -f "$_ec2_check_py"
  case "$ec2_rc" in
    0) ok "ec2:DescribeInstances allowed (IAM OK for EC2 API playbooks)" ;;
    3) fail "IAM denies EC2 API — attach $REPO_ROOT/iam/ec2-ansible-lab-policy.json (or AmazonEC2FullAccess). See README." ;;
    *) warn "EC2 DescribeInstances check failed (ec2_rc=$ec2_rc). Detail: ${ec2_err:-unknown}" ;;
  esac
fi

# ── 9. Generated inventory ────────────────────────────────────────────────────
echo ""
echo "[9] Generated inventory"
if [ -f "$REPO_ROOT/inventory/hosts.autogen.yml" ]; then
  ok "inventory/hosts.autogen.yml exists"
else
  warn "Inventory not yet generated  →  bash scripts/render_inventory_from_env.sh"
fi

# ── 10. Reports directory ─────────────────────────────────────────────────────
echo ""
echo "[10] Reports directory"
mkdir -p "$REPO_ROOT/reports" 2>/dev/null && ok "reports/ ready ($REPO_ROOT/reports/)"

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "========================================================"
printf "  PASS: %-3d  WARN: %-3d  FAIL: %d\n" "$PASS" "$WARN" "$FAIL"
echo "========================================================"
echo ""

if [ "$FAIL" -gt 0 ]; then
  echo "  ACTION REQUIRED: fix FAIL items before running playbooks."
  echo ""
  exit 1
elif [ "$WARN" -gt 0 ]; then
  echo "  Core SSH setup OK."
  echo "  WARN items are optional — needed only for EC2 provisioning playbooks."
  echo "  SSH playbooks (run_site.sh, run_audit.sh, etc.) will work now."
  echo ""
  exit 0
else
  echo "  All checks passed. Full stack ready including EC2 ops."
  echo ""
  exit 0
fi
