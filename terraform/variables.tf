variable "kong_gateway_login_redirect_uri" {
  description = "Kongのopenid-connectプラグイン（Chat UI/エージェント アクセス用Route）が認可コードフローで使うリダイレクトURI。decKのKong route設定と一致させること。"
  type        = string
  default     = "http://localhost:8000/login/callback"
}

variable "kong_gateway_post_logout_redirect_uri" {
  description = "ログアウト後にEntra IDからリダイレクトされるURI（Kongのopenid-connect logout_uri）。decKのKong route設定と一致させること。"
  type        = string
  default     = "http://localhost:8000/logout/callback"
}

# design-brief 2節「Entra ID・権限モデル」で確定済みの3ユーザー構成。
variable "test_users" {
  description = "検証用Entra IDユーザー定義"
  type = map(object({
    display_name     = string
    mail_nickname    = string
    ai_agent_access  = bool
    customer_inquiry = bool
    customer_details = bool
  }))
  default = {
    inquiry_only = {
      display_name     = "Demo User - Inquiry Only"
      mail_nickname    = "demo-inquiry-only"
      ai_agent_access  = true
      customer_inquiry = true
      customer_details = false
    }
    both_apis = {
      display_name     = "Demo User - Inquiry and Details"
      mail_nickname    = "demo-both-apis"
      ai_agent_access  = true
      customer_inquiry = true
      customer_details = true
    }
    no_agent_access = {
      display_name     = "Demo User - No Agent Access"
      mail_nickname    = "demo-no-agent-access"
      ai_agent_access  = false
      customer_inquiry = false
      customer_details = false
    }
  }
}
