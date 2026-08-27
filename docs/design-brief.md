# 基本設計（Dev Design Brief）

Picketfence Labs Obsidian Vaultの「Kong Gateway 3.16 OIDC OBO デモ環境構築」プロジェクトで、利用者とのヒアリングを踏まえて確定した基本設計です（2026-08-27）。

## 1. Projectゴール
Chat AIエージェントからMCP経由でAPIへアクセスするデモにおいて、「エージェントとしてログインする権限」と「個々のAPI(Tool)を実行する権限」を分離し、Kong Gateway 3.16のOpenID ConnectプラグインのOBO（On-Behalf-Of）機能でトークン交換、AI MCP ProxyのACL機能でTool単位の認可を行う一連の流れを実地検証する。

## 2. 要件

### 現在（今回のスコープで確実に必要なもの）

**全体フロー**:
1. ブラウザベースの簡単なChat UI + エージェント。ログイン必須・ログアウト可
2. ブラウザからEntra IDへ認可コードフローでアクセストークン発行（Kongが仲介）
3. ユーザーがプロンプトでバックエンドAPIアクセスを要求
4. MCPエンドポイントへのリクエストをKongが検知 → OIDC OBOでユーザーPrincipal情報を元にMCP(API)用トークンへExchange
5. AI MCP ProxyのACLを評価。許可されればtools/listで利用可能なToolを返却
6. AIエージェントがtools/callでMCP/APIを実行し結果を返却
7. ログイン後、Chat UI上部に自分のトークン情報の一部を表示

**Kongが経路全体をフロントする構成**（重要）: Chat UI→AIエージェントの経路も含め、ブラウザからの通信は全てKong Gatewayを経由する。Kongは最低3系統のRoute/Serviceをフロントする:
1. **Chat UI/エージェントアクセス用Route**: `openid-connect`（OBOなし、認可コードフロー＋ログイン可否判定のみ。「AIエージェント」用Security Groupで判定）
2. **MCPエンドポイント用Route**: `openid-connect`（`token_exchange`でOBO）＋`ai-mcp-proxy`（ACL、「API」用Security Groupで判定）
3. **LLM（Azure OpenAI）アクセス用Route**: `ai-proxy-advanced`

LLMアクセスは`ai-proxy-advanced`プラグイン必須。実LLMはAzure OpenAI。エージェント側には抽象化されたエンドポイントを提供し、Azure OpenAI固有の詳細（エンドポイントURL・APIバージョン・デプロイ名等）を意識しない設計にする。

**デモAPI（2本、同じ顧客データを参照）**:

| API | 検索条件 | 戻り値 |
|---|---|---|
| Customer Inquiry | 氏名（部分一致）/性別/都道府県、AND条件 | 顧客ID/氏名/性別/都道府県 |
| Customer Details | 顧客ID（UUID）による一意取得のみ。顧客IDは推測困難なUUID形式であり、事前にCustomer Inquiryを実行してIDを取得することが前提（Customer Details単体では顧客を検索できない。必ずInquiry→Detailsの順で呼ばれる設計） | 顧客ID/氏名/年齢/性別/マイナンバー/都道府県/住所/電話番号/eメールアドレス等（フル項目） |

顧客データ: 100人分のテストデータを生成。顧客IDはUUID。

**Entra ID・権限モデル**:
- Security Groupを「AIエージェント」用と「API」用で別々に定義
- ログイン（Chat UI利用可否）はAIエージェント側のグループで判定、MCP（Tool実行可否）はAPI側のグループでAI MCP Proxy ACLが判定
- ユーザーは最低3人、全員Entra IDアカウントあり
  - 2人にAIエージェントへのアクセスあり（Chat UIにログイン可能）
  - そのうち1人はCustomer Inquiryのみ権限あり、もう1人はCustomer Inquiry・Customer Details両方に権限あり
  - 残り1人はEntra IDアカウントはあるがAIエージェントへのアクセス無し（ログイン不可の反例）

**技術要素**:
- Kongイメージ: `kong/kong-gateway-dev:pr-21082-ubuntu`（ベータ、OBO機能を含むビルド）
- 必須プラグイン: OpenID Connect（OBO用、Chat UIログイン用の2用途）、AI MCP Proxy（ACLはそのネイティブ機能）、AI Proxy Advanced（LLMアクセスの抽象化）
- Konnect不使用（Gateway単体）
- Entra ID連携部分はTerraformでコード化（対象範囲はEntra ID/Azureのみ。Kong/Konnectは対象外）
- Kong自体の設定管理はdecKの宣言的YAML
- 実LLM: Azure OpenAI（`ai-proxy-advanced`経由）
- Kongのデータストア: Postgres（DB-less不採用。decKでの反復的な宣言的変更を行うため）
- リポジトリ公開設定: Private（マイナンバー等の機微な項目名を模したテストデータを扱うため）

