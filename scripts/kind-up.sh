#!/usr/bin/env bash
# Creates the local kind cluster (if needed), adds the namespace and secrets
# that never live in Git, installs Argo CD and lets it deploy the app from
# charts/swiggy.
#
# Usage: ./scripts/kind-up.sh [--monitoring] [git-revision]   (default: main)
#
# --monitoring also installs Prometheus, Alertmanager and Grafana (about
# 0.5 GB more memory). They can be added or removed later with
# scripts/monitoring-up.sh and scripts/monitoring-down.sh.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MONITORING=false
if [ "${1:-}" = "--monitoring" ]; then
  MONITORING=true
  shift
fi
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

if [ "$MONITORING" = true ]; then
  "$ROOT/scripts/monitoring-up.sh" "$REVISION"
fi

kubectl -n swiggy get pods -o wide
echo "Customer app:    http://localhost:8081"
echo "Partner console: http://localhost:8083"
echo "Argo CD UI:      kubectl -n argocd port-forward svc/argocd-server 8443:443, then https://localhost:8443"
if [ "$MONITORING" = false ]; then
  echo "Monitoring:      off; ./scripts/monitoring-up.sh installs Prometheus and Grafana"
fi
