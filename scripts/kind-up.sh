#!/usr/bin/env bash
# Creates the local kind cluster (if needed), adds the namespace and secrets
# that never live in Git, installs Argo CD and lets it deploy the app from
# charts/swiggy.
#
# Usage: ./scripts/kind-up.sh [git-revision]   (default: main)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REVISION="${1:-main}"
SECRETS="$ROOT/bootstrap/kind/secrets.env"

if ! kind get clusters | grep -qx swiggy; then
  kind create cluster --config "$ROOT/kind/cluster.yaml" --wait 120s
fi

kubectl config use-context kind-swiggy >/dev/null

# 1. Namespace and secrets. Generated once and kept outside Git (.gitignore).
if [ ! -f "$SECRETS" ]; then
  mkdir -p "$(dirname "$SECRETS")"
  ( umask 077
    {
      echo "DB_PASSWORD=$(openssl rand -hex 16)"
      echo "JWT_SECRET=$(openssl rand -hex 32)"
    } > "$SECRETS" )
  echo "Generated $SECRETS"
fi

kubectl apply -f "$ROOT/bootstrap/namespace.yaml"
kubectl -n swiggy create secret generic swiggy-secrets --from-env-file="$SECRETS" \
  --dry-run=client -o yaml | kubectl apply -f -

# Grafana's admin login for the monitoring stack, also kept outside Git.
GRAFANA="$ROOT/bootstrap/kind/grafana.env"
if [ ! -f "$GRAFANA" ]; then
  ( umask 077
    {
      echo "admin-user=admin"
      echo "admin-password=$(openssl rand -hex 16)"
    } > "$GRAFANA" )
  echo "Generated $GRAFANA"
fi
kubectl apply -f "$ROOT/bootstrap/monitoring-namespace.yaml"
kubectl -n monitoring create secret generic grafana-admin --from-env-file="$GRAFANA" \
  --dry-run=client -o yaml | kubectl apply -f -

# 2. Argo CD, which then deploys and keeps syncing the app.
"$ROOT/scripts/argocd-up.sh" "$REVISION"

echo "Waiting for Argo CD to sync and the app to become healthy..."
for _ in $(seq 1 60); do
  sync="$(kubectl -n argocd get application swiggy -o jsonpath='{.status.sync.status}' 2>/dev/null || true)"
  health="$(kubectl -n argocd get application swiggy -o jsonpath='{.status.health.status}' 2>/dev/null || true)"
  [ "$sync" = "Synced" ] && [ "$health" = "Healthy" ] && break
  sleep 5
done
echo "Argo CD application: sync=$sync health=$health"

kubectl -n swiggy rollout status statefulset/postgres --timeout=180s
for deployment in backend frontend partner; do
  kubectl -n swiggy rollout status "deployment/$deployment" --timeout=180s
done

kubectl -n swiggy get pods -o wide
echo "Customer app:    http://localhost:8081"
echo "Partner console: http://localhost:8083"
echo "Argo CD UI:      kubectl -n argocd port-forward svc/argocd-server 8443:443, then https://localhost:8443"
echo "Grafana:         kubectl -n monitoring port-forward svc/kps-grafana 3001:80, then http://localhost:3001"
echo "                 (login in $GRAFANA; the stack may need a few more minutes to start)"
