#!/usr/bin/env bash
# =============================================================================
# setup-github-repo.sh — Initialize git repo and push to GitHub
# =============================================================================
#
# This script:
#   1. Checks that the gh CLI is installed and authenticated
#   2. Creates a private GitHub repo called "homelab"
#   3. Initializes a local git repo (if not already done)
#   4. Commits all files
#   5. Pushes to GitHub
#
# Usage: bash scripts/setup-github-repo.sh
# Run this from the ROOT of the homelab directory.
#
# Prerequisites:
#   - gh CLI installed: https://cli.github.com/
#   - gh authenticated: run `gh auth login` first
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
# CONFIGURATION
# =============================================================================
# Change REPO_NAME if you want a different name for your GitHub repo.
REPO_NAME="homelab"
REPO_DESCRIPTION="Single-node Kubernetes homelab on Proxmox — GitOps with ArgoCD"
REPO_VISIBILITY="private"  # Change to "public" if you want a public repo

# =============================================================================
# STEP 1 — Check prerequisites
# =============================================================================

# Check we're in the right directory (the homelab repo root)
if [[ ! -f "README.md" ]] || [[ ! -d "scripts" ]]; then
  error "Please run this script from the root of the homelab directory."
fi

# Check gh CLI is installed
# gh is GitHub's official CLI tool: https://cli.github.com/
if ! command -v gh &>/dev/null; then
  error "gh CLI not found. Install it from https://cli.github.com/ then run:
    gh auth login
  Then re-run this script."
fi

info "Found gh CLI: $(gh --version | head -1)"

# Check gh is authenticated
# gh auth status returns exit code 0 if authenticated, non-zero otherwise
if ! gh auth status &>/dev/null; then
  error "gh CLI is not authenticated. Run:
    gh auth login
  Choose 'GitHub.com', 'HTTPS', and authenticate with your browser.
  Then re-run this script."
fi

# Get the authenticated username for display purposes
GH_USERNAME=$(gh api user --jq '.login' 2>/dev/null || echo "unknown")
info "Authenticated as GitHub user: $GH_USERNAME"

# Check git is installed
if ! command -v git &>/dev/null; then
  error "git is not installed. Install it with: sudo apt-get install -y git"
fi

# =============================================================================
# STEP 2 — Create GitHub repository
# =============================================================================
# We create the repo on GitHub first, then set it as the remote.
# gh repo create handles this cleanly.

info "Creating GitHub repository: $GH_USERNAME/$REPO_NAME..."

# Check if the repo already exists
if gh repo view "$GH_USERNAME/$REPO_NAME" &>/dev/null; then
  warn "Repository $GH_USERNAME/$REPO_NAME already exists on GitHub."
  warn "Will push to existing repo."
  REPO_URL="https://github.com/$GH_USERNAME/$REPO_NAME.git"
else
  # Create the repo
  # --private/--public controls visibility
  # --description sets the repo description shown on GitHub
  # We do NOT use --clone because we already have local files
  gh repo create "$REPO_NAME" \
    --${REPO_VISIBILITY} \
    --description "$REPO_DESCRIPTION"

  REPO_URL="https://github.com/$GH_USERNAME/$REPO_NAME.git"
  success "Created GitHub repository: $REPO_URL"
fi

# =============================================================================
# STEP 3 — Update REPO_URL placeholders in manifests
# =============================================================================
# ArgoCD manifests and install scripts use the placeholder
#   https://github.com/roshanvrazak/homelab.git
# which should be replaced with the actual GitHub URL.

PLACEHOLDER="https://github.com/roshanvrazak/homelab.git"
ACTUAL_URL="https://github.com/$GH_USERNAME/$REPO_NAME.git"

if grep -r "$PLACEHOLDER" . --include="*.yaml" --include="*.sh" --include="*.md" -l &>/dev/null; then
  info "Replacing REPO_URL placeholder in all files..."
  # Use sed to do an in-place replacement of the placeholder string
  # -i '' on macOS (BSD sed); -i on Linux (GNU sed)
  if [[ "$(uname)" == "Darwin" ]]; then
    grep -r "$PLACEHOLDER" . --include="*.yaml" --include="*.sh" --include="*.md" -l | \
      xargs sed -i '' "s|$PLACEHOLDER|$ACTUAL_URL|g"
  else
    grep -r "$PLACEHOLDER" . --include="*.yaml" --include="*.sh" --include="*.md" -l | \
      xargs sed -i "s|$PLACEHOLDER|$ACTUAL_URL|g"
  fi
  success "Updated REPO_URL placeholder to: $ACTUAL_URL"
