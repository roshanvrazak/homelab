# Creating the Ubuntu VM in Proxmox

This guide walks you through creating the Ubuntu Server 24.04 VM that will host K3s.

---

## Prerequisites

- Proxmox VE installed and accessible at `192.168.0.65:8006`
- Ubuntu Server 24.04 LTS ISO downloaded (or accessible via URL)

---

## Step 1 — Download the Ubuntu ISO

In the Proxmox web UI:

1. Navigate to your node → **local** storage → **ISO Images**
2. Click **Download from URL** and paste:
   ```
   https://releases.ubuntu.com/24.04/ubuntu-24.04-live-server-amd64.iso
   ```
3. Click **Download** and wait for it to complete

---

## Step 2 — Create the VM

In Proxmox web UI, click **Create VM** in the top right:

### General tab
| Setting | Value |
|---------|-------|
| VM ID | `100` (or any unused ID) |
| Name | `k3s-node` |
| Start at boot | ✅ Enabled |

### OS tab
| Setting | Value |
|---------|-------|
| ISO Image | `ubuntu-24.04-live-server-amd64.iso` |
| Type | Linux |
| Version | 6.x - 2.6 Kernel |

### System tab
| Setting | Value |
|---------|-------|
| Machine | Default (i440fx) |
| BIOS | Default (SeaBIOS) |
| SCSI Controller | VirtIO SCSI single |
| Qemu Agent | ✅ Enabled |

### Disks tab
| Setting | Value |
|---------|-------|
| Bus/Device | VirtIO Block 0 (virtio0) |
| Storage | local-lvm |
| Disk size | **200 GiB** |
| Cache | Write back |
| Discard | ✅ Enabled (if SSD) |

### CPU tab
| Setting | Value |
|---------|-------|
| Sockets | 1 |
| Cores | **4** |
| Type | host (best performance) |

### Memory tab
| Setting | Value |
|---------|-------|
| Memory | **12288 MiB** (12 GB) |
| Ballooning | Disabled (K3s needs stable RAM) |

### Network tab
| Setting | Value |
|---------|-------|
| Bridge | **vmbr0** (bridged to your LAN) |
| Model | VirtIO (paravirtualized) |
| Firewall | Unchecked |

### Confirm tab
- Review and click **Finish**

---

## Step 3 — Install Ubuntu Server

1. Start the VM and open the **Console** in Proxmox
2. Boot from the ISO and follow the Ubuntu installer

### Recommended installer settings

- **Language**: English
- **Keyboard**: Your layout
- **Network**: DHCP is fine (we'll set a static IP after)
- **Storage**: Use entire disk, no LVM (simpler for homelab)
- **Profile setup**:
  - Your name: `homelab`
  - Server name: `k3s-node`
  - Username: `ubuntu` (or your preference)
  - Password: something strong
- **SSH**: ✅ Install OpenSSH server
- **Featured snaps**: Skip all (we install K3s manually)

After installation completes, reboot and remove the ISO from the CD drive:
- Proxmox → VM → Hardware → CD/DVD Drive → Set to "Do not use any media"

---

## Step 4 — Configure a Static IP (Recommended)

SSH into the VM, then edit the netplan config:

```bash
ssh ubuntu@<dhcp-assigned-ip>
```

Find the network interface name:
```bash
ip link show
# Look for something like: ens18, eth0, enp6s0
```

Edit the netplan config:
```bash
sudo nano /etc/netplan/00-installer-config.yaml
```

Replace with:
```yaml
network:
  version: 2
  ethernets:
    ens18:                        # Replace with your actual interface name
      dhcp4: false
      addresses:
        - 192.168.0.100/24        # Choose an unused IP on your LAN
      routes:
        - to: default
          via: 192.168.0.1        # Your router/gateway IP
      nameservers:
        addresses:
          - 1.1.1.1
          - 8.8.8.8
```

Apply the config:
```bash
sudo netplan apply
```

Verify:
```bash
ip addr show ens18
ping 1.1.1.1
```

---

## Step 5 — Install the QEMU Guest Agent

The QEMU agent lets Proxmox communicate with the VM (display IP in UI, graceful shutdown, etc.):

```bash
sudo apt update && sudo apt install -y qemu-guest-agent
sudo systemctl enable --now qemu-guest-agent
```

---

## Step 6 — Enable SSH key authentication (recommended)

On your **local machine**:
```bash
ssh-copy-id ubuntu@192.168.0.100
```

---

## Next Step

Your VM is ready. Proceed to [setup-k3s.md](setup-k3s.md) to install K3s.
