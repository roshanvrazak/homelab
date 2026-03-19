# Homelab

A single-node Kubernetes homelab running on Proxmox, managed with GitOps (ArgoCD) and Infrastructure as Code.

Inspired by [khuedoan/homelab](https://github.com/khuedoan/homelab) — a fantastic reference for anyone building a production-like homelab.

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│  Physical Host: HP Mini PC (Intel i5-8500, 16GB RAM, 256GB SSD) │
│                                                                  │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │  Proxmox VE (192.168.0.65:8006)                           │  │
│  │                                                           │  │
│  │  ┌─────────────────────────────────────────────────────┐  │  │
│  │  │  Ubuntu 24.04 VM (4 vCPU, 12GB RAM, 200GB disk)     │  │  │
│  │  │  192.168.0.x (bridged)                              │  │  │
│  │  │                                                     │  │  │
│  │  │  ┌───────────────────────────────────────────────┐  │  │  │
│  │  │  │  K3s (single-node Kubernetes)                 │  │  │  │
│  │  │  │                                               │  │  │  │
│  │  │  │  ┌──────────┐  GitOps sync  ┌─────────────┐  │  │  │  │
│  │  │  │  │  ArgoCD  │◄─────────────│  GitHub Repo │  │  │  │  │
│  │  │  │  └──────────┘               └─────────────┘  │  │  │  │
│  │  │  │       │                                       │  │  │  │
│  │  │  │       │ deploys                               │  │  │  │
│  │  │  │       ▼                                       │  │  │  │
│  │  │  │  ┌─────────────────────────────────────────┐  │  │  │  │
│  │  │  │  │  Apps                                   │  │  │  │  │
│  │  │  │  │  • ingress-nginx   (HTTP routing)       │  │  │  │  │
│  │  │  │  │  • cert-manager    (TLS certificates)   │  │  │  │  │
│  │  │  │  │  • kube-prometheus (metrics/dashboards) │  │  │  │  │
│  │  │  │  │  • Gitea           (self-hosted Git)    │  │  │  │  │
│  │  │  │  │  • Homepage        (service dashboard)  │  │  │  │  │
│  │  │  │  │  • ntfy            (notifications)      │  │  │  │  │
│  │  │  │  └─────────────────────────────────────────┘  │  │  │  │
│  │  │  └───────────────────────────────────────────────┘  │  │  │
│  │  └─────────────────────────────────────────────────────┘  │  │
│  └───────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

---

## Hardware

| Component | Spec |
|-----------|------|
| Host | HP Mini PC |
| CPU | Intel Core i5-8500 |
| RAM | 16 GB |
| Storage | 256 GB SSD |
| Hypervisor | Proxmox VE |
| VM | Ubuntu Server 24.04 LTS |
| VM vCPU | 4 cores |
| VM RAM | 12 GB |
| VM Disk | 200 GB |
| Network | Bridged (192.168.0.x) |

---

## Quick Start

### Prerequisites

- Proxmox VE running on your hardware
- A GitHub account with `gh` CLI installed and authenticated on your local machine
- SSH access to your Proxmox host

### Step 1 — Create the Proxmox VM

Follow [docs/setup-proxmox-vm.md](docs/setup-proxmox-vm.md) to create an Ubuntu 24.04 VM.

### Step 2 — Clone this repo and push to your GitHub

On your **local machine**:

```bash
git clone https://github.com/roshanvrazak/homelab.git
cd homelab

# Update the REPO_URL placeholder with your actual GitHub repo URL
grep -r "roshanvrazak" . --include="*.yaml" --include="*.sh" -l
# Then do a find-and-replace: change https://github.com/roshanvrazak/homelab.git
# to your actual repo URL (e.g. https://github.com/yourusername/homelab.git)

# Push to your own GitHub repo
bash scripts/setup-github-repo.sh
```

### Step 3 — Bootstrap K3s on the VM

SSH into your Ubuntu VM and run:

```bash
curl -sSL https://raw.githubusercontent.com/roshanvrazak/homelab/main/scripts/bootstrap.sh | bash
# Or if you've cloned the repo onto the VM:
bash scripts/bootstrap.sh
```

### Step 4 — Install ArgoCD

Still on the VM:

```bash
bash scripts/install-argocd.sh https://github.com/roshanvrazak/homelab.git
```

ArgoCD will then take over and deploy everything else from the repo automatically.

### Step 5 — Access your services

Add the homelab hostnames to your local `/etc/hosts` (see [docs/accessing-services.md](docs/accessing-services.md)), then open your browser.

---

## Deployed Services

| Service | URL | Description | Default Port |
|---------|-----|-------------|--------------|
| ArgoCD | http://argocd.homelab.local | GitOps CD dashboard | 443 → ingress |
| Grafana | http://grafana.homelab.local | Metrics & dashboards | 443 → ingress |
| Gitea | http://gitea.homelab.local | Self-hosted Git server | 443 → ingress |
| Homepage | http://homepage.homelab.local | Service dashboard | 443 → ingress |
| ntfy | http://ntfy.homelab.local | Push notifications | 443 → ingress |
| Prometheus | Internal | Metrics scraping | ClusterIP only |
| AlertManager | Internal | Alert routing | ClusterIP only |

---

## Resource Budget

Approximate RAM usage per component (12GB VM total):

| Component | RAM Target |
|-----------|-----------|
| OS + K3s control plane | ~1.0 GB |
| ArgoCD | ~300 MB |
| ingress-nginx | ~100 MB |
| cert-manager | ~50 MB |
| kube-prometheus-stack | ~1.0 GB |
| Gitea | ~200 MB |
| Homepage | ~50 MB |
| ntfy | ~50 MB |
| **Total** | **~2.75 GB** |
| **Headroom** | **~9.25 GB** |

---

## Learning Resources

| Technology | Resource |
|------------|---------|
| Kubernetes | [kubernetes.io/docs](https://kubernetes.io/docs/home/) |
| K3s | [docs.k3s.io](https://docs.k3s.io/) |
| Helm | [helm.sh/docs](https://helm.sh/docs/) |
| ArgoCD | [argo-cd.readthedocs.io](https://argo-cd.readthedocs.io/) |
| Proxmox | [pve.proxmox.com/wiki](https://pve.proxmox.com/wiki/Main_Page) |
| GitOps | [opengitops.dev](https://opengitops.dev/) |
| Prometheus | [prometheus.io/docs](https://prometheus.io/docs/introduction/overview/) |
| Grafana | [grafana.com/docs](https://grafana.com/docs/) |
| cert-manager | [cert-manager.io/docs](https://cert-manager.io/docs/) |
| ingress-nginx | [kubernetes.github.io/ingress-nginx](https://kubernetes.github.io/ingress-nginx/) |

---

## Acknowledgements

This project is heavily inspired by [khuedoan/homelab](https://github.com/khuedoan/homelab). If you want to see a more advanced, multi-node, fully automated homelab setup, check out Khue's excellent work.
