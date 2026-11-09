#!/usr/bin/env bash
# Installs Argo CD into the current cluster and points it at this repository.
# After this, Argo CD deploys the app from Git: a change merged to main is
# applied automatically, and manual changes in the cluster are reverted.
#
# The monitoring stack is not installed here; see scripts/monitoring-up.sh.
#
# Usage: ./scripts/argocd-up.sh [git-revision]   (default: main)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REVISION="${1:-main}"

# Argo CD v3.5.7, pinned to the commit of its signed release tag, and checked
# against the manifest's SHA-256 before anything is applied.
ARGOCD_VERSION="v3.5.7"
ARGOCD_COMMIT="6d732962f61a99c2a0f221fd26b9aac7c83bcf18"
ARGOCD_SHA256="09bfbb9041b4a8503c6e4fa22cf41c403fa62be17526de353648a4551f5beb77"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

curl -fsSL -o "$WORK/install.yaml" \
  "https://raw.githubusercontent.com/argoproj/argo-cd/$ARGOCD_COMMIT/manifests/install.yaml"
echo "$ARGOCD_SHA256  $WORK/install.yaml" | sha256sum --check --quiet
echo "Argo CD $ARGOCD_VERSION manifest verified"

# bootstrap/argocd/kustomization.yaml trims the install for a small VM.
cp "$ROOT/bootstrap/argocd/kustomization.yaml" "$WORK/"

kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f - >/dev/null
# Server-side apply, because some Argo CD CRDs are too large for the
# last-applied annotation that client-side apply writes.
kubectl kustomize "$WORK" | kubectl apply --server-side --force-conflicts -f - >/dev/null

# Clusters set up before the trimmed install still run these; apply does not
# remove objects, so delete them explicitly.
kubectl -n argocd delete deployment --ignore-not-found \
  argocd-dex-server argocd-notifications-controller argocd-applicationset-controller

for deployment in argocd-server argocd-repo-server argocd-redis; do
  kubectl -n argocd rollout status "deployment/$deployment" --timeout=300s
done
kubectl -n argocd rollout status statefulset/argocd-application-controller --timeout=300s

# Keep the app's monitoring objects on if the monitoring stack is installed.
monitoring=false
if kubectl -n argocd get application monitoring >/dev/null 2>&1; then
  monitoring=true
fi
"$ROOT/scripts/swiggy-app.sh" "$REVISION" "$monitoring"

echo "Argo CD is following $REVISION of this repository for the app (monitoring: $monitoring)."
