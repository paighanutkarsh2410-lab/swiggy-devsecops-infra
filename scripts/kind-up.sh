#!/usr/bin/env bash
# Creates the local kind cluster (if needed) and deploys the app into it.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OVERLAY="$ROOT/k8s/overlays/kind"
SECRETS="$OVERLAY/secrets.env"

if ! kind get clusters | grep -qx swiggy; then
  kind create cluster --config "$ROOT/kind/cluster.yaml" --wait 120s
fi

kubectl config use-context kind-swiggy >/dev/null

if [ ! -f "$SECRETS" ]; then
  umask 077
  {
    echo "DB_PASSWORD=$(openssl rand -hex 16)"
    echo "JWT_SECRET=$(openssl rand -hex 32)"
  } > "$SECRETS"
  echo "Generated $SECRETS"
fi

kubectl apply -k "$OVERLAY"

kubectl -n swiggy rollout status statefulset/postgres --timeout=180s
kubectl -n swiggy rollout status deployment/backend --timeout=180s
kubectl -n swiggy rollout status deployment/frontend --timeout=180s

kubectl -n swiggy get pods -o wide
echo "Website: http://localhost:8081"
