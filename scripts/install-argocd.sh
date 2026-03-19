#!/usr/bin/env bash
# =============================================================================
# install-argocd.sh — Install ArgoCD and configure App of Apps
# =============================================================================
#
# This script:
#   1. Creates the argocd namespace
#   2. Installs ArgoCD via Helm with single-node-friendly settings
#   3. Waits for ArgoCD to be healthy
#   4. Retrieves and prints the initial admin password
#   5. Creates the root App of Apps application pointing at your GitHub repo
#   6. Prints access instructions
#
# Usage: bash install-argocd.sh <GITHUB_REPO_URL>
# Example: bash install-argocd.sh https://github.com/yourusername/homelab.git
#
# Prerequisites: bootstrap.sh must have been run first (K3s + Helm installed)
#
# =============================================================================

set -euo pipefail

# --- Color output helpers ---------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }

# =============================================================================
# ARGUMENT PARSING
# =============================================================================

GITHUB_REPO_URL="${1:-}"

if [[ -z "$GITHUB_REPO_URL" ]]; then
  error "Usage: $0 <GITHUB_REPO_URL>
Example: $0 https://github.com/yourusername/homelab.git

This URL is used to configure ArgoCD to watch your homelab repo.
ArgoCD will sync all manifests from the argocd/ directory in that repo."
fi

# Validate the URL looks reasonable
if [[ ! "$GITHUB_REPO_URL" =~ ^https?:// ]]; then
  error "GITHUB_REPO_URL should start with https://. Got: $GITHUB_REPO_URL"
fi

info "Will configure ArgoCD to track: $GITHUB_REPO_URL"

# =============================================================================
# PREREQUISITE CHECKS
# =============================================================================

if ! command -v kubectl &>/dev/null; then
  error "kubectl not found. Run bootstrap.sh first."
fi

if ! command -v helm &>/dev/null; then
  error "helm not found. Run bootstrap.sh first."
fi

if ! kubectl get node &>/dev/null; then
  error "Cannot connect to Kubernetes cluster. Is K3s running? Check: sudo systemctl status k3s"
fi

# Ensure kubeconfig is set
export KUBECONFIG="${KUBECONFIG:-$HOME/.kube/config}"

# =============================================================================
# STEP 1 — Create argocd namespace
# =============================================================================
# Namespaces are Kubernetes's way of isolating resources into logical groups.
# ArgoCD runs all its components in the "argocd" namespace.
#
# We use "kubectl apply" instead of "kubectl create" so this is idempotent —
# if the namespace already exists, it updates it rather than failing.

info "Creating argocd namespace..."
kubectl apply -f - <<EOF
apiVersion: v1
kind: Namespace
metadata:
  name: argocd
  labels:
    # This label is referenced in some ArgoCD RBAC configs
    kubernetes.io/metadata.name: argocd
EOF
success "argocd namespace ready"

# =============================================================================
# STEP 2 — Add ArgoCD Helm repository
# =============================================================================

info "Adding ArgoCD Helm repository..."
helm repo add argo https://argoproj.github.io/argo-helm 2>/dev/null || true
helm repo update argo
success "ArgoCD Helm repository ready"

# =============================================================================
# STEP 3 — Install ArgoCD via Helm
# =============================================================================
# We install ArgoCD using the values from system/argocd/values.yaml in this repo.
# Those values are tuned for a single-node homelab (reduced replicas, low resource requests).
#
# "helm upgrade --install" is idempotent:
#   - If ArgoCD is not installed: installs it
#   - If it IS installed: upgrades it with any new values
#   - This makes the script safe to run multiple times

ARGOCD_VALUES="$(dirname "$0")/../system/argocd/values.yaml"

if [[ ! -f "$ARGOCD_VALUES" ]]; then
  error "ArgoCD values file not found at $ARGOCD_VALUES. Make sure you're running from the repo root."
fi

info "Installing ArgoCD (this may take a few minutes)..."

helm upgrade --install argocd argo/argo-cd \
  --namespace argocd \
  --version 7.7.3 \
  --values "$ARGOCD_VALUES" \
  --wait \
  --timeout 10m

success "ArgoCD Helm release installed"

# =============================================================================
# STEP 4 — Wait for ArgoCD server to be ready
# =============================================================================
# Even after "helm --wait" completes, the ArgoCD server pod may still be
# initializing internally. We wait for the deployment to report all replicas ready.

info "Waiting for ArgoCD server deployment to be ready..."
kubectl rollout status deployment/argocd-server -n argocd --timeout=5m
success "ArgoCD server is ready"

# =============================================================================
# STEP 5 — Get the initial admin password
# =============================================================================
# ArgoCD generates a random initial admin password and stores it in a Kubernetes
# Secret called "argocd-initial-admin-secret". The password is base64-encoded.
#
# IMPORTANT: You should change this password after first login!

ARGOCD_PASSWORD=""
ATTEMPTS=0
MAX_ATTEMPTS=20

info "Retrieving ArgoCD initial admin password..."

while [[ -z "$ARGOCD_PASSWORD" && $ATTEMPTS -lt $MAX_ATTEMPTS ]]; do
  ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret \
    -o jsonpath="{.data.password}" 2>/dev/null | base64 -d 2>/dev/null || true)

  if [[ -z "$ARGOCD_PASSWORD" ]]; then
    ATTEMPTS=$((ATTEMPTS + 1))
    info "Password not available yet, waiting 5s... ($ATTEMPTS/$MAX_ATTEMPTS)"
    sleep 5
  fi
done

if [[ -z "$ARGOCD_PASSWORD" ]]; then
  warn "Could not retrieve initial admin password automatically."
  warn "Once ArgoCD is running, try: kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
else
  success "Retrieved ArgoCD admin password"
fi

# =============================================================================
# STEP 6 — Create the App of Apps root application
# =============================================================================
# The App of Apps pattern is a way to manage multiple ArgoCD Applications
# with a single parent Application. The root app watches the argocd/ directory
# in your repo and creates child Applications from the YAML files there.
#
# Benefits:
#   - Single source of truth: the repo controls what ArgoCD manages
#   - Self-healing: if someone manually changes a resource, ArgoCD reverts it
#   - Pruning: if you delete a manifest from the repo, ArgoCD deletes the resource
#
# We use "kubectl apply" so this is idempotent.

info "Creating ArgoCD App of Apps root application..."

kubectl apply -f - <<EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: homelab
  namespace: argocd
  # Finalizer ensures ArgoCD cleans up child apps when this app is deleted
  finalizers:
    - resources-finalizer.argocd.argoproj.io
  labels:
    app.kubernetes.io/name: homelab
    app.kubernetes.io/managed-by: argocd
spec:
  project: default

  source:
    repoURL: ${GITHUB_REPO_URL}
    targetRevision: HEAD
    # This directory contains Application manifests for all system and user apps
    path: argocd

  destination:
    # Deploy the child Application objects into the argocd namespace
    server: https://kubernetes.default.svc
    namespace: argocd

  syncPolicy:
    automated:
      # selfHeal: if someone manually changes something in the cluster,
      # ArgoCD will automatically revert it to match the repo state
      selfHeal: true
      # prune: if a manifest is removed from the repo, ArgoCD deletes the resource
      prune: true
    syncOptions:
      - CreateNamespace=true
EOF

success "App of Apps root application created"

# =============================================================================
# DONE — Print access instructions
# =============================================================================

# Get the VM's IP for access instructions
NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null || echo "YOUR_VM_IP")

