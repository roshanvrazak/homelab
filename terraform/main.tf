# =============================================================================
# main.tf — Proxmox VM Provisioning for K3s Homelab
# =============================================================================
#
# This file provisions:
#   1. The Ubuntu 24.04 cloud image (downloaded to Proxmox storage)
#   2. The K3s VM (cloned from the cloud image with cloud-init config)
#
# Architecture:
#   Terraform (your machine) → Proxmox API (192.168.0.65:8006) → VM created
#
# What cloud-init does on first boot:
#   - Sets hostname (vm_name)
#   - Creates user (vm_user) with your SSH public key
#   - Configures static IP (vm_ip/vm_netmask/vm_gateway)
#   - Installs qemu-guest-agent (Proxmox integration)
#   - Disables swap (required for Kubernetes)
#   - Resizes the root partition to use all available disk space
#
# After Terraform completes, you SSH in and run bootstrap.sh.
# =============================================================================

# =============================================================================
# Provider configuration
# =============================================================================
# The bpg/proxmox provider connects to Proxmox via:
#   1. HTTPS REST API (for VM management operations)
#   2. SSH (for file uploads, e.g. cloud-init ISO)
#
# Authentication uses an API token (safer than password — can be revoked).
# See docs/setup-terraform.md for how to create the API token.

provider "proxmox" {
  # Proxmox API endpoint — the same URL you use to access the web UI
  endpoint = var.proxmox_endpoint

  # API token: format is "USER@REALM!TOKENID=SECRET"
  # e.g. "root@pam!terraform=3988d338-1ebc-4dab-ba82-a619c7a30cb0"
  api_token = var.proxmox_api_token

  # Skip TLS verification — needed because Proxmox uses a self-signed cert by default
  # In production, you'd install a proper cert and set this to false
  insecure = var.proxmox_insecure

  # SSH access to the Proxmox host (needed for file upload operations)
  # The provider uses SSH to upload the cloud-init ISO to Proxmox storage
  ssh {
    agent    = true  # Use SSH agent (ssh-add your key first)
    username = var.proxmox_ssh_username

    # Password fallback if SSH agent doesn't have a key for Proxmox
    password = var.proxmox_ssh_password

    # Or use a specific private key file:
    # private_key = file("~/.ssh/id_ed25519")
  }
}

# =============================================================================
# RESOURCE 1: Download Ubuntu 24.04 Cloud Image
# =============================================================================
# Cloud images are pre-installed, minimal Ubuntu VMs designed for automation.
# They're different from installation ISOs — the OS is already installed,
# and cloud-init handles first-boot configuration (users, networking, etc.).
#
# This resource tells Proxmox to download the image directly from Ubuntu's
# servers into its local storage. This only happens once — if the file
# already exists in Proxmox storage, Terraform detects it and skips download.
#
# The image is stored as an "iso" content type because Proxmox treats .img
# files the same way (it's just a raw disk image, not a live installer).

resource "proxmox_virtual_environment_download_file" "ubuntu_cloud_image" {
  # Content type: "iso" covers both ISOs and raw disk images (.img)
  content_type = "iso"

  # Storage where the image will be saved on the Proxmox host
  # "local" is the default directory-based storage that supports ISOs
  datastore_id = var.vm_storage_iso

  # Which Proxmox node downloads the file
  node_name = var.proxmox_node

  # URL to download from — Ubuntu's official cloud image server
  url = var.ubuntu_cloud_image_url

  # Rename the downloaded file to something consistent
  # The URL contains a date-stamped filename; this gives us a stable name
  file_name = "ubuntu-24.04-noble-cloudimg-amd64.img"

  # Verify the download integrity with SHA256 checksum (recommended)
  # If checksum is empty string, verification is skipped
  checksum_algorithm = var.ubuntu_cloud_image_checksum != "" ? "sha256" : null
  checksum           = var.ubuntu_cloud_image_checksum != "" ? var.ubuntu_cloud_image_checksum : null

  # Don't re-download if the file already exists in Proxmox storage
  # Set to true to force a re-download (e.g. to get a newer version)
  overwrite = false
}

# =============================================================================
# RESOURCE 2: Cloud-init user-data
# =============================================================================
# Cloud-init is the industry standard for cloud VM first-boot configuration.
# It reads a YAML config ("user-data") on first boot and applies it.
#
# We create a cloud-init snippet file on Proxmox storage, then reference it
# in the VM configuration. This gives us more control than the built-in
# cloud-init fields (e.g. we can install packages, run commands, etc.).
#
# The snippet is stored in Proxmox's "snippets" directory:
#   /var/lib/vz/snippets/ (for "local" storage)

