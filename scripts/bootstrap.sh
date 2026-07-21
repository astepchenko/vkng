#!/usr/bin/env bash
# Automates README steps 1-3: cluster creation, image build/import, and
# terraform apply. Safe to re-run (cluster creation and image import are
# both idempotent).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

CLUSTER_NAME="vkng"
K3S_IMAGE="rancher/k3s:v1.35.5-k3s1"
BACKEND_IMAGE="vkng/backend:0.1.0"
FRONTEND_IMAGE="vkng/frontend:0.1.0"
ARGOCD_URL="http://argocd.localhost:8080"
FRONTEND_URL="http://vkng.localhost:8080"

log() { printf '\n==> %s\n' "$1"; }

log "Checking prerequisites"
missing=()
for tool in docker k3d kubectl helm terraform; do
  command -v "$tool" >/dev/null 2>&1 || missing+=("$tool")
done
if [ "$(uname)" = "Darwin" ] && ! command -v colima >/dev/null 2>&1; then
  missing+=("colima")
fi
if [ "${#missing[@]}" -gt 0 ]; then
  echo "Missing required tools: ${missing[*]}" >&2
  echo "See README.md 'Prerequisites' for install commands." >&2
  exit 1
fi

if [ "$(uname)" = "Darwin" ]; then
  log "Ensuring colima is running"
  colima status >/dev/null 2>&1 || colima start
  docker context use colima >/dev/null
else
  log "Checking Docker is reachable"
  if ! docker info >/dev/null 2>&1; then
    echo "Docker daemon not reachable. Start Docker and retry." >&2
    exit 1
  fi
fi

log "Ensuring k3d cluster '$CLUSTER_NAME' exists"
if k3d cluster list | tail -n +2 | awk '{print $1}' | grep -qx "$CLUSTER_NAME"; then
  echo "Cluster '$CLUSTER_NAME' already exists, skipping creation."
else
  k3d cluster create "$CLUSTER_NAME" \
    --servers 1 --agents 2 \
    --image "$K3S_IMAGE" \
    --port "8080:80@loadbalancer" \
    --port "8443:443@loadbalancer"
fi
kubectl config use-context "k3d-$CLUSTER_NAME" >/dev/null

log "Building application images"
docker build -t "$BACKEND_IMAGE" "$REPO_ROOT/applications/backend"
docker build -t "$FRONTEND_IMAGE" "$REPO_ROOT/applications/frontend"

log "Importing images into the cluster"
k3d image import "$BACKEND_IMAGE" "$FRONTEND_IMAGE" -c "$CLUSTER_NAME"

log "Deploying Argo CD and its Applications with Terraform"
(cd "$REPO_ROOT/terraform" && terraform init && terraform apply)

log "Waiting for Argo CD Applications to become Synced/Healthy (up to 5m)"
deadline=$((SECONDS + 300))
while [ "$SECONDS" -lt "$deadline" ]; do
  statuses=$(kubectl -n argocd get applications -o jsonpath='{range .items[*]}{.metadata.name}={.status.sync.status}/{.status.health.status} {end}' 2>/dev/null || true)
  echo "  $statuses"
  if [[ "$statuses" == *"applications=Synced/Healthy"* && "$statuses" == *"infrastructure=Synced/Healthy"* ]]; then
    break
  fi
  sleep 5
done

log "Done"
cat <<EOF
Argo CD UI: $ARGOCD_URL
  admin password: (cd "$REPO_ROOT/terraform" && terraform output -raw argocd_admin_password; echo)

Frontend:   $FRONTEND_URL

If *.localhost does not resolve on your system, fall back to kubectl
port-forward as described in README.md.
EOF
