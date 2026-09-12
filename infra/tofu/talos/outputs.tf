output "talosconfig" {
  description = "The generated client talosconfig"
  value       = data.talos_client_configuration.this.talos_config
  sensitive   = true
}

output "schematic_id" {
  description = "The computed Talos Image Factory schematic ID"
  value       = local.schematic_id
}

output "installer_image" {
  description = "The full installer image URL with schematic ID and Talos version"
  value       = local.installer_image
}

output "controlplane_nodes" {
  description = "Map of controlplane node IPs"
  value       = { for k, v in var.nodes : k => v.ip if v.role == "controlplane" }
}

output "worker_nodes" {
  description = "Map of worker node IPs"
  value       = { for k, v in var.nodes : k => v.ip if v.role == "worker" }
}

output "kubeconfig" {
  description = "The generated admin kubeconfig"
  value       = talos_cluster_kubeconfig.this.kubeconfig_raw
  sensitive   = true
}

output "kubernetes_client_configuration" {
  description = "Kubernetes client auth credentials"
  value       = talos_cluster_kubeconfig.this.kubernetes_client_configuration
  sensitive   = true
}
