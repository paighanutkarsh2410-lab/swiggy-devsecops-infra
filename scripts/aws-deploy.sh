#!/usr/bin/env bash
# Deploys the app to the K3s server created by terraform/aws.
# Run it from the machine that ran Terraform and Ansible. It renders the Helm
# chart locally and applies it over SSH, so port 6443 is not needed.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CHART="$ROOT/charts/swiggy"
SECRETS="$ROOT/bootstrap/aws/secrets.env"
SSH_KEY="${SSH_KEY:-$HOME/.ssh/swiggy-aws}"
SERVER_IP="${SWIGGY_SERVER_IP:-$(terraform -chdir="$ROOT/terraform/aws" output -raw server_public_ip)}"

remote() { ssh -i "$SSH_KEY" -o BatchMode=yes "ec2-user@$SERVER_IP" "$@"; }

# Secrets are generated once and kept outside Git (.gitignore). Deleting the
# file and redeploying would change the database password and lock the
# backend out of the existing database. aws-down.sh removes it with the server.
if [ ! -f "$SECRETS" ]; then
  mkdir -p "$(dirname "$SECRETS")"
  ( umask 077
    {
      echo "DB_PASSWORD=$(openssl rand -hex 16)"
      echo "JWT_SECRET=$(openssl rand -hex 32)"
    } > "$SECRETS" )
  echo "Generated $SECRETS"
fi

# 1. Namespace and Secret, which are not part of the chart.
remote sudo k3s kubectl apply -f - < "$ROOT/bootstrap/namespace.yaml"
kubectl create secret generic swiggy-secrets -n swiggy --from-env-file="$SECRETS" \
  --dry-run=client -o yaml | remote sudo k3s kubectl apply -f -

# 2. The app. Host names come from the server IP, for example
#    partner.13-55-152-184.sslip.io.
IP_DASHED="${SERVER_IP//./-}"
PARTNER_HOST="partner.$IP_DASHED.sslip.io"

helm template swiggy "$CHART" --namespace swiggy \
  -f "$CHART/values-aws.yaml" \
  --set "ingress.partnerHost=$PARTNER_HOST" \
  | remote sudo k3s kubectl apply -n swiggy -f -

remote sudo k3s kubectl -n swiggy rollout status statefulset/postgres --timeout=300s
for deployment in backend frontend partner; do
  remote sudo k3s kubectl -n swiggy rollout status "deployment/$deployment" --timeout=300s
done

remote sudo k3s kubectl -n swiggy get pods,ingress
echo "Customer app:    http://$SERVER_IP  (or http://$IP_DASHED.sslip.io)"
echo "Partner console: http://$PARTNER_HOST"
