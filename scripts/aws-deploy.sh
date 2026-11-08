#!/usr/bin/env bash
# Deploys the app to the K3s server created by terraform/aws.
# Run it from the machine that ran Terraform and Ansible. It renders the
# manifests locally and applies them over SSH, so port 6443 is not needed.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OVERLAY="$ROOT/k8s/overlays/aws"
SECRETS="$OVERLAY/secrets.env"
SSH_KEY="${SSH_KEY:-$HOME/.ssh/swiggy-aws}"
SERVER_IP="${SWIGGY_SERVER_IP:-$(terraform -chdir="$ROOT/terraform/aws" output -raw server_public_ip)}"

remote() { ssh -i "$SSH_KEY" -o BatchMode=yes "ec2-user@$SERVER_IP" "$@"; }

# Secrets are generated once and kept next to the overlay. The file is in
# .gitignore. Deleting it and redeploying would change the database password
# and lock the backend out of the existing database.
if [ ! -f "$SECRETS" ]; then
  umask 077
  {
    echo "DB_PASSWORD=$(openssl rand -hex 16)"
    echo "JWT_SECRET=$(openssl rand -hex 32)"
  } > "$SECRETS"
  echo "Generated $SECRETS"
fi

kubectl kustomize "$OVERLAY" | remote sudo k3s kubectl apply -f -

remote sudo k3s kubectl -n swiggy rollout status statefulset/postgres --timeout=300s
remote sudo k3s kubectl -n swiggy rollout status deployment/backend --timeout=300s
remote sudo k3s kubectl -n swiggy rollout status deployment/frontend --timeout=300s

remote sudo k3s kubectl -n swiggy get pods,ingress
echo "Website: http://$SERVER_IP"
