#!/usr/bin/env bash
# Registers (or updates) the swiggy Argo CD Application on the kind cluster.
#
# Usage: ./scripts/swiggy-app.sh <git-revision> <true|false>
#
# The second argument switches the app's monitoring objects (ServiceMonitor,
# alert rules, Grafana dashboard) on or off. They need the monitoring stack's
# CRDs, so they are only on while the stack is installed; see
# scripts/monitoring-up.sh and scripts/monitoring-down.sh.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REVISION="${1:?git revision required}"
MONITORING="${2:?true or false required}"

case "$MONITORING" in
  true|false) ;;
  *) echo "Second argument must be true or false" >&2; exit 1 ;;
esac

kubectl apply -f "$ROOT/argocd/project.yaml" >/dev/null
kubectl patch --local -f "$ROOT/argocd/swiggy-kind.yaml" --type merge -o yaml -p "{
  \"spec\": {\"source\": {
    \"targetRevision\": \"$REVISION\",
    \"helm\": {\"parameters\": [{\"name\": \"monitoring.enabled\", \"value\": \"$MONITORING\"}]}
  }}
}" | kubectl apply -f -
