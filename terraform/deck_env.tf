locals {
  deck_secrets_directory = abspath("${path.root}/../secrets")

  deck_environment = {
    DECK_AZURE_OPENAI_API_KEY                 = azurerm_cognitive_account.openai.primary_access_key
    DECK_AZURE_OPENAI_DEPLOYMENT_NAME         = azurerm_cognitive_deployment.gpt_5_mini.name
    DECK_AZURE_OPENAI_INSTANCE_NAME           = azurerm_cognitive_account.openai.name
    DECK_DOWNSTREAM_API_APPLICATION_ID_URI    = azuread_application_identifier_uri.downstream_api.identifier_uri
    DECK_ENTRA_ISSUER                         = "https://login.microsoftonline.com/${data.azuread_client_config.current.tenant_id}/v2.0"
    DECK_GROUP_API_CUSTOMER_DETAILS_OBJECT_ID = azuread_group.api_customer_details.object_id
    DECK_GROUP_API_CUSTOMER_INQUIRY_OBJECT_ID = azuread_group.api_customer_inquiry.object_id
    DECK_LOGIN_OIDC_CACHE_TOKENS_SALT         = random_password.login_oidc_cache_tokens_salt.result
    DECK_MCP_OIDC_CACHE_TOKENS_SALT           = random_password.mcp_oidc_cache_tokens_salt.result
    DECK_MIDDLE_TIER_CLIENT_ID                = azuread_application.middle_tier.client_id
    DECK_MIDDLE_TIER_CLIENT_SECRET            = azuread_application_password.middle_tier.value
    DECK_SESSION_SECRET                       = random_password.deck_session_secret.result
  }

  # Single-quote each value so the generated file can be sourced safely even
  # when a provider-generated secret contains shell metacharacters.
  deck_environment_file = join("\n", [
    for name, value in local.deck_environment :
    "export ${name}='${replace(value, "'", "'\"'\"'")}'"
  ])
}

resource "random_password" "deck_session_secret" {
  length  = 64
  special = false
}

resource "random_password" "login_oidc_cache_tokens_salt" {
  length  = 32
  special = false
}

resource "random_password" "mcp_oidc_cache_tokens_salt" {
  length  = 32
  special = false
}

resource "terraform_data" "deck_secrets_directory" {
  provisioner "local-exec" {
    command = "mkdir -p '${local.deck_secrets_directory}'"
  }
}

resource "local_sensitive_file" "deck_environment" {
  content         = "${local.deck_environment_file}\n"
  filename        = "${local.deck_secrets_directory}/deck.env"
  file_permission = "0600"

  depends_on = [terraform_data.deck_secrets_directory]
}