resource "proxmox_virtual_environment_file" "cloud_init_user_data" {
  # "snippets" content type is for cloud-init and other config files
  content_type = "snippets"
  datastore_id = var.vm_storage_iso
  node_name    = var.proxmox_node

  source_raw {
    # Filename on the Proxmox host
    file_name = "${var.vm_name}-user-data.yaml"

    # The cloud-init user-data YAML content
    # Cloud-init spec: https://cloudinit.readthedocs.io/en/latest/reference/examples.html
    data = <<-USERDATA
    #cloud-config
    # ==========================================================================
    # Cloud-init user-data for ${var.vm_name}
    # Applied on first boot by the cloud-init service
    # ==========================================================================

    # Set the hostname
    hostname: ${var.vm_name}
    fqdn: ${var.vm_name}.homelab.local
    manage_etc_hosts: true

    # Create the default user
    users:
      - name: ${var.vm_user}
        groups: [sudo, adm, docker]
        shell: /bin/bash
        sudo: ALL=(ALL) NOPASSWD:ALL
        # Inject the SSH public key for passwordless login
        ssh_authorized_keys:
          - ${var.vm_ssh_public_key}
        # Lock the password (SSH key only) — more secure
        lock_passwd: ${var.vm_password == "" ? "true" : "false"}
        %{if var.vm_password != ""}
        # Password is hashed with SHA-512 — never stored in plaintext
        # Generate hash: openssl passwd -6 'yourpassword'
        passwd: ${var.vm_password}
        %{endif}

    # Disable root SSH login (security best practice)
    disable_root: true

    # SSH hardening
    ssh_pwauth: false  # Disable password auth (key-only)

    # Install packages on first boot
    # These are the same packages bootstrap.sh installs — having them
    # pre-installed means bootstrap.sh runs faster
    packages:
      - qemu-guest-agent  # Proxmox integration: graceful shutdown, IP display
      - curl              # Download K3s installer
      - git               # Required by ArgoCD and bootstrap
      - open-iscsi        # iSCSI support for storage drivers
      - nfs-common        # NFS client library

    # Update package list and upgrade all packages on first boot
    package_update: true
    package_upgrade: true

    # Commands to run on first boot (after packages are installed)
    runcmd:
      # Enable and start QEMU guest agent so Proxmox can communicate with VM
      - systemctl enable --now qemu-guest-agent

      # Disable swap permanently — Kubernetes requires swap to be off
      # swapoff -a: disable for current session
      - swapoff -a
      # Comment out swap in /etc/fstab: persistent across reboots
      - sed -i '/\sswap\s/s/^/#/' /etc/fstab

      # Grow the root partition to use all available disk space
      # Cloud images come with a small root partition; we need to resize it
      # to use the full 200GB disk we provisioned
      - growpart /dev/vda 1 || true       # Grow partition 1 on virtio disk
      - resize2fs /dev/vda1 || true        # Resize ext4 filesystem
      - pvresize /dev/vda1 || true         # Resize LVM physical volume (if LVM)

      # Set timezone to UTC (consistent, avoids daylight saving issues)
      - timedatectl set-timezone UTC

      # Log completion so we can check cloud-init ran successfully
      - echo "Cloud-init complete for ${var.vm_name}" >> /var/log/cloud-init-homelab.log

    # Final message shown in cloud-init logs when complete
    final_message: |
      ================================================
      K3s homelab VM is ready!
      Hostname: ${var.vm_name}
      User:     ${var.vm_user}
      Next:     ssh ${var.vm_user}@${var.vm_ip}
                then: bash scripts/bootstrap.sh
      ================================================
    USERDATA
  }
}

# =============================================================================
# RESOURCE 3: The K3s VM
# =============================================================================
# This is the main resource — it creates the actual Proxmox VM.
#
# The VM uses the cloud image as its base disk (not as a live installer).
# Proxmox imports the cloud image as the VM's primary disk and boots from it.
# Cloud-init config is attached as a separate small "seed" drive (IDE2).

