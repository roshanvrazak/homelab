#!/usr/bin/env bash
# =============================================================================
# bootstrap.sh — Homelab K3s Bootstrap Script
# =============================================================================
#
# This script sets up a fresh Ubuntu 24.04 VM for running K3s (Kubernetes).
# It is designed to be:
#   - IDEMPOTENT: safe to run multiple times without side effects
#   - EDUCATIONAL: comments explain what each step does and WHY
#   - FAIL-FAST: exits immediately if any command fails (set -e)
#
# Usage: bash bootstrap.sh
# Run as a regular user with sudo privileges (not as root).
#
# =============================================================================

# Exit immediately if any command returns a non-zero exit code.
# This prevents the script from silently continuing after an error.
set -e

# Treat unset variables as errors — catches typos in variable names.
set -u

# If a pipeline fails, the exit code is that of the last failed command.
set -o pipefail

# --- Color output helpers ---------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }

# --- Sanity checks -----------------------------------------------------------

# Make sure we're NOT running as root.
# K3s should be installed by a regular user with sudo — running as root
# can cause kubeconfig ownership issues and is generally bad practice.
if [[ $EUID -eq 0 ]]; then
  error "Do not run this script as root. Run as a regular user with sudo access."
fi

# Check that sudo is available.
if ! command -v sudo &>/dev/null; then
  error "sudo is not installed. Please install it and add your user to the sudo group."
fi

# Check internet connectivity — we need to download packages.
if ! curl -s --max-time 5 https://get.k3s.io > /dev/null; then
  error "No internet access. Check your network connection before running this script."
fi

info "Starting homelab bootstrap on $(hostname) ($(uname -m))"
info "Ubuntu version: $(lsb_release -ds 2>/dev/null || echo 'unknown')"

# =============================================================================
# STEP 1 — Update package lists
# =============================================================================
# Always run apt update before installing packages to get the latest package
# index from the repositories. This prevents "package not found" errors.
info "Updating apt package lists..."
sudo apt-get update -qq
success "Package lists updated"

# =============================================================================
# STEP 2 — Install prerequisites
# =============================================================================
# These packages are needed before we install K3s:
#
#   curl          — download K3s installer and Helm
#   git           — clone repos, used by ArgoCD
#   open-iscsi    — iSCSI initiator, required by some storage drivers (like
#                   Longhorn). Not strictly needed for local-path but good to
#                   have so adding storage later doesn't require re-running bootstrap.
#   nfs-common    — NFS client library. Allows mounting NFS volumes if you
#                   ever add a NAS to your homelab.
#
# The -y flag answers "yes" to all prompts (non-interactive install).

PACKAGES=(curl git open-iscsi nfs-common)

for pkg in "${PACKAGES[@]}"; do
  if dpkg -l "$pkg" 2>/dev/null | grep -q "^ii"; then
    info "Package already installed: $pkg"
  else
    info "Installing $pkg..."
    sudo apt-get install -y -qq "$pkg"
    success "Installed $pkg"
  fi
done

# =============================================================================
# STEP 3 — Disable swap
# =============================================================================
# Kubernetes REQUIRES swap to be disabled. The kubelet (K8s node agent) will
# refuse to start if swap is enabled because:
#   - Kubernetes memory limits become unreliable when swap is present
#   - Pod eviction decisions are based on memory pressure, not swap usage
#   - Performance is unpredictable when swap is used
#
# We need to disable it in two ways:
#   1. Immediately (for the current session): swapoff -a
#   2. Permanently (across reboots): comment it out in /etc/fstab

# Check if swap is currently active
if swapon --show | grep -q .; then
  info "Disabling swap..."
  sudo swapoff -a
  success "Swap disabled for current session"
else
  info "Swap is already disabled"
fi

# Permanently disable swap by commenting out swap entries in /etc/fstab
# /etc/fstab controls what gets mounted at boot, including swap partitions/files.
# We use sed to comment out any line containing " swap " (with spaces to avoid
# matching paths that happen to contain the word 'swap').
if grep -qE '^\s*[^#].*\sswap\s' /etc/fstab; then
  info "Commenting out swap in /etc/fstab..."
  sudo sed -i '/\sswap\s/s/^/#/' /etc/fstab
  success "Swap permanently disabled in /etc/fstab"
else
  info "No swap entries found in /etc/fstab (already clean)"
fi

# =============================================================================
# STEP 4 — Install K3s
# =============================================================================
# K3s is a certified Kubernetes distribution that packages everything into a
# single ~70MB binary. It's designed for IoT, edge computing, and homelab use.
#
# Installation options we're using:
#   INSTALL_K3S_CHANNEL=stable   — use the stable release channel (not latest/edge)
#   --disable=traefik            — K3s ships with Traefik as the default ingress
#                                  controller. We disable it because we'll use
#                                  ingress-nginx instead (more widely used, better
#                                  ArgoCD/Helm ecosystem support).
#   --write-kubeconfig-mode=644  — Make kubeconfig world-readable so we don't
#                                  need sudo to run kubectl commands.

if command -v k3s &>/dev/null && sudo k3s kubectl get node &>/dev/null 2>&1; then
  # K3s is already installed and the server is running
  K3S_VERSION=$(k3s --version | head -1)
  warn "K3s is already installed ($K3S_VERSION). Skipping installation."
  warn "To upgrade K3s, run: curl -sfL https://get.k3s.io | INSTALL_K3S_CHANNEL=stable sh -s -"
