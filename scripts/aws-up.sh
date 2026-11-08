#!/usr/bin/env bash
# Creates the AWS server, hardens it, installs K3s and deploys the app.
# Usage: ./scripts/aws-up.sh        (shows the plan and asks before creating)
#        ./scripts/aws-up.sh -y     (no question)
# Running it again on an existing server is safe: it only fixes drift.
set -euo pipefail
source "$(dirname "$0")/aws-common.sh"

need aws terraform ansible-playbook kubectl ssh ssh-keygen curl openssl
check_aws
write_tfvars

tf init -input=false >/dev/null
tf plan -input=false -out=up.tfplan
if [ "${1:-}" != "-y" ]; then
  read -r -p "Create or update these AWS resources? Type yes to continue: " answer
  if [ "$answer" != "yes" ]; then rm -f "$TF/up.tfplan"; echo "Cancelled."; exit 1; fi
fi
tf apply -input=false up.tfplan
rm -f "$TF/up.tfplan"

IP="$(tf output -raw server_public_ip)"
echo "Waiting for SSH on $IP ..."
for attempt in $(seq 1 40); do
  if ssh -i "$SSH_KEY" -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new \
      "ec2-user@$IP" true 2>/dev/null; then
    break
  fi
  if [ "$attempt" -eq 40 ]; then echo "The server did not accept SSH in time." >&2; exit 1; fi
  sleep 5
done

( cd "$ROOT/ansible" && SWIGGY_SERVER_IP="$IP" ansible-playbook playbooks/site.yml --private-key "$SSH_KEY" )
SWIGGY_SERVER_IP="$IP" SSH_KEY="$SSH_KEY" "$ROOT/scripts/aws-deploy.sh"

echo
echo "The app is live: http://$IP"
echo "It uses AWS credits while it runs. Stop it with: ./scripts/aws-down.sh"
