variable "konnect_server_url" {
  description = "Konnect API endpoint for the target geo."
  type        = string
  default     = "https://us.api.konghq.com"
}

variable "control_plane_name" {
  description = "Name of the self-managed Gateway control plane."
  type        = string
  default     = "azure-obo-demo"
}

variable "control_plane_description" {
  description = "Description shown in Konnect Gateway Manager."
  type        = string
  default     = "Entra ID OBO and AI MCP Proxy demo"
}

variable "data_plane_certificate_validity_hours" {
  description = "Lifetime of the locally generated Data Plane client certificate."
  type        = number
  default     = 8760

  validation {
    condition     = var.data_plane_certificate_validity_hours >= 24
    error_message = "The Data Plane certificate must be valid for at least 24 hours."
  }
}
