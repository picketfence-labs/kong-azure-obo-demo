output "auth_check" {
  description = "Terraformが現在どのEntra IDテナント/Azureサブスクリプションに対して認証されているかの確認用"
  value = {
    entra_tenant_id       = data.azuread_client_config.current.tenant_id
    entra_object_id       = data.azuread_client_config.current.object_id
    azure_subscription_id = data.azurerm_client_config.current.subscription_id
  }
}

output "entra_tenant_id" {
  description = "Kong openid-connectプラグインのissuer設定に使うテナントID"
  value       = data.azuread_client_config.current.tenant_id
}

output "middle_tier_client_id" {
  description = "Kong openid-connectプラグインのclient_id（ログイン用Route・MCP用Route共通）"
  value       = azuread_application.middle_tier.client_id
}

output "middle_tier_client_secret" {
  description = "Kong openid-connectプラグインのclient_secret"
  value       = azuread_application_password.middle_tier.value
  sensitive   = true
}

output "middle_tier_application_id_uri" {
  description = "ログイン時にKongが要求するscope（<この値>/access_as_user）"
  value       = azuread_application_identifier_uri.middle_tier.identifier_uri
}

output "downstream_api_application_id_uri" {
  description = "OBO交換時にKongが要求するscope（<この値>/.default）。design-brief: audienceはscopeで指定する"
  value       = azuread_application_identifier_uri.downstream_api.identifier_uri
}

output "group_ai_agent_object_id" {
  description = "「AIエージェント」用Security GroupのObject ID"
  value       = azuread_group.ai_agent.object_id
}

output "group_api_customer_inquiry_object_id" {
  description = "Customer Inquiry Tool用Security GroupのObject ID（decKのai-mcp-proxy ACL allowリストに使う）"
  value       = azuread_group.api_customer_inquiry.object_id
}

output "group_api_customer_details_object_id" {
  description = "Customer Details Tool用Security GroupのObject ID（decKのai-mcp-proxy ACL allowリストに使う）"
  value       = azuread_group.api_customer_details.object_id
}

output "test_user_credentials" {
  description = "検証用ユーザーのサインイン情報（ブラウザでのログイン確認用）"
  value = {
    for key, user in azuread_user.test_user : key => {
      user_principal_name = user.user_principal_name
      password            = random_password.test_user[key].result
    }
  }
  sensitive = true
}
