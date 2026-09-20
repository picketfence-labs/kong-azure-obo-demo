# Authentication is supplied at runtime through KONNECT_TOKEN (PAT) or
# KONNECT_SPAT (system account access token). Never commit either value.
provider "konnect" {
  server_url = var.konnect_server_url
}

# The stable provider does not expose Konnect Analytics dashboards yet.
# Keep this beta provider scoped to konnect_dashboard resources (ADR-0008).
provider "konnect-beta" {
  server_url = var.konnect_server_url
}