### 将来（今回のスコープ外だが、明示的に認識しておくもの）
- **Tool/APIの追加**: 可能性あり。ただし現時点ではToolは2つのみのため、`ai-mcp-proxy`は自己完結の`conversion-listener`モードで開始する（後述「アーキテクチャ」参照）。将来Tool追加が必要になった時点で`listener`+`conversion-only`の集約パターンへ作り替える
- **他IdPとの組み合わせ**: なし。OBOの性質上IdPはEntra ID限定（Azure ADのOn-Behalf-Ofフロー自体がMicrosoft固有の仕様であり、他IdPへの一般化は設計上想定しない）
- **Konnect管理への移行**: 将来的な可能性あり。今回はGateway単体で構築するが、後からKonnectへ移行しやすいよう、Konnect非対応の設定（Gateway専用のAdmin API直叩き等）は避け、decKで完結する構成に留める
- **CI化**: 今回はスコープ外

## 3. アーキテクチャ

### OIDC OBO機能の実装詳細
`kong/kong-gateway-dev:pr-21082-ubuntu`が含む、Entra ID On-Behalf-Ofフロー対応のベータ機能（`openid-connect`プラグイン）:
- `config.token_exchange.grant_type = "jwt_bearer"` でRFC 7523 JWT Bearerフローを使う（デフォルトは`token_exchange`＝RFC 8693標準のToken Exchange。Entra ID OBOには`jwt_bearer`を使う）
- `config.token_exchange.provider = "microsoft"` にすると、Entra IDのOBOが要求する`requested_token_use=on_behalf_of`パラメータが自動付与される
- 送信されるOAuth2パラメータ: `grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer`、`assertion=<受信した元のBearerトークン>`、`requested_token_use=on_behalf_of`、`scope=<config.scopesまたはtoken_exchange.request.scopes>`
  - `jwt_bearer`グラントでは`audience`パラメータは送信されない。**ダウンストリームAPIの対象（audience）はscopeで指定する**（Entra ID流に`api://<downstream-app-id>/.default`等）
- OBO交換を実行する主体はKong自身（`openid-connect`プラグインの`client_id`/`client_secret`）。この`client_id`は「受信したBearerトークンのaudience」と一致している必要がある
- `config.token_exchange.subject_token_issuers`で信頼する発行者（Entra IDのテナントissuer URL）と、必要ならJWT検証条件を設定する
- `config.token_exchange.map_identities_from`（既定`exchanged_tokens`）で、Consumer/Consumer Group/Principalマッピングに使うクレームを「交換後トークン」由来にするか「交換前の元トークン」由来にするか選べる。AI MCP ProxyのACLは交換後トークンのクレームを見るため既定のままでよい
- **`openid-connect`単体で`ai-mcp-proxy`のACLに接続できる**: このベータビルドでは`openid-connect`プラグイン自身が`kong.ctx.shared.ai_mcp_oauth2 = { access_token_claims = ... }`を書き込むため、`ai-mcp-oauth2`プラグインを別途有効化する必要はない（GA版でこの挙動が維持されるかは要注視）

### Entra IDアプリ構成
少なくとも以下2種のApp Registrationが必要:
1. **ミドル層App**（Kongが`client_id`/`client_secret`として保持するApp。「Chat UI/エージェント アクセス用Route」と「MCPエンドポイント用Route」の両方でKongが使う）: Chat UI（Next.js）自体はOAuthクライアントを持たないため、ログイン用の認可コードフローもOBO交換も、Kongが同じApp Registrationの認証情報で行う。「AIエージェント」の実体はこのApp。Entra ID Enterprise Applicationの「割り当てが必要」設定＋「AIエージェント」用Security Groupの割り当てで、ログイン可否そのものを制御する（Kongは非関与）
2. **ダウンストリームAPI App**（Customer Inquiry / Customer Details、1つにまとめる）: OBO交換後のトークンのaudience。Security Group 2つ（Inquiry用／両方用）をユーザーに割り当て、`groups`クレームとしてトークンに含める

### Kong側のプラグインチェーン（Kongが3種類のRoute/Serviceをフロントする構成）

1. **Chat UI/エージェント アクセス用Route**（ブラウザ→Kong→Next.jsアプリ）
   - `openid-connect`を適用。認可コードフローでログインを扱い、OBO（`token_exchange`）は設定しない
   - ログイン可否判定はEntra ID Enterprise Applicationの「割り当てが必要」設定＋「AIエージェント」用Security Groupの割り当てのみで行う（Kongは非関与）。未割当ユーザーは認可コード発行段階でEntra ID自体が拒否するため、Kong側にACL相当の追加実装は不要
   - ログアウトは`openid-connect`の`logout_methods`/`logout_uri`機能を使う想定
   - Next.js側はAuth.js（NextAuth.js）を使わず、Kongが転送する認証済みユーザー情報（ヘッダー）を信頼するだけの構成にする。Next.jsアプリはOAuthクライアントとしての実装を持たない
