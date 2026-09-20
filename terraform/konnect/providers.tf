# Authentication is supplied at runtime through KONNECT_TOKEN (PAT) or
# KONNECT_SPAT (system account access token). Never commit either value.
provider "konnect" {
  server_url = var.konnect_server_url
}
