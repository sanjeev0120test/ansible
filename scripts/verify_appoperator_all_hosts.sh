#!/bin/bash
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=scripts/_env.sh
source "$SCRIPT_DIR/_env.sh"

_load_ansible_env "$REPO_ROOT"
_require_ec2_hosts || exit 1
PEM="$(_pem_for_ssh)" || exit 1

IPS=("$EC2_HOST_SERVER1" "$EC2_HOST_SERVER2" "$EC2_HOST_SERVER3" "$EC2_HOST_CLIENT")

echo "############################################"
echo "# Verification — $(date -u +%Y-%m-%dT%H:%M:%SZ) UTC"
echo "############################################"

for ip in "${IPS[@]}"; do
  echo ""
  echo "══════════════════════════════════════════"
  echo " HOST: $ip"
  echo "══════════════════════════════════════════"
  ssh -i "$PEM" -o BatchMode=yes -o ConnectTimeout=20 -o StrictHostKeyChecking=accept-new \
    ec2-user@"$ip" bash <<'REMOTE'
set -e
echo "---- Human accounts (UID>=1000) ----"
awk -F: '$3>=1000 {print $1 " (uid="$3", home="$6")"}' /etc/passwd | sort
echo "---- appoperator passwd entry ----"
getent passwd appoperator
echo "---- /home/appoperator ----"
sudo ls -la /home/appoperator
echo "---- /home/appoperator/.ssh ----"
sudo ls -la /home/appoperator/.ssh
echo "---- authorized_keys (line 1) ----"
sudo head -1 /home/appoperator/.ssh/authorized_keys
echo "---- /etc/sudoers.d/90-ansible-appoperator ----"
sudo cat /etc/sudoers.d/90-ansible-appoperator
sudo visudo -cf /etc/sudoers.d/90-ansible-appoperator
echo "---- id appoperator ----"
id appoperator
echo "AUDIT_OK"
REMOTE
done

echo ""
echo "############################################"
echo "# RESULT: all ${#IPS[@]} hosts audited successfully"
echo "############################################"
