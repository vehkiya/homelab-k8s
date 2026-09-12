data "talos_machine_configuration" "config" {
  for_each = var.nodes

  cluster_name       = var.cluster_name
  cluster_endpoint   = var.cluster_endpoint
  machine_type       = each.value.role
  machine_secrets    = local.machine_secrets
  talos_version      = "v1.7"
  kubernetes_version = var.kubernetes_version

  config_patches = [
    templatefile("${path.module}/templates/common.yaml.tftpl", {
      kubernetes_version = var.kubernetes_version
    }),
    templatefile("${path.module}/templates/${each.value.role}.yaml.tftpl", {
      hostname           = each.key
      node_ip            = each.value.ip
      ipv6               = each.value.ipv6
      vlan2_ip           = each.value.vlan2_ip
      driver             = each.value.nic_driver
      macs               = each.value.mac_addresses
      install_disk       = each.value.install_disk
      installer_image    = local.installer_image
      cluster_vip        = var.cluster_vip
      kubernetes_version = var.kubernetes_version
    })
  ]
}

data "talos_client_configuration" "this" {
  cluster_name         = var.cluster_name
  client_configuration = local.talos_client_config
  nodes                = [for k, v in var.nodes : v.ip]
  endpoints            = [var.cluster_vip]
}

locals {
  custom_config_documents = <<-EOT
---
apiVersion: v1alpha1
kind: CRICustomizationConfig
name: 20-customization
content: |
  [plugins."io.containerd.cri.v1.images"]
    discard_unpacked_layers = false

  # Set cdi dirs to /var/ because default locations are not writeable in talos
  [plugins."io.containerd.cri.v1.runtime"]
    cdi_spec_dirs = ["/var/cdi/static", "/var/cdi/dynamic", "/var/run/cdi"]

  [plugins."io.containerd.cri.v1.runtime".containerd]
            default_runtime_name = "crun"
---
apiVersion: v1alpha1
kind: EtcFileConfig
name: nfsmount.conf
mode: 0644
contents: |
  [ NFSMount_Global_Options ]
  nfsvers=4.1
  hard=True
  nconnect=16
  nodiratime=True
  noatime=True
EOT

  rendered_machine_configurations = {
    for k, v in var.nodes : k => "${data.talos_machine_configuration.config[k].machine_configuration}\n${local.custom_config_documents}"
  }
}

resource "talos_machine_configuration_apply" "node" {
  for_each = var.nodes

  node                        = each.value.ip
  client_configuration        = local.talos_client_config
  machine_configuration_input = local.rendered_machine_configurations[each.key]
  apply_mode                  = "no_reboot"
}
