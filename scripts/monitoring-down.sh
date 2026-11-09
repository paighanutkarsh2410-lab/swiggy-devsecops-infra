#!/usr/bin/env bash
# Removes the monitoring stack from the kind cluster to free memory. The app
# keeps running; only its monitoring objects are switched off. The Grafana
# login in bootstrap/kind/grafana.env is kept for the next monitoring-up.sh.
#
# Usage: ./scripts/monitoring-down.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

kubectl config use-context kind-swiggy >/dev/null

# 1. Switch off the app's ServiceMonitor, alert rules and dashboard first, so
#    nothing in the swiggy namespace depends on the CRDs removed below.
revision="$(kubectl -n argocd get application swiggy -o jsonpath='{.spec.source.targetRevision}')"
"$ROOT/scripts/swiggy-app.sh" "$revision" false
echo "Waiting for Argo CD to remove the app's monitoring objects..."
for _ in $(seq 1 36); do
  if ! kubectl -n swiggy get servicemonitor backend >/dev/null 2>&1 \
     && ! kubectl -n swiggy get configmap swiggy-dashboard >/dev/null 2>&1; then
    break
  fi
  sleep 5
done

# 2. Delete the Application. Its finalizer makes Argo CD delete everything the
#    chart created before the Application itself goes away.
if kubectl -n argocd get application monitoring >/dev/null 2>&1; then
  kubectl -n argocd delete application monitoring --timeout=300s
fi

# 3. Objects the chart does not own: the CRDs if any are left, and the kubelet
#    Service the Prometheus Operator creates in kube-system.
kubectl get crd -o name | grep '\.monitoring\.coreos\.com$' | xargs -r kubectl delete --timeout=120s
kubectl -n kube-system delete service kps-kubelet --ignore-not-found

kubectl -n monitoring get pods 2>/dev/null || true
echo "Monitoring removed. Run ./scripts/monitoring-up.sh to install it again."
