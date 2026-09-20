locals {
  secrets_directory  = abspath("${path.root}/../../secrets/konnect")
  control_plane_host = split(":", trimprefix(konnect_gateway_control_plane.azure_obo_demo.config.control_plane_endpoint, "https://"))[0]
  telemetry_host     = split(":", trimprefix(konnect_gateway_control_plane.azure_obo_demo.config.telemetry_endpoint, "https://"))[0]
}

resource "konnect_gateway_control_plane" "azure_obo_demo" {
  name          = var.control_plane_name
  description   = var.control_plane_description
  auth_type     = "pinned_client_certs"
  cloud_gateway = false
  cluster_type  = "CLUSTER_TYPE_CONTROL_PLANE"

  labels = {
    owner   = "picketfence-labs"
    purpose = "azure-obo-demo"
  }
}

resource "tls_private_key" "data_plane" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_self_signed_cert" "data_plane" {
  private_key_pem       = tls_private_key.data_plane.private_key_pem
  validity_period_hours = var.data_plane_certificate_validity_hours

  subject {
    common_name  = "${var.control_plane_name}-data-plane"
    organization = "picketfence-labs"
  }

  allowed_uses = [
    "digital_signature",
    "key_encipherment",
    "client_auth",
  ]
}

resource "konnect_gateway_data_plane_client_certificate" "docker_compose" {
  control_plane_id = konnect_gateway_control_plane.azure_obo_demo.id
  cert             = tls_self_signed_cert.data_plane.cert_pem
  title            = "docker-compose"
}

resource "terraform_data" "secrets_directory" {
  provisioner "local-exec" {
    command = "mkdir -p '${local.secrets_directory}'"
  }
}

resource "local_sensitive_file" "data_plane_certificate" {
  content         = tls_self_signed_cert.data_plane.cert_pem
  filename        = "${local.secrets_directory}/tls.crt"
  file_permission = "0600"

  depends_on = [terraform_data.secrets_directory]
}

resource "local_sensitive_file" "data_plane_private_key" {
  content         = tls_private_key.data_plane.private_key_pem
  filename        = "${local.secrets_directory}/tls.key"
  file_permission = "0600"

  depends_on = [terraform_data.secrets_directory]
}

resource "local_sensitive_file" "docker_compose_env" {
  content = <<-EOT
    KONNECT_CONTROL_PLANE_HOST=${local.control_plane_host}
    KONNECT_TELEMETRY_HOST=${local.telemetry_host}
    KONNECT_CLUSTER_CERT_PATH=./secrets/konnect/tls.crt
    KONNECT_CLUSTER_CERT_KEY_PATH=./secrets/konnect/tls.key
  EOT

  filename        = "${local.secrets_directory}/compose.env"
  file_permission = "0600"

  depends_on = [terraform_data.secrets_directory]
}
