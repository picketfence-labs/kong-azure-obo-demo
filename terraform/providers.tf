# 認証は Azure CLI (`az login`) のセッションに委譲する。
# クライアントシークレット等の長期間有効な静的資格情報は使わない（判断根拠: docs/decisions/0001-terraform-azure-auth-method.md）。
#
# 前提:
#   - `az login` 済みであること
#   - `az account show` で対象のテナント/サブスクリプションが選択されていること
#     （複数サブスクリプションがある場合は `az account set --subscription <id>` で切り替える）

provider "azuread" {}

provider "azurerm" {
  features {}
}
