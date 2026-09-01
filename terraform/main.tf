# 認証の疎通確認用（read-only data source のみ）。
# `terraform plan` を実行し、テナント/サブスクリプションが意図した対象になっているか確認する。

data "azuread_client_config" "current" {}

data "azurerm_client_config" "current" {}

# テストユーザーのuser_principal_nameの組み立てに使うテナント既定ドメイン（*.onmicrosoft.com）
data "azuread_domains" "default" {
  only_default = true
}

locals {
  default_domain = data.azuread_domains.default.domains[0].domain_name

  # oauth2_permission_scope の id は「Application上で一意なUUID」であればよく値そのものに意味はない。
  # 一度払い出した後にterraform外で変更するとスコープが再作成されるため、固定値としてここに置く。
  middle_tier_scope_id    = "8f6a3b1e-6b2e-4b0a-9b6a-2e6a5b1c8f11"
  downstream_api_scope_id = "3d2c9a44-7e3d-4b8a-9c2e-1f5a6d3b7c22"
}
