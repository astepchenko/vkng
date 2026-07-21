#!/usr/bin/env bash
# Tears down everything bootstrap.sh created: Terraform-managed resources
# first, then the k3d cluster itself.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

CLUSTER_NAME="vkng"

log() { printf '\n==> %s\n' "$1"; }

log "Destroying Terraform-managed resources"
(cd "$REPO_ROOT/terraform" && terraform destroy)

log "Deleting k3d cluster '$CLUSTER_NAME'"
k3d cluster delete "$CLUSTER_NAME"

log "Done"
