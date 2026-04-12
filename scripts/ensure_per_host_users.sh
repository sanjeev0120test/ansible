#!/bin/bash
# One distinct Linux account per EC2 instance (same SSH public key on all).
# Requires .env with EC2_HOST_* (see .env.example).
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=scripts/_env.sh
source "$SCRIPT_DIR/_env.sh"

_load_ansible_env "$REPO_ROOT"
_require_ec2_hosts || exit 1
PEM="$(_pem_for_ssh)" || exit 1

PUBKEY_FILE="${REPO_ROOT}/.keys/appoperator_ed25519.pub"
HOST_SPECS=(
  "$EC2_HOST_SERVER1:srv01ops"
  "$EC2_HOST_SERVER2:srv02ops"
  "$EC2_HOST_SERVER3:srv03ops"
  "$EC2_HOST_CLIENT:clientops"
)

chmod 600 "$PEM" 2>/dev/null || true

if [ ! -f "$PUBKEY_FILE" ]; then
  echo "ERROR: Missing $PUBKEY_FILE"
  exit 1
fi

PUB=$(tr -d '\r\n' < "$PUBKEY_FILE")
B64=$(printf '%s' "$PUB" | base64 -w0 2>/dev/null || printf '%s' "$PUB" | base64)

echo "=== Per-host users (${#HOST_SPECS[@]} hosts), pubkey: $PUBKEY_FILE ==="

run_remote() {
  local ip="$1"
  local target_user="$2"
  ssh -i "$PEM" -o BatchMode=yes -o ConnectTimeout=25 -o StrictHostKeyChecking=accept-new \
    ec2-user@"$ip" bash -s "$B64" "$target_user" <<'REMOTE'
set -e
B64="$1"
TARGET_USER="$2"
PUB=$(printf '%s' "$B64" | base64 -d)
if [[ ! "$TARGET_USER" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]; then
  echo "Invalid username: $TARGET_USER"
  exit 1
fi
if getent passwd "$TARGET_USER" >/dev/null; then
  echo "(user $TARGET_USER exists; refreshing keys/sudo)"
else
  sudo useradd -m -s /bin/bash "$TARGET_USER"
  echo "(created $TARGET_USER)"
fi
sudo usermod -aG wheel "$TARGET_USER"
sudo mkdir -p "/home/$TARGET_USER/.ssh"
printf '%s\n' "$PUB" | sudo tee "/home/$TARGET_USER/.ssh/authorized_keys" >/dev/null
sudo chmod 700 "/home/$TARGET_USER/.ssh"
sudo chmod 600 "/home/$TARGET_USER/.ssh/authorized_keys"
sudo chown -R "$TARGET_USER:$TARGET_USER" "/home/$TARGET_USER/.ssh"
SUDO_F="/etc/sudoers.d/90-ansible-${TARGET_USER}"
printf '%s\n' "${TARGET_USER} ALL=(ALL) NOPASSWD:ALL" | sudo tee "$SUDO_F" >/dev/null
sudo chmod 440 "$SUDO_F"
sudo visudo -cf "$SUDO_F"
getent passwd "$TARGET_USER"
REMOTE
}

for spec in "${HOST_SPECS[@]}"; do
  ip="${spec%%:*}"
  user="${spec##*:}"
  echo "--- $ip -> $user ---"
  run_remote "$ip" "$user"
  echo "OK $ip ($user)"
done

echo "=== Per-host users ensured ==="
