#!/bin/bash
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=scripts/_env.sh
source "$SCRIPT_DIR/_env.sh"

_load_ansible_env "$REPO_ROOT"
_require_ec2_hosts || exit 1
PEM="$(_pem_for_ssh)" || exit 1

PUBKEY_FILE="${REPO_ROOT}/.keys/appoperator_ed25519.pub"
if [ ! -f "$PUBKEY_FILE" ]; then
  echo "ERROR: Missing $PUBKEY_FILE"
  exit 1
fi

PUB=$(tr -d '\r\n' < "$PUBKEY_FILE")
B64=$(printf '%s' "$PUB" | base64 -w0 2>/dev/null || printf '%s' "$PUB" | base64)

IPS=("$EC2_HOST_SERVER1" "$EC2_HOST_SERVER2" "$EC2_HOST_SERVER3" "$EC2_HOST_CLIENT")

echo "=== Ensure appoperator (${#IPS[@]} hosts), pubkey: $PUBKEY_FILE ==="

run_remote() {
  local ip="$1"
  ssh -i "$PEM" -o BatchMode=yes -o ConnectTimeout=25 -o StrictHostKeyChecking=accept-new \
    ec2-user@"$ip" bash -s "$B64" <<'REMOTE'
set -e
B64="$1"
PUB=$(printf '%s' "$B64" | base64 -d)
if getent passwd appoperator >/dev/null; then
  echo "(user already existed; refreshing keys/sudo)"
else
  sudo useradd -m -s /bin/bash appoperator
  echo "(created appoperator)"
fi
sudo usermod -aG wheel appoperator
sudo mkdir -p /home/appoperator/.ssh
printf '%s\n' "$PUB" | sudo tee /home/appoperator/.ssh/authorized_keys >/dev/null
sudo chmod 700 /home/appoperator/.ssh
sudo chmod 600 /home/appoperator/.ssh/authorized_keys
sudo chown -R appoperator:appoperator /home/appoperator/.ssh
printf '%s\n' 'appoperator ALL=(ALL) NOPASSWD:ALL' | sudo tee /etc/sudoers.d/90-ansible-appoperator >/dev/null
sudo chmod 440 /etc/sudoers.d/90-ansible-appoperator
sudo visudo -cf /etc/sudoers.d/90-ansible-appoperator
getent passwd appoperator
REMOTE
}

for ip in "${IPS[@]}"; do
  echo "--- $ip ---"
  run_remote "$ip"
  echo "OK $ip"
done

echo "=== All hosts have appoperator ==="
