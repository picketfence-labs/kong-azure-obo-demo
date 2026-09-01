# design-brief 2節「Entra ID・権限モデル」参照。
# 「AIエージェント」用と「API」用でSecurity Groupを別々に定義する。

resource "azuread_group" "ai_agent" {
  display_name     = "kong-obo-demo-ai-agent"
  security_enabled = true
  description      = "Chat UI/エージェントへのログインを許可されたユーザー（ミドル層AppのEnterprise Application割り当て用）"
}

resource "azuread_group" "api_customer_inquiry" {
  display_name     = "kong-obo-demo-api-customer-inquiry"
  security_enabled = true
  description      = "Customer Inquiry ToolをMCP経由で実行できるユーザー（ai-mcp-proxy ACL評価対象、groupsクレームのobject idで照合）"
}

resource "azuread_group" "api_customer_details" {
  display_name     = "kong-obo-demo-api-customer-details"
  security_enabled = true
  description      = "Customer Details ToolをMCP経由で実行できるユーザー（ai-mcp-proxy ACL評価対象、groupsクレームのobject idで照合）"
}

# グループ単位でEnterprise Applicationへ割り当てる標準的な方法（カスタムApp Roleを定義しない場合、
# app_role_id は全ゼロの "Default Access" を使う）。
resource "azuread_app_role_assignment" "ai_agent_to_middle_tier" {
  app_role_id         = "00000000-0000-0000-0000-000000000000"
  principal_object_id = azuread_group.ai_agent.object_id
  resource_object_id  = azuread_service_principal.middle_tier.object_id
}
