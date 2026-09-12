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
  effective_dhi_username = var.dhi_username != "" ? var.dhi_username : var.docker_hub_username
  effective_dhi_token    = var.dhi_token != "" ? var.dhi_token : var.docker_hub_token

  effective_docker_hub_username = var.docker_hub_username != "" ? var.docker_hub_username : var.dhi_username
  effective_docker_hub_token    = var.docker_hub_token != "" ? var.docker_hub_token : var.dhi_token

  registry_auths = merge(
    var.extra_registry_auths,
    local.effective_dhi_username != "" && local.effective_dhi_token != "" ? {
      "dhi.io" = {
        username = local.effective_dhi_username
        password = local.effective_dhi_token
      }
    } : {},
    local.effective_docker_hub_username != "" && local.effective_docker_hub_token != "" ? {
      "docker.io" = {
        username = local.effective_docker_hub_username
        password = local.effective_docker_hub_token
      }
    } : {},
    var.ghcr_username != "" && var.ghcr_token != "" ? {
      "ghcr.io" = {
        username = var.ghcr_username
        password = var.ghcr_token
      }
    } : {}
  )

  registry_auth_documents = join("", [
    for host, creds in local.registry_auths : <<-DOC
---
apiVersion: v1alpha1
kind: RegistryAuthConfig
name: ${jsonencode(host)}
username: ${jsonencode(creds.username)}
password: ${jsonencode(creds.password)}
DOC
  ])

  base_custom_config_documents = <<-EOT
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

  custom_config_documents = "${local.base_custom_config_documents}${local.registry_auth_documents}"

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
