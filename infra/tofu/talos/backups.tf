# Hook A: Automatic Offline Machineconfig Rendering
resource "local_sensitive_file" "machineconfigs" {
  for_each = var.nodes

  filename        = "${path.module}/_output/machineconfigs/${each.key}.yaml"
  content         = data.talos_machine_configuration.config[each.key].machine_configuration
  file_permission = "0600"
}

# Hook B: Automatic talosconfig Generation
resource "local_sensitive_file" "talosconfig" {
  filename        = "${path.module}/_output/talosconfig"
  content         = data.talos_client_configuration.this.talos_config
  file_permission = "0600"
}

# Hook C: Cluster Kubeconfig Retrieval and Offline Export
resource "talos_cluster_kubeconfig" "this" {
  client_configuration = local.talos_client_config
  node                 = var.nodes["lab-1"].ip
}

resource "local_sensitive_file" "kubeconfig" {
  filename        = "${path.module}/_output/kubeconfig"
  content         = talos_cluster_kubeconfig.this.kubeconfig_raw
  file_permission = "0600"
}