else
  info "No REPO_URL placeholder found (may have already been replaced)"
fi

# =============================================================================
# STEP 4 — Initialize local git repository
# =============================================================================

if [[ -d ".git" ]]; then
  info "Git repository already initialized"
else
  info "Initializing git repository..."
  git init
  git branch -M main  # Use 'main' as the default branch name (modern standard)
  success "Git repository initialized with 'main' branch"
fi

# =============================================================================
# STEP 5 — Set up git remote
# =============================================================================

if git remote get-url origin &>/dev/null; then
  EXISTING_REMOTE=$(git remote get-url origin)
  if [[ "$EXISTING_REMOTE" == "$REPO_URL" ]]; then
    info "Git remote 'origin' already points to: $REPO_URL"
  else
    warn "Git remote 'origin' exists but points to: $EXISTING_REMOTE"
    warn "Updating to: $REPO_URL"
    git remote set-url origin "$REPO_URL"
    success "Updated git remote 'origin'"
  fi
else
  info "Setting git remote 'origin' to: $REPO_URL"
  git remote add origin "$REPO_URL"
  success "Git remote 'origin' set"
fi

# =============================================================================
# STEP 6 — Configure git user (if not already set)
# =============================================================================
# Git requires a name and email for commits. We check if they're set globally
# and prompt if not.

if ! git config user.name &>/dev/null; then
  GIT_NAME=$(gh api user --jq '.name // .login' 2>/dev/null || echo "")
  if [[ -n "$GIT_NAME" ]]; then
    git config user.name "$GIT_NAME"
    info "Set git user.name from GitHub profile: $GIT_NAME"
  else
    read -rp "Enter your git user name: " GIT_NAME
    git config user.name "$GIT_NAME"
  fi
fi

if ! git config user.email &>/dev/null; then
  GIT_EMAIL=$(gh api user --jq '.email // empty' 2>/dev/null || echo "")
  if [[ -z "$GIT_EMAIL" ]]; then
    # GitHub provides a noreply email for privacy
    GIT_EMAIL="${GH_USERNAME}@users.noreply.github.com"
  fi
  git config user.email "$GIT_EMAIL"
  info "Set git user.email: $GIT_EMAIL"
fi

# =============================================================================
# STEP 7 — Stage and commit all files
# =============================================================================

info "Staging all files for initial commit..."
git add -A

# Check if there are staged changes
if git diff --cached --quiet; then
  info "No changes to commit (repository is up to date)"
else
  info "Creating initial commit..."
  git commit -m "Initial homelab setup

Single-node Kubernetes homelab on Proxmox VE
- K3s with ArgoCD GitOps
- System: ingress-nginx, cert-manager, kube-prometheus-stack
- Apps: Gitea, Homepage, ntfy
- Inspired by https://github.com/khuedoan/homelab"
  success "Initial commit created"
fi

# =============================================================================
# STEP 8 — Push to GitHub
# =============================================================================

info "Pushing to GitHub ($REPO_URL)..."
git push -u origin main
success "Pushed to GitHub!"

# =============================================================================
# DONE
# =============================================================================

echo ""
echo -e "${GREEN}=============================================${NC}"
echo -e "${GREEN} GitHub setup complete!                      ${NC}"
echo -e "${GREEN}=============================================${NC}"
echo ""
echo "  Repository URL: $REPO_URL"
echo "  GitHub page:    https://github.com/$GH_USERNAME/$REPO_NAME"
echo ""
echo "Next steps:"
echo "  1. SSH into your Proxmox VM"
echo "  2. Clone this repo: git clone $REPO_URL"
echo "  3. Run: bash scripts/bootstrap.sh"
echo "  4. Run: bash scripts/install-argocd.sh $REPO_URL"
echo ""
