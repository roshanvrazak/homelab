# Accessing Homelab Services

All services are exposed via ingress-nginx at `*.homelab.local`. Since this is a local-only setup with no external DNS, you need to tell your machines where to find these hostnames.

---

## Service URLs

| Service | URL |
|---------|-----|
| ArgoCD | http://argocd.homelab.local |
| Grafana | http://grafana.homelab.local |
| Prometheus | http://prometheus.homelab.local |
| Gitea | http://gitea.homelab.local |
| Homepage | http://homepage.homelab.local |
| ntfy | http://ntfy.homelab.local |

---

## Option 1 — Edit /etc/hosts (Simplest)

Add entries to `/etc/hosts` on **every machine** you want to access the homelab from.

Find your VM's IP address:
```bash
# On the K3s VM
hostname -I | awk '{print $1}'
# Or check Proxmox UI — the VM's IP is shown in the summary
```

On your **local Mac/Linux machine**:
```bash
sudo nano /etc/hosts
```

Add these lines (replace `192.168.0.100` with your VM's actual IP):
```
# Homelab services
192.168.0.100  argocd.homelab.local
192.168.0.100  grafana.homelab.local
192.168.0.100  prometheus.homelab.local
192.168.0.100  gitea.homelab.local
192.168.0.100  homepage.homelab.local
192.168.0.100  ntfy.homelab.local
```

On **Windows**:
Edit `C:\Windows\System32\drivers\etc\hosts` as Administrator with the same lines.

---

## Option 2 — Local DNS with Pi-hole or AdGuard Home

If you have Pi-hole or AdGuard Home on your network, add DNS rewrites:

**AdGuard Home**: Settings → DNS rewrites → Add rewrite:
- Domain: `*.homelab.local`
- Answer: `192.168.0.100`

**Pi-hole**: Settings → DNS → Local DNS Records → Add record for each hostname

This is the recommended approach as it works for all devices on your network automatically.

---

## Option 3 — Local DNS with dnsmasq

If you have a router that supports dnsmasq (OpenWrt, pfSense, etc.):

```
address=/homelab.local/192.168.0.100
```

This wildcard entry resolves all `*.homelab.local` to your K3s node.

---

## Default Credentials

### ArgoCD
- **Username**: `admin`
- **Password**: Retrieved during install. Run on the VM:
  ```bash
  kubectl -n argocd get secret argocd-initial-admin-secret \
    -o jsonpath="{.data.password}" | base64 -d && echo
  ```
- **First login**: Change the password immediately in User Info → Update Password

### Grafana
- **Username**: `admin`
- **Password**: `homelab-grafana` (set in values.yaml — change this!)
- Default dashboards are pre-loaded for Kubernetes monitoring

### Gitea
- First visit to `http://gitea.homelab.local` prompts you to complete setup
- Create your admin user on the first run

### ntfy
- No authentication by default (local network only)
- Access `http://ntfy.homelab.local` directly

---

## Port Forwarding (Alternative to Ingress)

If ingress isn't working yet, you can use kubectl port-forward to access services directly:

```bash
# ArgoCD UI
kubectl port-forward -n argocd svc/argocd-server 8080:80

# Grafana
kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80

# Gitea
kubectl port-forward -n gitea svc/gitea-http 3001:3000
```

Then access via `http://localhost:8080`, etc. This is also what `make dashboard` does.

---

## Troubleshooting

### Can't reach a service URL

1. **Check ingress-nginx is running:**
   ```bash
   kubectl get pods -n ingress-nginx
   kubectl get svc -n ingress-nginx
   ```

2. **Check the ingress resource exists:**
   ```bash
   kubectl get ingress -A
   ```

3. **Check the ingress controller has a LoadBalancer IP:**
   ```bash
   kubectl get svc -n ingress-nginx ingress-nginx-controller
   # EXTERNAL-IP should show your VM's IP, not <pending>
   ```
   If it shows `<pending>`, K3s ServiceLB may need a moment. Check:
   ```bash
   kubectl get pods -n kube-system -l app=svclb-ingress-nginx-controller
   ```

4. **Check /etc/hosts has the right IP:**
   ```bash
   cat /etc/hosts | grep homelab
   ping argocd.homelab.local
   ```

5. **Check ingress-nginx logs:**
   ```bash
   kubectl logs -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx --tail=50
   ```

### ArgoCD apps stuck in Progressing

```bash
# Check app status
kubectl get applications -n argocd

# Describe a specific app
kubectl describe application <app-name> -n argocd

# Force sync
kubectl patch application <app-name> -n argocd \
  --type merge -p '{"operation": {"initiatedBy": {"username": "admin"}, "sync": {}}}'
```
