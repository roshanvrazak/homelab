# =============================================================================
# outputs.tf — Terraform Output Values
# =============================================================================
#
# Outputs are values that Terraform prints after a successful apply.
# They're useful for:
#   - Getting the VM's assigned IP address
#   - Getting the SSH connection command
#   - Chaining Terraform modules (one module's output = another's input)
#
# View outputs at any time with: terraform output
# View a specific output:        terraform output vm_ip
# Output as JSON:                terraform output -json
# =============================================================================

output "vm_id" {
  description = "Proxmox VM ID assigned to the K3s node."
  value       = proxmox_virtual_environment_vm.k3s_node.vm_id
}

output "vm_name" {
  description = "Hostname of the K3s VM."
  value       = proxmox_virtual_environment_vm.k3s_node.name
}

output "vm_ip" {
  description = "Static IP address assigned to the K3s VM via cloud-init."
  value       = var.vm_ip
}

output "vm_ipv4_addresses" {
  description = <<-EOT
    IP addresses reported by the QEMU guest agent after the VM is booted.
    This is populated once the guest agent starts (may take a few minutes).
    More reliable than the static IP variable — shows what the OS actually got.
  EOT
  value = try(
    proxmox_virtual_environment_vm.k3s_node.ipv4_addresses,
    ["Guest agent not yet running — check Proxmox UI"]
  )
}

output "ssh_command" {
  description = "SSH command to connect to the K3s VM."
  value       = "ssh ${var.vm_user}@${var.vm_ip}"
}

output "bootstrap_command" {
  description = "Command to run on the VM after SSH to install K3s (run bootstrap.sh from your cloned repo)."
  value       = "ssh ${var.vm_user}@${var.vm_ip} 'bash -s' < scripts/bootstrap.sh"
}

output "proxmox_vm_url" {
  description = "Direct URL to the VM in the Proxmox web UI."
  value       = "${var.proxmox_endpoint}/#v1:0:=qemu%2F${var.vm_id}"
}

output "next_steps" {
  description = "What to do after 'terraform apply' completes."
  value       = <<-EOT

    ============================================================
     VM provisioned successfully!
    ============================================================

    1. Wait ~2 minutes for cloud-init to complete on first boot.
       Check progress: ssh ${var.vm_user}@${var.vm_ip} 'cloud-init status --wait'

    2. SSH into the VM:
       ssh ${var.vm_user}@${var.vm_ip}

    3. Clone the homelab repo on the VM:
       git clone https://github.com/roshanvrazak/homelab.git
       cd homelab

    4. Run the bootstrap script (installs K3s + Helm):
       bash scripts/bootstrap.sh

    5. Install ArgoCD (deploys everything else via GitOps):
       bash scripts/install-argocd.sh https://github.com/roshanvrazak/homelab.git

    6. Add homelab hostnames to your local /etc/hosts:
       ${var.vm_ip}  argocd.homelab.local grafana.homelab.local
       ${var.vm_ip}  gitea.homelab.local homepage.homelab.local ntfy.homelab.local

    Or run: make bootstrap / make argocd REPO=... from the VM.
    ============================================================
  EOT
}
