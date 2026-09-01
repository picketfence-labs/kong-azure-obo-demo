# design-brief 2節: 最低3人。全員Entra IDアカウントあり。
# パスワードは生成のみ（terraform outputのsensitive値として取得、コード・状態ファイル以外には残さない）。

resource "random_password" "test_user" {
  for_each = var.test_users

  length      = 24
  min_upper   = 2
  min_lower   = 2
  min_numeric = 2
  min_special = 2
  # Entra IDのパスワード複雑性要件を満たしつつ、シェルやURLで扱う際に問題を起こしにくい記号のみに絞る
  override_special = "!@#$%^&*()-_=+"
}

resource "azuread_user" "test_user" {
  for_each = var.test_users

  user_principal_name = "${each.value.mail_nickname}@${local.default_domain}"
  display_name        = each.value.display_name
  mail_nickname       = each.value.mail_nickname
  password            = random_password.test_user[each.key].result
  # デモ用の使い捨てアカウントのため、初回サインイン時のパスワード変更強制はオフにする
  force_password_change = false
}

resource "azuread_group_member" "ai_agent" {
  for_each = { for key, user in var.test_users : key => user if user.ai_agent_access }

  group_object_id  = azuread_group.ai_agent.object_id
  member_object_id = azuread_user.test_user[each.key].object_id
}

resource "azuread_group_member" "api_customer_inquiry" {
  for_each = { for key, user in var.test_users : key => user if user.customer_inquiry }

  group_object_id  = azuread_group.api_customer_inquiry.object_id
  member_object_id = azuread_user.test_user[each.key].object_id
}

resource "azuread_group_member" "api_customer_details" {
  for_each = { for key, user in var.test_users : key => user if user.customer_details }

  group_object_id  = azuread_group.api_customer_details.object_id
  member_object_id = azuread_user.test_user[each.key].object_id
}
