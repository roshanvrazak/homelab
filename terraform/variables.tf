# =============================================================================
# variables.tf — Input Variable Declarations
# =============================================================================
#
# Variables let you customise the deployment without editing main.tf.
# Values are supplied via terraform.tfvars (see terraform.tfvars.example).
#
# Variable types used here:
#   string  — text value
#   number  — integer or float
#   bool    — true/false
#
# "sensitive = true" means Terraform won't print the value in plan/apply output
# or store it in the plan file in plaintext. Use this for passwords and tokens.
# =============================================================================

# =============================================================================
# Proxmox connection
# =============================================================================

variable "proxmox_endpoint" {
  description = "URL of the Proxmox API endpoint, including port. e.g. https://192.168.0.65:8006"
  type        = string
  default     = "https://192.168.0.65:8006"
}

variable "proxmox_api_token" {
  description = <<-EOT
    Proxmox API token in the format: USER@REALM!TOKENID=UUID
    Example: root@pam!terraform=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx

    Create one in Proxmox UI:
      Datacenter → Permissions → API Tokens → Add
      User: root@pam (or a dedicated user)
      Token ID: terraform
      Privilege Separation: unchecked (gives full permissions)
  EOT
  type      = string
  sensitive = true
  # No default — must be set in terraform.tfvars
}

variable "proxmox_insecure" {
  description = <<-EOT
    Skip TLS certificate verification for the Proxmox API.
    Set to true if Proxmox is using its default self-signed certificate
    (which it does by default). Set to false only if you have a valid
    certificate from a trusted CA.
  EOT
  type    = bool
  default = true
}

variable "proxmox_node" {
  description = "Name of the Proxmox node where the VM will be created. Find it in the Proxmox UI sidebar (e.g. 'pve', 'proxmox', or the hostname of your server)."
  type        = string
  default     = "pve"
}

variable "proxmox_ssh_username" {
  description = <<-EOT
    Username for SSH access to the Proxmox host.
    The bpg/proxmox provider uses SSH for operations that require direct
    node access (e.g. uploading cloud-init ISOs, file operations).
    This is usually 'root' for a standard Proxmox installation.
  EOT
  type    = string
  default = "root"
}

variable "proxmox_ssh_password" {
  description = <<-EOT
    Password for SSH access to the Proxmox host.
    Used if SSH key agent is not available.
    Leave empty if using SSH key agent (ssh-add).
  EOT
  type      = string
  sensitive = true
  default   = ""
}

# =============================================================================
# VM identity
# =============================================================================

variable "vm_id" {
  description = <<-EOT
    Proxmox VM ID — a unique integer identifier for the VM.
    Valid range: 100–999999999. Convention: 100+ for VMs, 900+ for templates.
    Check existing IDs in Proxmox UI to avoid conflicts.
  EOT
  type    = number
  default = 100
}

variable "vm_name" {
  description = "Hostname of the VM as shown in Proxmox and set via cloud-init."
  type        = string
  default     = "k3s-node"
}

variable "vm_description" {
  description = "Human-readable description shown in the Proxmox UI."
  type        = string
  default     = "K3s single-node Kubernetes homelab — managed by Terraform"
}

# =============================================================================
# VM compute resources
# =============================================================================

variable "vm_cores" {
  description = "Number of virtual CPU cores assigned to the VM."
  type        = number
  default     = 4
}

variable "vm_memory_mb" {
  description = <<-EOT
    RAM allocated to the VM in megabytes.
    12GB = 12288 MB. Formula: GB × 1024.
    K3s uses ~500MB at idle; leave headroom for workloads.
  EOT
  type    = number
  default = 12288  # 12 GB
}

variable "vm_disk_size_gb" {
  description = "Size of the primary disk in gigabytes. 200GB provides ample space for container images, PV data, and OS."
  type        = number
  default     = 200
}

variable "vm_storage" {
  description = <<-EOT
    Proxmox storage ID where the VM disk will be created.
    Check available storages in Proxmox UI: Datacenter → Storage.
    Common values: 'local-lvm', 'local', 'nvme', 'ssd'.
  EOT
  type    = string
  default = "local-lvm"
}

