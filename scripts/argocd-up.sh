#!/usr/bin/env bash
# Installs Argo CD into the current cluster and points it at this repository.
# After this, Argo CD deploys the app from Git: a change merged to main is
# applied automatically, and manual changes in the cluster are reverted.
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

kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f - >/dev/null
# Server-side apply, because some Argo CD CRDs are too large for the
# last-applied annotation that client-side apply writes.
kubectl apply -n argocd --server-side --force-conflicts -f "$WORK/install.yaml" >/dev/null

for deployment in argocd-server argocd-repo-server argocd-redis; do
  kubectl -n argocd rollout status "deployment/$deployment" --timeout=300s
done
kubectl -n argocd rollout status statefulset/argocd-application-controller --timeout=300s

# The project limits what this app may deploy; the Application tells Argo CD
# where the chart is and which revision to follow.
kubectl apply -f "$ROOT/argocd/project.yaml"
sed "s|targetRevision: main|targetRevision: $REVISION|" "$ROOT/argocd/swiggy-kind.yaml" | kubectl apply -f -

echo "Argo CD is following $REVISION of charts/swiggy."
