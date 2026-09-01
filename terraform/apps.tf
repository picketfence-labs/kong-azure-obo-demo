# design-brief 3節「Entra IDアプリ構成」参照。
#
# ミドル層App: Kongがclient_id/client_secretとして保持するApp。
# Chat UI/エージェント アクセス用Route（ログイン、OBOなし）とMCPエンドポイント用Route（OBO）の両方でKongが使う。
# 「AIエージェント」の実体はこのApp。
resource "azuread_application" "middle_tier" {
  display_name     = "kong-obo-demo-middle-tier"
  sign_in_audience = "AzureADMyOrg"

  web {
    redirect_uris = [
      var.kong_gateway_login_redirect_uri,
      var.kong_gateway_post_logout_redirect_uri,
    ]
    logout_url = var.kong_gateway_post_logout_redirect_uri
  }

  # Kongが要求するscope（api://<自身のclient_id>/access_as_user）の受け皿。
  # requested_access_token_version=2でないとgroups overage判定やaud表記がv1形式になり
  # design-briefが前提とするEntra ID OBOフローの挙動と食い違う。
  api {
    requested_access_token_version = 2

    oauth2_permission_scope {
      id                         = local.middle_tier_scope_id
      value                      = "access_as_user"
      type                       = "User"
      enabled                    = true
      admin_consent_description  = "Kong GatewayがAIエージェントとしてサインインしたユーザーに代わってアクセスすることを許可する"
      admin_consent_display_name = "AIエージェントとしてアクセス"
      user_consent_description   = "Kong GatewayがAIエージェントとしてあなたに代わってアクセスすることを許可します"
      user_consent_display_name  = "AIエージェントとしてアクセス"
    }
  }

  # ダウンストリームAPI Appのスコープへの要求（OBO交換の前提となるAPI permission）。
  required_resource_access {
    resource_app_id = azuread_application.downstream_api.client_id

    resource_access {
      id   = local.downstream_api_scope_id
      type = "Scope"
    }
  }
}

# Application ID URI（api://<client_id>）は自身のclient_id確定後にしか設定できないため別リソースにする
# （azuread providerのapplication_identifier_uriは自己参照循環を避けるための専用リソース）。
resource "azuread_application_identifier_uri" "middle_tier" {
  application_id = azuread_application.middle_tier.id
  identifier_uri = "api://${azuread_application.middle_tier.client_id}"
}

resource "azuread_service_principal" "middle_tier" {
  client_id = azuread_application.middle_tier.client_id

  # Entra ID Enterprise Applicationの「割り当てが必要」設定そのもの。
  # 「AIエージェント」用Security Groupの割り当てが無いユーザーは、認可コード発行段階でEntra ID自体が拒否する
  # （design-brief 3節）。
  app_role_assignment_required = true
}

resource "azuread_application_password" "middle_tier" {
  application_id = azuread_application.middle_tier.id
  display_name   = "kong-openid-connect-client-secret"
  # end_date_relative は非推奨（timestamp()を使うと毎planで差分が出るため、固定日付にする。1年後を目安に設定）
  end_date = "2027-09-01T00:00:00Z"
}

# ダウンストリームAPI App（Customer Inquiry / Customer Details、1つにまとめる）。
# OBO交換後のトークンのaudience。
resource "azuread_application" "downstream_api" {
  display_name     = "kong-obo-demo-downstream-api"
  sign_in_audience = "AzureADMyOrg"

  # ACL評価対象のgroupsクレームをOBO交換後トークンに含めるために必須
  # （design-brief 5節「外部依存の前提条件確認」）。
  group_membership_claims = ["SecurityGroup"]

  api {
    requested_access_token_version = 2

    oauth2_permission_scope {
      id                         = local.downstream_api_scope_id
      value                      = "access_as_user"
      type                       = "User"
      enabled                    = true
      admin_consent_description  = "Kong GatewayがOBO交換により、サインインしたユーザーに代わって顧客情報APIへアクセスすることを許可する"
      admin_consent_display_name = "顧客情報APIへアクセス"
      user_consent_description   = "Kong Gatewayがあなたに代わって顧客情報APIへアクセスすることを許可します"
      user_consent_display_name  = "顧客情報APIへアクセス"
    }
  }
}

resource "azuread_application_identifier_uri" "downstream_api" {
  application_id = azuread_application.downstream_api.id
  identifier_uri = "api://${azuread_application.downstream_api.client_id}"
}

resource "azuread_service_principal" "downstream_api" {
  client_id = azuread_application.downstream_api.client_id

  # Tool実行可否はai-mcp-proxyのACL（groupsクレーム評価）で判定する設計のため、
  # サインイン割り当て自体は必須にしない（design-brief 3節）。
  app_role_assignment_required = false
}

# 「管理者の同意を与える」に相当する操作。ミドル層AppがダウンストリームAPI Appのスコープを
# ユーザーの同意プロンプト無しでOBO交換に使えるようにする（デモ運用の簡略化のため事前に付与）。
resource "azuread_service_principal_delegated_permission_grant" "middle_tier_to_downstream_api" {
  service_principal_object_id          = azuread_service_principal.middle_tier.object_id
  resource_service_principal_object_id = azuread_service_principal.downstream_api.object_id
  claim_values                         = ["access_as_user"]
}
