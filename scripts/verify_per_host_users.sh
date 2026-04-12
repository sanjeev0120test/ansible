#!/bin/bash
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=scripts/_env.sh
source "$SCRIPT_DIR/_env.sh"

_load_ansible_env "$REPO_ROOT"
_require_ec2_hosts || exit 1
PEM="$(_pem_for_ssh)" || exit 1

HOST_SPECS=(
  "$EC2_HOST_SERVER1:srv01ops"
  "$EC2_HOST_SERVER2:srv02ops"
  "$EC2_HOST_SERVER3:srv03ops"
  "$EC2_HOST_CLIENT:clientops"
)

echo "=== Verify per-host users ==="
for spec in "${HOST_SPECS[@]}"; do
  ip="${spec%%:*}"
  user="${spec##*:}"
  echo "--- $ip ($user) ---"
  ssh -i "$PEM" -o BatchMode=yes -o ConnectTimeout=20 -o StrictHostKeyChecking=accept-new \
    ec2-user@"$ip" bash -c "set -e; getent passwd $user; sudo test -f /home/$user/.ssh/authorized_keys; sudo head -1 /home/$user/.ssh/authorized_keys; id $user; echo OK"
done
echo "=== All verified ==="