echo ""
echo -e "${GREEN}=============================================${NC}"
echo -e "${GREEN} ArgoCD installation complete!               ${NC}"
echo -e "${GREEN}=============================================${NC}"
echo ""
echo -e "${BLUE}Access ArgoCD:${NC}"
echo ""
echo "  Option 1 (Port forward — works immediately):"
echo "    kubectl port-forward -n argocd svc/argocd-server 8080:80"
echo "    Then open: http://localhost:8080"
echo ""
echo "  Option 2 (Ingress — after ingress-nginx is deployed):"
echo "    Add to /etc/hosts: ${NODE_IP}  argocd.homelab.local"
echo "    Then open: http://argocd.homelab.local"
echo ""
echo -e "${BLUE}Credentials:${NC}"
echo "  Username: admin"
if [[ -n "$ARGOCD_PASSWORD" ]]; then
  echo "  Password: ${ARGOCD_PASSWORD}"
else
  echo "  Password: kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
fi
echo ""
echo -e "${YELLOW}IMPORTANT: Change the admin password after first login!${NC}"
echo "  ArgoCD UI → User Info → Update Password"
echo ""
echo -e "${BLUE}Watch ArgoCD sync your apps:${NC}"
echo "  kubectl get applications -n argocd -w"
echo ""
echo -e "${BLUE}ArgoCD is now tracking:${NC} ${GITHUB_REPO_URL}"
echo "  It will automatically deploy everything in the argocd/ directory."
echo "  System apps deploy first (sync wave -1), then user apps (wave 0)."
echo ""
echo "  Sit back and watch your homelab build itself! :)"
