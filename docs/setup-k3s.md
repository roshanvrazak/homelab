# K3s Installation and Configuration

K3s is a lightweight, production-ready Kubernetes distribution from Rancher. It bundles everything into a single binary (~70MB) and comes with sensible defaults for single-node setups.

---

## Why K3s?

- Single binary, very low overhead (~512MB RAM for the control plane)
- Includes: containerd, CoreDNS, Traefik (we replace with ingress-nginx), ServiceLB, local-path-provisioner
- Production-tested — powers many homelabs and edge deployments
- Great documentation: https://docs.k3s.io

---

## Automated Installation

The `bootstrap.sh` script handles everything below automatically. Run it from your VM:

```bash
bash scripts/bootstrap.sh
```

For details on what it does, read on.

---

## Manual Installation Steps

### Step 1 — System Prerequisites

```bash
# Update package list
sudo apt update

# Install required packages
# - curl: download K3s installer
# - git: clone this repo and other tools
# - open-iscsi: required by some storage solutions (good to have)
# - nfs-common: NFS client support (useful for future storage)
sudo apt install -y curl git open-iscsi nfs-common

# Disable swap — Kubernetes requires swap to be off
# The kubelet will refuse to start if swap is enabled
sudo swapoff -a

# Make swap disabled permanent across reboots
# This comments out any swap entries in /etc/fstab
sudo sed -i '/ swap / s/^/#/' /etc/fstab
```

### Step 2 — Install K3s

```bash
# The official K3s installer script
# - INSTALL_K3S_CHANNEL=stable: use the stable release channel
# - --disable=traefik: we use ingress-nginx instead
# - --write-kubeconfig-mode=644: allow non-root users to read kubeconfig
curl -sfL https://get.k3s.io | \
  INSTALL_K3S_CHANNEL=stable \
  sh -s - \
    --disable=traefik \
    --write-kubeconfig-mode=644
```

**What this installs:**
- `k3s` binary (kubectl, crictl, ctr all bundled)
- `k3s-server` systemd service (starts automatically)
- CoreDNS (cluster DNS)
- local-path-provisioner (dynamic PVC storage using the host filesystem)
- ServiceLB (simple load balancer using host ports)

### Step 3 — Wait for the node to become Ready

```bash
# Watch the node status — it takes ~30-60 seconds
kubectl get node --watch

# You should see:
# NAME       STATUS   ROLES                  AGE   VERSION
# k3s-node   Ready    control-plane,master   60s   v1.x.x+k3s1
```

### Step 4 — Set up kubeconfig

```bash
# K3s writes its kubeconfig to /etc/rancher/k3s/k3s.yaml
# Copy it to the standard location so tools like helm, argocd CLI work
mkdir -p ~/.kube
sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
sudo chown $USER:$USER ~/.kube/config
chmod 600 ~/.kube/config
```

### Step 5 — Install Helm

Helm is the Kubernetes package manager. ArgoCD uses Helm charts to deploy all services.

```bash
# Download and run the official Helm installer
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Verify installation
helm version
```

---

## Verifying the Installation

```bash
# Check the node is ready
kubectl get nodes -o wide

# Check all system pods are running
kubectl get pods -A

# Check K3s system service status
sudo systemctl status k3s
```

Expected output — all pods should be in `Running` state:
```
NAMESPACE     NAME                                     READY   STATUS
kube-system   coredns-xxxx                             1/1     Running
kube-system   local-path-provisioner-xxxx              1/1     Running
kube-system   metrics-server-xxxx                      1/1     Running
kube-system   svclb-traefik-xxxx (if not disabled)     1/1     Running
```

---

## Understanding K3s Architecture

```
K3s Single-Node Architecture
─────────────────────────────
┌─────────────────────────────────────────┐
│  k3s-server (systemd service)           │
│                                         │
│  ┌─────────────────────────────────┐    │
│  │  Kubernetes Control Plane       │    │
│  │  • API Server    (port 6443)    │    │
│  │  • Scheduler                    │    │
│  │  • Controller Manager          │    │
│  │  • etcd (embedded SQLite)      │    │
│  └─────────────────────────────────┘    │
│                                         │
│  ┌─────────────────────────────────┐    │
│  │  Kubernetes Node (same machine) │    │
│  │  • kubelet                      │    │
│  │  • containerd (container rt)    │    │
│  │  • kube-proxy                   │    │
│  └─────────────────────────────────┘    │
│                                         │
│  ┌─────────────────────────────────┐    │
│  │  Built-in Addons                │    │
│  │  • CoreDNS                      │    │
│  │  • local-path-provisioner       │    │
│  │  • ServiceLB (MetalLB-like)     │    │
│  │  • Metrics Server               │    │
│  └─────────────────────────────────┘    │
└─────────────────────────────────────────┘
```

---

## K3s Storage (local-path-provisioner)

K3s ships with `local-path-provisioner` which dynamically creates PersistentVolumes using host directories. Data is stored under `/var/lib/rancher/k3s/storage/` by default.

```bash
# Check the default storage class
kubectl get storageclass

# NAME                   PROVISIONER             RECLAIMPOLICY
# local-path (default)   rancher.io/local-path   Delete
```

**Important:** Since data lives on the node's filesystem, pods must always be scheduled to the same node (not an issue for single-node clusters). Data is NOT replicated — back up `/var/lib/rancher/k3s/storage/` regularly.

---

## K3s Useful Commands

```bash
# View cluster info
kubectl cluster-info

# View all resources
kubectl get all -A

# View K3s logs
sudo journalctl -u k3s -f

# K3s configuration
cat /etc/rancher/k3s/k3s.yaml

# Restart K3s
sudo systemctl restart k3s

# Stop K3s
sudo systemctl stop k3s
```

---

## Next Step

Proceed to [install-argocd.sh](../scripts/install-argocd.sh) or run:

```bash
bash scripts/install-argocd.sh https://github.com/CHANGEME/homelab.git
```
