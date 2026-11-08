#!/usr/bin/env bash
# Destroys everything aws-up.sh created and checks that nothing is left.
# Usage: ./scripts/aws-down.sh      (shows what will be destroyed and asks)
#        ./scripts/aws-down.sh -y   (no question)
set -euo pipefail
source "$(dirname "$0")/aws-common.sh"

need aws terraform ssh-keygen curl
check_aws
tf init -input=false >/dev/null

if [ -z "$(tf state list 2>/dev/null)" ]; then
  echo "Terraform has nothing to destroy."
else
  [ -f "$TF/terraform.tfvars" ] || write_tfvars
  IP="$(tf output -raw server_public_ip 2>/dev/null || true)"
  if [ "${1:-}" = "-y" ]; then
    tf destroy -input=false -auto-approve
  else
    tf destroy -input=false
  fi
  # The next server may get this address with a different host key.
  [ -n "$IP" ] && ssh-keygen -R "$IP" >/dev/null 2>&1 || true
fi

# The database went with the server, so its secrets are no longer needed.
rm -f "$ROOT/k8s/overlays/aws/secrets.env"

remaining="$(leftovers)"
if [ -n "$remaining" ]; then
  echo "These project resources still exist in AWS:" >&2
  echo "$remaining" >&2
  exit 1
fi
echo "Nothing from this project is left running in AWS."