else
  info "Installing K3s (stable channel)..."
  info "This downloads the K3s binary and sets up a systemd service..."

  curl -sfL https://get.k3s.io | \
    INSTALL_K3S_CHANNEL=stable \
    sh -s - \
      --disable=traefik \
      --write-kubeconfig-mode=644

  success "K3s installed successfully"
fi

# =============================================================================
# STEP 5 — Configure kubeconfig
# =============================================================================
# kubectl (the Kubernetes CLI) looks for its configuration in ~/.kube/config
# by default. K3s stores its kubeconfig at /etc/rancher/k3s/k3s.yaml.
# We copy it to the standard location so kubectl, helm, and argocd CLI all work.

KUBECONFIG_DIR="$HOME/.kube"
KUBECONFIG_FILE="$KUBECONFIG_DIR/config"
K3S_KUBECONFIG="/etc/rancher/k3s/k3s.yaml"

info "Setting up kubeconfig..."
mkdir -p "$KUBECONFIG_DIR"

# Copy the K3s kubeconfig to the standard location
sudo cp "$K3S_KUBECONFIG" "$KUBECONFIG_FILE"

# Make the current user the owner (it was created as root by K3s)
sudo chown "$USER:$USER" "$KUBECONFIG_FILE"

# Restrict permissions to owner-only for security
# The kubeconfig contains credentials that can control the entire cluster
chmod 600 "$KUBECONFIG_FILE"

# Export KUBECONFIG so it's available for the rest of this script session
export KUBECONFIG="$KUBECONFIG_FILE"

success "kubeconfig written to $KUBECONFIG_FILE"

# =============================================================================
# STEP 6 — Wait for K3s to be Ready
# =============================================================================
# After installation, K3s takes a moment to start all its components.
# We wait until the node shows as "Ready" before proceeding.
# If we install Helm charts before K3s is ready, they'll fail.

info "Waiting for K3s node to become Ready (up to 120 seconds)..."

TIMEOUT=120
ELAPSED=0
INTERVAL=5

while true; do
  # Check if the node is ready
  # kubectl get node returns exit code 0 even if the node is NotReady,
  # so we grep for " Ready" in the output.
  if kubectl get node 2>/dev/null | grep -q " Ready"; then
    success "K3s node is Ready!"
    kubectl get node -o wide
    break
  fi

  if [[ $ELAPSED -ge $TIMEOUT ]]; then
    error "Timed out waiting for K3s node to be Ready after ${TIMEOUT}s"
  fi

  info "Node not ready yet... waiting ${INTERVAL}s (${ELAPSED}/${TIMEOUT}s elapsed)"
  sleep $INTERVAL
  ELAPSED=$((ELAPSED + INTERVAL))
done

# =============================================================================
# STEP 7 — Install Helm
# =============================================================================
# Helm is the Kubernetes package manager. It uses "charts" (packages) to
# deploy applications. ArgoCD uses Helm to deploy all the services in this repo.
#
# We use the official Helm installer script which:
# 1. Detects your OS and architecture
# 2. Downloads the correct Helm binary
# 3. Installs it to /usr/local/bin/helm

if command -v helm &>/dev/null; then
  HELM_VERSION=$(helm version --short 2>/dev/null || echo "unknown")
  info "Helm is already installed: $HELM_VERSION"
else
  info "Installing Helm..."
  curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
  success "Helm installed: $(helm version --short)"
fi

# =============================================================================
# STEP 8 — Add common Helm repositories
# =============================================================================
# Pre-add the Helm chart repositories we'll use so they're cached and ready.
# ArgoCD also manages these, but having them locally helps for manual debugging.

info "Adding Helm chart repositories..."

declare -A HELM_REPOS=(
  ["argo"]="https://argoproj.github.io/argo-helm"
  ["ingress-nginx"]="https://kubernetes.github.io/ingress-nginx"
  ["cert-manager"]="https://charts.jetstack.io"
  ["prometheus-community"]="https://prometheus-community.github.io/helm-charts"
  ["gitea-charts"]="https://dl.gitea.com/charts/"
)

for repo_name in "${!HELM_REPOS[@]}"; do
  repo_url="${HELM_REPOS[$repo_name]}"
  if helm repo list 2>/dev/null | grep -q "^$repo_name"; then
    info "Helm repo already added: $repo_name"
  else
    helm repo add "$repo_name" "$repo_url"
    success "Added Helm repo: $repo_name ($repo_url)"
  fi
done

helm repo update
success "Helm repositories updated"

# =============================================================================
# DONE
# =============================================================================

echo ""
echo -e "${GREEN}=============================================${NC}"
echo -e "${GREEN} Bootstrap complete!                         ${NC}"
echo -e "${GREEN}=============================================${NC}"
echo ""
echo "Cluster status:"
kubectl get nodes -o wide
echo ""
echo "Next steps:"
echo "  1. Make sure you've updated the REPO_URL placeholder in argocd/ manifests"
echo "  2. Run: bash scripts/install-argocd.sh https://github.com/roshanvrazak/homelab.git"
echo "  3. ArgoCD will then deploy all other services automatically"
echo ""
echo "Useful commands:"
echo "  kubectl get pods -A          # View all running pods"
echo "  kubectl get nodes -o wide    # View node details"
echo "  helm list -A                 # View installed Helm releases"