resource "proxmox_virtual_environment_vm" "k3s_node" {
  # VM metadata
  name        = var.vm_name
  description = var.vm_description
  node_name   = var.proxmox_node
  vm_id       = var.vm_id

  # Tags shown in the Proxmox UI (useful for filtering VMs)
  tags = var.vm_tags

  # Start the VM automatically when Proxmox boots (after a power outage, etc.)
  on_boot = true

  # Boot order: boot from the virtio disk (our cloud image disk)
  # "order=virtio0" means: first boot device is virtio disk 0
  boot_order = ["virtio0"]

  # ==========================================================================
  # CPU configuration
  # ==========================================================================
  cpu {
    # Number of vCPU cores
    cores = var.vm_cores

    # CPU type "host" passes through the host CPU model to the VM.
    # This gives the best performance and enables all CPU features the host has.
    # Alternative: "kvm64" for maximum compatibility (but lower performance).
    # For K3s, "host" is recommended.
    type = "host"
  }

  # ==========================================================================
  # Memory configuration
  # ==========================================================================
  memory {
    # Amount of RAM in MB (12288 = 12 GB)
    dedicated = var.vm_memory_mb

    # Disable memory ballooning — K3s needs stable, predictable RAM allocation.
    # Ballooning allows the hypervisor to reclaim unused VM memory dynamically,
    # but this can cause K3s components to OOM when the host reclaims memory.
    # floating = 0  # Not needed when dedicated is set (ballooning off by default)
  }

  # ==========================================================================
  # QEMU Guest Agent
  # ==========================================================================
  # The guest agent is a daemon running inside the VM that lets Proxmox:
  #   - Display the VM's IP address in the Proxmox UI
  #   - Send graceful shutdown/reboot signals
  #   - Freeze the filesystem for consistent snapshots
  #   - Run guest commands from the Proxmox host
  # We install qemu-guest-agent via cloud-init above.
  agent {
    enabled = true
    # Wait for the guest agent to respond before Terraform considers the VM ready
    # This ensures the VM is fully booted (not just powered on) before proceeding
    timeout = "15m"
  }

  # ==========================================================================
  # Primary disk — imported from the cloud image
  # ==========================================================================
  disk {
    # VirtIO Block device — best performance for Linux guests
    # VirtIO is a paravirtualized interface; much faster than emulated SCSI/IDE
    interface = "virtio0"

    # Reference the downloaded cloud image as the disk source
    # Proxmox will import the image and resize it to vm_disk_size_gb
    file_id = proxmox_virtual_environment_download_file.ubuntu_cloud_image.id

    # Explicitly set the file format — "raw" works with LVM-thin and directory storage
    # This prevents format detection issues during the import step
    file_format = "raw"

    # Storage pool where this disk is created
    datastore_id = var.vm_storage

    # Disk size in GB — the cloud image (~2GB) gets expanded to this size
    size = var.vm_disk_size_gb

    # discard: send TRIM/DISCARD commands to the underlying storage
    # Allows the host SSD to reclaim freed blocks inside the VM
    # Only effective if the storage supports discard (LVM-thin, ZFS, etc.)
    discard = "on"
  }

  # ==========================================================================
  # Cloud-init "seed" drive
  # ==========================================================================
  # Cloud-init reads its configuration from a special ISO attached as a second
  # drive (traditionally on IDE2 or SCSI). Proxmox creates this automatically
  # when we define the initialization block.
  initialization {
    # Storage for the auto-generated cloud-init drive
    # Must support 'images' content type — local-lvm works, plain 'local' does not
    datastore_id = var.vm_storage

    # Network configuration applied by cloud-init
    # This sets the VM's static IP at the OS level via netplan
    ip_config {
      ipv4 {
        # Format: "IP/PREFIX" — e.g. "192.168.0.100/24"
        address = "${var.vm_ip}/${var.vm_netmask}"
        gateway = var.vm_gateway
      }
    }

    # DNS configuration
    dns {
      servers = var.vm_dns_servers
      domain  = "homelab.local"
    }

    # Point to our custom user-data file (created as a snippet above)
    # This overrides the built-in user_account block with our richer config
    user_data_file_id = proxmox_virtual_environment_file.cloud_init_user_data.id
  }

  # ==========================================================================
  # Network interface
  # ==========================================================================
  network_device {
    # Use the bridged network for LAN access
    bridge = var.vm_bridge

    # VirtIO NIC — paravirtualized, best performance for Linux guests
    model = "virtio"

    # Don't restrict traffic by MAC address filtering
    firewall = false
  }

  # ==========================================================================
  # Operating system hint
  # ==========================================================================
  # Tells Proxmox the guest OS type for display purposes and some defaults
  # "l26" = Linux 2.6+ kernel (use for any modern Linux including Ubuntu 24.04)
  operating_system {
    type = "l26"
  }

  # ==========================================================================
  # Startup/shutdown ordering
  # ==========================================================================
  # Controls VM startup order when Proxmox boots
  # Higher order numbers start later; useful when you have multiple VMs
  startup {
    order      = "3"    # Start after storage/networking VMs (if any)
    up_delay   = "30"   # Wait 30s after starting before starting next VMs
    down_delay = "30"   # Wait 30s during ordered shutdown
  }

  # ==========================================================================
  # Lifecycle
  # ==========================================================================
  lifecycle {
    # Don't destroy and recreate the VM just because the cloud image changed
    # (e.g. if Ubuntu releases an updated cloud image with a different checksum)
    # The VM disk was already imported from the image — it doesn't change after creation
    ignore_changes = [
      disk[0].file_id,
    ]
  }
}
