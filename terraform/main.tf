# 認証の疎通確認用（read-only data source のみ、リソース作成は行わない）。
# `terraform plan` を実行し、テナント/サブスクリプションが意図した対象になっているか確認する。

data "azuread_client_config" "current" {}

data "azurerm_client_config" "current" {}

output "auth_check" {
  description = "Terraformが現在どのEntra IDテナント/Azureサブスクリプションに対して認証されているかの確認用"
  value = {
    entra_tenant_id       = data.azuread_client_config.current.tenant_id
    entra_object_id       = data.azuread_client_config.current.object_id
    azure_subscription_id = data.azurerm_client_config.current.subscription_id
  }
}
