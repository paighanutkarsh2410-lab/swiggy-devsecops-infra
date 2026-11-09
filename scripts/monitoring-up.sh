#!/usr/bin/env bash
# Installs the monitoring stack (Prometheus, Alertmanager, Grafana) on the kind
# cluster through Argo CD, then switches on the app's ServiceMonitor, alert
# rules and dashboard. It uses about 0.5 GB of memory, so it is off by default;
# scripts/monitoring-down.sh removes it again.
#
# Usage: ./scripts/monitoring-up.sh [git-revision]
#        (default: the revision the swiggy app already follows, else main)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REVISION="${1:-$(kubectl -n argocd get application swiggy -o jsonpath='{.spec.source.targetRevision}' 2>/dev/null || true)}"
REVISION="${REVISION:-main}"

kubectl config use-context kind-swiggy >/dev/null

# Grafana's admin login, generated once and kept outside Git (.gitignore).
GRAFANA="$ROOT/bootstrap/kind/grafana.env"
if [ ! -f "$GRAFANA" ]; then
  mkdir -p "$(dirname "$GRAFANA")"
  ( umask 077
    {
      echo "admin-user=admin"
      echo "admin-password=$(openssl rand -hex 16)"
    } > "$GRAFANA" )
  echo "Generated $GRAFANA"
fi
kubectl apply -f "$ROOT/bootstrap/monitoring-namespace.yaml" >/dev/null
kubectl -n monitoring create secret generic grafana-admin --from-env-file="$GRAFANA" \
  --dry-run=client -o yaml | kubectl apply -f - >/dev/null

kubectl apply -f "$ROOT/argocd/platform-project.yaml" >/dev/null
sed "s|targetRevision: main|targetRevision: $REVISION|" "$ROOT/argocd/monitoring.yaml" | kubectl apply -f -

# The app's ServiceMonitor and PrometheusRule need these CRDs to exist first.
# (`kubectl wait` fails instead of waiting while a new CRD has no status yet.)
echo "Waiting for the Prometheus Operator CRDs..."
established=""
for _ in $(seq 1 60); do
  established="$(kubectl get crd servicemonitors.monitoring.coreos.com prometheusrules.monitoring.coreos.com \
    -o jsonpath='{range .items[*]}{.status.conditions[?(@.type=="Established")].status} {end}' 2>/dev/null || true)"
  [ "$established" = "True True " ] && break
  sleep 5
done
if [ "$established" != "True True " ]; then
  echo "The Prometheus Operator CRDs were not created; check: kubectl -n argocd get application monitoring" >&2
  exit 1
fi

"$ROOT/scripts/swiggy-app.sh" "$REVISION" true

# Argo CD can report Healthy before the operator has created Prometheus and
# Alertmanager, so wait for the workloads themselves.
echo "Waiting for the monitoring stack to start (a few minutes on a fresh cluster)..."
for _ in $(seq 1 60); do
  kubectl -n monitoring get statefulset prometheus-kps-prometheus alertmanager-kps-alertmanager >/dev/null 2>&1 && break
  sleep 5
done
kubectl -n monitoring rollout status deployment/kps-grafana --timeout=600s
kubectl -n monitoring rollout status statefulset/prometheus-kps-prometheus --timeout=600s
kubectl -n monitoring rollout status statefulset/alertmanager-kps-alertmanager --timeout=300s
echo "Monitoring application: $(kubectl -n argocd get application monitoring \
  -o jsonpath='sync={.status.sync.status} health={.status.health.status}')"
kubectl -n monitoring get pods

echo "Grafana: kubectl -n monitoring port-forward svc/kps-grafana 3001:80, then http://localhost:3001"
echo "         (login in $GRAFANA)"
