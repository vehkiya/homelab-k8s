data "http" "talos_schematic" {
  count = var.schematic_id == "" ? 1 : 0

  url    = "https://factory.talos.dev/schematics"
  method = "POST"
  request_headers = {
    "Content-Type" = "application/yaml"
  }
  request_body = file("${path.module}/image-factory-parameters.yaml")
}

locals {
  schematic_id    = var.schematic_id != "" ? var.schematic_id : jsondecode(data.http.talos_schematic[0].response_body).id
  installer_image = "factory.talos.dev/metal-installer/${local.schematic_id}:${var.talos_version}"
}
