# design-brief 4節「技術スタック」: 実LLMはAzure OpenAI（ai-proxy-advancedプラグイン経由）。
# リージョンはユーザー確認済み（Japan East）。モデルは当初gpt-4o-miniを予定していたが、
# Japan Eastで新規デプロイ不可（lifecycleStatus: Deprecating）だった。次点のgpt-5.4-miniは
# このサブスクリプションでクォータ0（増額はサポートチケット要、即日不可）だったため、
# 既定クォータがあるgpt-5-miniに変更（troubleshooting-log.md参照、いずれもユーザー確認済み）。

resource "azurerm_resource_group" "main" {
  name     = "rg-kong-obo-demo"
  location = "Japan East"
}

resource "azurerm_cognitive_account" "openai" {
  name                = "kong-obo-demo-openai"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  kind                = "OpenAI"
  sku_name            = "S0"

  # モデルデプロイのエンドポイントURLに使われるサブドメイン。api.cognitive.microsoft.comではなく
  # <この値>.openai.azure.com形式のエンドポイントになる（ai-proxy-advancedの設定に必要）。
  custom_subdomain_name = "kong-obo-demo-openai"
}

resource "azurerm_cognitive_deployment" "gpt_5_mini" {
  name                 = "gpt-5-mini"
  cognitive_account_id = azurerm_cognitive_account.openai.id

  model {
    format  = "OpenAI"
    name    = "gpt-5-mini"
    version = "2025-08-07"
  }

  # Japan Eastではリージョン固定のStandard SKUが提供されておらず、GlobalStandardのみ選択可能
  # （az rest .../locations/japaneast/modelsで確認、troubleshooting-log.md参照）。
  sku {
    name     = "GlobalStandard"
    capacity = 10
  }
}
