# =============================================================================
# versions.tf — Terraform and Provider Version Constraints
# =============================================================================
#
# This file pins the versions of Terraform itself and every provider we use.
# Pinning versions is critical because:
#   - Provider APIs change between major versions (breaking changes)
#   - Reproducible infrastructure: same code = same result, months later
#   - "~> 0.66" means ">= 0.66, < 1.0" — allows patch updates, not majors
#
# Provider: bpg/proxmox
#   The most feature-complete and actively maintained Proxmox provider.
#   Supports: VMs, LXC, storage, network, users, ACLs, cloud-init, etc.
#   Docs: https://registry.terraform.io/providers/bpg/proxmox/latest/docs
#   GitHub: https://github.com/bpg/terraform-provider-proxmox
# =============================================================================

terraform {
  # Minimum Terraform CLI version required
  # 1.6+ introduced test framework and minor improvements; widely available
  required_version = ">= 1.5"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.69"
      # ~> 0.69 = any 0.69.x patch release, but not 0.70.0+
      # Check for new releases: https://registry.terraform.io/providers/bpg/proxmox
    }
  }

  # Optional: Remote state backend
  # For a homelab, local state (the default) is fine.
  # If you want state stored remotely (e.g. Terraform Cloud), uncomment:
  #
  # backend "remote" {
  #   organization = "your-org"
  #   workspaces {
  #     name = "homelab"
  #   }
  # }
  #
  # Or use S3-compatible storage (e.g. Gitea with S3 backend, Minio, etc.):
  # backend "s3" {
  #   bucket = "terraform-state"
  #   key    = "homelab/terraform.tfstate"
  #   ...
  # }
}