2. **MCPエンドポイント用Route**（Next.jsエージェント→Kong→デモAPI、MCP変換込み）
   - `openid-connect`（`token_exchange.grant_type=jwt_bearer`+`provider=microsoft`でOBO）＋`ai-mcp-proxy`（`acl_attribute_type: oauth_access_token`、`access_token_claim_field`で`groups`クレームを指定）
   - `ai-mcp-proxy`の構成は、現時点は自己完結の`conversion-listener`モードでシンプルに構築する。将来Tool追加が必要になった時点で`listener`+`conversion-only`の集約パターンへ作り替える
3. **LLM（Azure OpenAI）アクセス用Route**（Next.jsエージェント→Kong→Azure OpenAI）
   - `ai-proxy-advanced`を適用。KongがAzure OpenAIの認証情報・エンドポイントの詳細を保持し、エージェント側には抽象化されたエンドポイントを提供する
   - 追加認証は掛けない。Docker Composeの内部専用ネットワークでNext.jsアプリ以外からアクセスできないようにすることで保護する

## 4. 技術スタック
- **Kong Gateway**: `kong/kong-gateway-dev:pr-21082-ubuntu`、Docker Compose、Konnect不使用（Gateway単体）
- **Kongのデータストア**: Postgres（DB-less不採用）
- **Kong側の設定管理**: decKの宣言的YAML
- **Entra ID連携のIaC**: Terraform（`azuread` provider）。対象範囲はEntra ID（Azure）のみ
- **Chat UI/エージェント**: Next.js（App Router）+ Vercel AI SDK。Auth.js（NextAuth.js）は不採用
- **LLM**: Azure OpenAI。`ai-proxy-advanced`プラグイン経由でアクセスし、エージェント側には抽象化されたエンドポイントを提供する
- **デモAPI（Customer Inquiry/Details）バックエンド**: TypeScript、ランタイムはBun
- **リポジトリ公開設定**: Private

## 5. 検証方法（テストケース）
- [ ] Entra IDアカウントを持つがAIエージェント用グループに未割当のユーザーがChat UIへログインできないこと（3人目のユーザー）
- [ ] AIエージェント用グループに割当済みの2ユーザーがChat UIへログイン・ログアウトできること
- [ ] Customer Inquiryのみ権限のユーザーが、tools/listでCustomer Inquiryのみ表示され、Customer Detailsは表示されない/呼び出すと拒否されること
- [ ] 両方権限のユーザーが、両方のToolを表示・実行できること
- [ ] Customer Inquiryの検索がAND条件（氏名部分一致・性別・都道府県）で正しく絞り込まれること
- [ ] OBOによるトークン交換が成功し、交換後トークンのgroupsクレームがACL評価に正しく使われること（Entra IDのgroups overage〈グループ数が多いと`groups`クレームが省略される仕様〉が発生しない人数規模であることも確認）
- [ ] Chat UI上部に表示される「自分のトークン情報の一部」が、実際のログインユーザーと一致すること
- [ ] Customer Detailsを顧客IDの推測（総当たり等）だけで直接呼び出せない・実質的にCustomer Inquiryを経由しないとID取得できないこと
- [ ] エージェントがAzure OpenAI固有の設定（エンドポイントURL・APIバージョン・デプロイ名等）を一切持たずにLLM呼び出しができること（`ai-proxy-advanced`による抽象化の確認）

**外部依存の前提条件確認**: Entra IDテナント側でOBO・グループクレーム発行に必要な設定（`groupMembershipClaims`、Appのconfidential client有効化、`requested_access_token_version`等）が事前に有効になっているかを、本格実装前に確認する。

## 6. 成果物
- Docker Composeで起動するKong Gateway 3.16ベータ + Chat UI/エージェント + デモAPI(2本)一式
- Entra IDリソース一式をコード化したTerraform構成
- OBO＋MCP ACLの動作を実演できる状態（上記テストケースが全て確認できること）

## 参照
- [obsidian-vault-labs（Picketfence Labs Obsidian Vault）](https://github.com/picketfence-labs/obsidian-vault-labs) の `03-Resources/Kong AI MCP Proxy - ACL設定ガイド.md`: `ai-mcp-proxy`の4モード、ACL評価ロジック（`default_acl`/`tools[].acl`）、Entra ID groups overageの注意点など
- ローカル参照リポジトリ: `kong-mcp-testbed`（Postgres+decKの実働構成サンプル、OIDC(Auth0)+`ai-mcp-proxy`ネイティブACLの実装例）、`kong-ee`（OBO機能自体の一次情報源。ソースコード参照が必要な場合は`additionalDirectories`でホワイトリスト付与する）
