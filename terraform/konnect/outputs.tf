output "control_plane_id" {
  description = "Konnect Gateway control plane ID."
  value       = konnect_gateway_control_plane.azure_obo_demo.id
}

output "control_plane_endpoint" {
  description = "Full Konnect control plane endpoint."
  value       = konnect_gateway_control_plane.azure_obo_demo.config.control_plane_endpoint
}

output "telemetry_endpoint" {
  description = "Full Konnect telemetry endpoint."
  value       = konnect_gateway_control_plane.azure_obo_demo.config.telemetry_endpoint
}

output "control_plane_host" {
  description = "Control plane hostname for KONNECT_CONTROL_PLANE_HOST."
  value       = local.control_plane_host
}

output "telemetry_host" {
  description = "Telemetry hostname for KONNECT_TELEMETRY_HOST."
  value       = local.telemetry_host
}

output "data_plane_certificate_path" {
  description = "Local path to the generated Data Plane certificate."
  value       = local_sensitive_file.data_plane_certificate.filename
}

output "data_plane_private_key_path" {
  description = "Local path to the generated Data Plane private key."
  value       = local_sensitive_file.data_plane_private_key.filename
}

output "docker_compose_env_path" {
  description = "Generated env fragment to pass after .env with Docker Compose."
  value       = local_sensitive_file.docker_compose_env.filename
}
