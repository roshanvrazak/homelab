# Provisioning the Proxmox VM with Terraform

Instead of manually clicking through the Proxmox UI to create the VM, we use Terraform to declare the desired state and have it created automatically. This is Infrastructure as Code (IaC) — the VM configuration is version-controlled, reproducible, and easy to recreate.

---

## What Terraform does

1. Downloads the Ubuntu 24.04 cloud image directly to your Proxmox host
2. Creates a VM with the specified CPU/RAM/disk configuration
3. Injects a cloud-init config that sets up: hostname, user, SSH key, static IP
4. Installs prerequisite packages (qemu-guest-agent, curl, git, etc.) on first boot
5. Disables swap and resizes the root partition automatically

After `terraform apply`, you SSH in and run `bootstrap.sh` to install K3s.

---

## Prerequisites

### 1. Install Terraform on your local machine

```bash
# macOS (Homebrew)
brew tap hashicorp/tap
brew install hashicorp/tap/terraform

# Ubuntu/Debian
wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt update && sudo apt install terraform

# Verify
terraform version  # Should be >= 1.6
```

### 2. Create a Proxmox API Token

The `bpg/proxmox` Terraform provider authenticates via an API token (more secure than a password — can be revoked without changing your root password).

**In the Proxmox web UI (https://192.168.0.65:8006):**

1. Log in as `root`
2. Navigate to: **Datacenter** → **Permissions** → **API Tokens**
3. Click **Add**:
   - **User**: `root@pam`
   - **Token ID**: `terraform`
   - **Privilege Separation**: **Unchecked** (gives the token full root permissions)
4. Click **Add** — Proxmox shows the token secret **once**. Copy it immediately!

The token format is: `root@pam!terraform=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx`

> **Note on Privilege Separation**: Unchecked means the token inherits root's permissions. Checked would let you scope the token's permissions separately. For a homelab, unchecked (full access) is fine.

### 3. Enable SSH access to Proxmox

The `bpg/proxmox` provider needs SSH access to the Proxmox host to upload the cloud-init snippet file. Proxmox has SSH enabled by default on port 22.

If you use an SSH key for Proxmox access, add it to your SSH agent:
```bash
ssh-add ~/.ssh/your-proxmox-key
# Or just ensure you can SSH in: ssh root@192.168.0.65
```

### 4. Enable snippets on Proxmox "local" storage

Cloud-init config files are stored as "snippets" in Proxmox. By default, the `local` storage may not have snippets enabled.

**In Proxmox UI:**
1. **Datacenter** → **Storage** → click **local**
2. Click **Edit**
3. Under **Content**, add **Snippets** to the list
4. Click **OK**

Or via SSH on the Proxmox host:
```bash
pvesm set local --content iso,vztmpl,backup,snippets
```

### 5. Generate an SSH key (if you don't have one)

```bash
# Generate a new Ed25519 key (recommended — smaller and more secure than RSA)
ssh-keygen -t ed25519 -C "homelab" -f ~/.ssh/id_ed25519

# View your public key (this goes in terraform.tfvars)
cat ~/.ssh/id_ed25519.pub
```

---

## Deploy

### Step 1 — Configure variables

```bash
cd terraform/

# Copy the example file
cp terraform.tfvars.example terraform.tfvars

# Edit with your values
nano terraform.tfvars  # or code terraform.tfvars
```

Key values to change:
| Variable | What to set |
|----------|-------------|
| `proxmox_api_token` | The token you created above |
| `proxmox_node` | Your Proxmox node name (check the sidebar in Proxmox UI) |
| `vm_ip` | An unused static IP on your LAN |
| `vm_ssh_public_key` | Contents of `~/.ssh/id_ed25519.pub` |

### Step 2 — Initialise Terraform

```bash
terraform init
```

This downloads the `bpg/proxmox` provider into `.terraform/`. Only needed once (or after changing provider versions).

Expected output:
```
Initializing provider plugins...
- Finding bpg/proxmox versions matching "~> 0.69"...
- Installing bpg/proxmox v0.69.x...
Terraform has been successfully initialized!
```

### Step 3 — Preview the plan

```bash
terraform plan
```

Terraform shows exactly what it will create/modify/destroy **without making any changes**. Always review the plan before applying.

Expected resources to create:
```
+ proxmox_virtual_environment_download_file.ubuntu_cloud_image
+ proxmox_virtual_environment_file.cloud_init_user_data
+ proxmox_virtual_environment_vm.k3s_node
```

### Step 4 — Apply

```bash
terraform apply
```

Terraform will show the plan again and prompt: `Do you want to perform these actions? (yes/no)` — type `yes`.

**What happens:**
1. Proxmox downloads Ubuntu 24.04 cloud image (~600MB, ~2 minutes)
2. Cloud-init snippet is uploaded to Proxmox
3. VM is created and started (~30 seconds)
4. Cloud-init runs on first boot (~3-5 minutes): updates packages, installs agent, disables swap

**Total time:** ~5-10 minutes

After apply, Terraform prints the outputs:
```
Outputs:

ssh_command    = "ssh ubuntu@192.168.0.100"
vm_ip          = "192.168.0.100"
next_steps     = <<EOT
  ============================================================
  VM provisioned successfully!
  ...
```

### Step 5 — Wait for cloud-init

```bash
# Check cloud-init status (run from your local machine)
ssh ubuntu@192.168.0.100 'cloud-init status --wait'
# Output: status: done
```

Or watch the Proxmox console (click the VM → Console in the Proxmox UI) to see the boot process.

### Step 6 — Continue with K3s setup

```bash
# SSH into the VM
ssh ubuntu@192.168.0.100

# Clone the homelab repo
git clone https://github.com/roshanvrazak/homelab.git
cd homelab

# Install K3s and Helm
bash scripts/bootstrap.sh

# Install ArgoCD (deploys everything else)
bash scripts/install-argocd.sh https://github.com/roshanvrazak/homelab.git
```

---

## Makefile shortcuts

From the repo root, you can use:
```bash
make tf-init     # terraform init
make tf-plan     # terraform plan (preview changes)
make tf-apply    # terraform apply (create/update VM)
make tf-destroy  # terraform destroy (DELETES the VM)
make tf-output   # show terraform outputs
```

---

## Understanding the Terraform state

Terraform keeps track of what it created in a **state file** (`terraform/terraform.tfstate`). This file:
- Records which Proxmox resources Terraform manages
- Is used to compute the diff for the next `plan`/`apply`
- **Should never be committed to git** (contains sensitive data — already in `.gitignore`)
- **Should be backed up** — losing state means Terraform "forgets" about the VM

For a homelab, storing state locally is fine. If you want to share state or avoid losing it, consider:
- Terraform Cloud (free tier, remote state)
- S3-compatible backend (Minio, Gitea packages, AWS S3)

---

## Modifying the VM after creation

To change the VM specs (e.g. add more RAM), edit `terraform.tfvars`, then:

```bash
terraform plan   # See what will change
terraform apply  # Apply the change
```

Terraform will update the VM in place (no recreation needed for most changes like RAM/CPU).

Changes that require VM recreation (destroy + create):
- Changing the disk size requires resizing from inside the OS (not Terraform)
- Changing the VM ID

---

## Destroying the VM

```bash
cd terraform/
terraform destroy
```

This will delete the VM and its disk from Proxmox. **All data on the VM will be lost.**

The downloaded cloud image in Proxmox storage is **not** deleted (it's managed as a separate resource and would be reused next time).

---

## Troubleshooting

### Error: 401 Unauthorized
- Check your `proxmox_api_token` in terraform.tfvars
- Make sure "Privilege Separation" was **unchecked** when creating the token
- Verify the token in Proxmox: Datacenter → Permissions → API Tokens

### Error: SSH connection refused
- Make sure you can SSH to Proxmox: `ssh root@192.168.0.65`
- Try adding your key: `ssh-add ~/.ssh/id_ed25519`
- Check `proxmox_ssh_username` and `proxmox_ssh_password` in tfvars

### Error: storage 'local' does not support content type 'snippets'
- Follow the "Enable snippets" step above in the Proxmox UI
- Then re-run `terraform apply`

### Error: VMID already exists
- Change `vm_id` in terraform.tfvars to an unused ID
- Or delete the conflicting VM in Proxmox UI first

### VM boots but cloud-init didn't run / no SSH access
- Check the Proxmox console (VM → Console) for boot errors
- Run: `ssh root@192.168.0.65 "qm cloudinit dump 100"` to see the generated cloud-init config
- Check cloud-init logs: `ssh ubuntu@192.168.0.100 'cat /var/log/cloud-init-output.log'`

### Static IP not applied
- Verify `vm_ip`, `vm_gateway`, `vm_netmask` in tfvars
- Check netplan config on the VM: `cat /etc/netplan/*.yaml`
- Apply netplan: `sudo netplan apply`