variable "vm_storage_iso" {
  description = <<-EOT
    Proxmox storage ID where ISOs and cloud images are stored.
    Usually 'local' (directory-type storage that supports iso content).
    Must support 'iso' content type.
  EOT
  type    = string
  default = "local"
}

# =============================================================================
# VM networking
# =============================================================================

variable "vm_bridge" {
  description = <<-EOT
    Network bridge to attach the VM's NIC to.
    'vmbr0' is the default bridge in Proxmox, connected to your physical NIC.
    This gives the VM a presence on your LAN (bridged networking).
  EOT
  type    = string
  default = "vmbr0"
}

variable "vm_ip" {
  description = <<-EOT
    Static IP address for the VM (without the subnet mask).
    Choose an IP on your LAN subnet that won't be assigned by DHCP.
    Example: if your router uses 192.168.0.1-99 for DHCP, use 192.168.0.100+
  EOT
  type    = string
  default = "192.168.0.100"
}

variable "vm_netmask" {
  description = "CIDR prefix length for the VM's IP. 24 = /24 = 255.255.255.0 (standard home network)."
  type        = number
  default     = 24
}

variable "vm_gateway" {
  description = "Default gateway IP (your router's IP address)."
  type        = string
  default     = "192.168.0.1"
}

variable "vm_dns_servers" {
  description = "DNS servers for the VM. Defaults to Cloudflare (1.1.1.1) and Google (8.8.8.8)."
  type        = list(string)
  default     = ["1.1.1.1", "8.8.8.8"]
}

# =============================================================================
# Cloud-init (OS configuration on first boot)
# =============================================================================

variable "vm_user" {
  description = <<-EOT
    Username for the default VM user (created by cloud-init on first boot).
    You'll SSH into the VM as this user. 'ubuntu' is conventional for Ubuntu VMs.
  EOT
  type    = string
  default = "ubuntu"
}

variable "vm_password" {
  description = <<-EOT
    Password for the VM user (hashed by cloud-init).
    Only used as a fallback if SSH key auth fails (e.g. console access).
    Strong password recommended. Leave empty to disable password auth.
  EOT
  type      = string
  sensitive = true
  default   = ""
}

variable "vm_ssh_public_key" {
  description = <<-EOT
    SSH public key to inject into the VM for passwordless login.
    Get yours with: cat ~/.ssh/id_ed25519.pub (or id_rsa.pub)
    Generate if missing: ssh-keygen -t ed25519 -C "homelab"

    This is PUBLIC data — safe to commit (but we keep it in tfvars for flexibility).
  EOT
  type = string
  # No default — must be set. Your SSH public key is required for access.
}

# =============================================================================
# Ubuntu cloud image
# =============================================================================

variable "ubuntu_cloud_image_url" {
  description = <<-EOT
    URL of the Ubuntu 24.04 (Noble) cloud image to download.
    Cloud images are pre-installed Ubuntu VMs designed for cloud/automation use.
    They support cloud-init for configuration on first boot.
    The Proxmox node will download this directly (not your local machine).
  EOT
  type    = string
  default = "https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
}

variable "ubuntu_cloud_image_checksum" {
  description = <<-EOT
    SHA256 checksum of the cloud image for integrity verification.
    Update this when changing ubuntu_cloud_image_url.
    Get the checksum from: https://cloud-images.ubuntu.com/noble/current/SHA256SUMS
    Leave empty to skip checksum verification (not recommended for production).
  EOT
  type    = string
  default = ""
  # To get the current checksum:
  # curl -s https://cloud-images.ubuntu.com/noble/current/SHA256SUMS | grep "noble-server-cloudimg-amd64.img"
}

# =============================================================================
# VM tags (optional, for organisation in Proxmox UI)
# =============================================================================

variable "vm_tags" {
  description = "Tags to apply to the VM in Proxmox UI (for organisation and filtering)."
  type        = list(string)
  default     = ["k3s", "homelab", "terraform"]
}
