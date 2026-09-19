# 基本設計（Dev Design Brief）

2026-08-27に作成したKong Gateway 3.16 OIDC OBOデモの基本設計を、2026-09-20に正式版Kong GatewayとKonnect前提へ更新したものです。

## 1. Projectゴール

既存のOIDC OBO + MCP Tool ACL + Azure OpenAIデモを維持しながら、Kong Gatewayをベータ版から正式版`3.16.0.0`へ切り替え、ローカルDocker ComposeをKonnect管理のself-hosted Data Plane構成へ移行する。あわせて、Konnect Observability Dashboard、MCP Registry、Catalog AI Model登録を再現可能な成果物として追加する。

## 2. 現在要件

### 2.1 維持するデモ機能

1. ブラウザベースのChat UI。ログイン必須、ログアウト可能
2. Kong GatewayのOpenID ConnectプラグインがEntra IDの認可コードフローとsessionを処理
3. MCP RouteでOIDC OBOを実行し、ユーザーのトークンをダウンストリームAPI用トークンへ交換
4. AI MCP Proxyが交換後トークンの`groups` claimでTool ACLを評価
5. Customer Inquiry / Customer Details Toolを権限に応じて公開・実行
6. AI Proxy Advanced経由でAzure OpenAIを呼び出し、Chat UIからprovider固有設定を隠蔽

Kongがフロントする3 Route構成は維持する。

| Route | 主なプラグイン | 役割 |
|---|---|---|
| Chat UI / Agent | `openid-connect` | authorization code + session、ログイン可否 |
| MCP | `openid-connect` + `ai-mcp-proxy` | Entra ID OBO、Tool ACL、REST-to-MCP変換 |
| LLM | `ai-proxy-advanced` | Azure OpenAI認証とmodel endpointの抽象化 |

### 2.2 Gatewayとローカルruntime

- imageを`kong/kong-gateway-dev:pr-21082-ubuntu`から`kong/kong-gateway:3.16.0.0`へ変更する。
- local runtimeはDocker Composeを維持する。
- KongはKonnect Control Planeへ接続するself-hosted Data Planeとして起動する。
- Data Planeは`KONG_ROLE=data_plane`、`KONG_DATABASE=off`、`KONG_KONNECT_MODE=on`を前提とする。
- Control Plane endpoint、telemetry endpoint、mTLS certificate/keyは環境変数またはgitignore済みlocal mountから与える。
- local Postgres、`kong migrations bootstrap`、local Control Plane、host公開のAdmin APIは廃止する。
- `KONG_LICENSE_DATA`、license file、その他local license管理は廃止する。ライセンスはKonnect Control PlaneからData Planeへ連携される前提とする。
- certificate private key、Konnect token、Entra ID client secret、Azure OpenAI credentialはcommitしない。

### 2.3 Gateway設定管理

- `kong/login-route.yaml`、`kong/mcp-route.yaml`、`kong/llm-route.yaml`のdecK宣言的設定を維持する。
- 反映先をlocal Admin APIからKonnect Control Planeへ変更する。
- 変更適用は`deck gateway validate` → `deck gateway diff` → 人間承認後の`deck gateway sync`とする。
- Konnect resource管理のために既存Terraformのscopeを無断で拡張しない。現行TerraformはEntra ID / Azure resourceのみを管理する。

### 2.4 Konnect Observability Dashboard

OBOデモ専用のCustom Dashboardを作成し、definitionまたはexportと再現手順をリポジトリへ保存する。

最低限、次を可視化する。

- login / MCP / LLM Route別のrequest volume、latency、status code
- MCP Routeの2xx / 401 / 403 / 5xx推移
- LLM request数、latency、error、provider/model、token usage（利用可能なdataset範囲）
- Control Plane / Data Plane / Service / Routeでデモ環境へ絞り込むfilter

OBO交換の詳細な失敗理由はDashboardだけに依存せず、Gateway logまたはKonnect Debuggerでrequest IDから追跡する。token、prompt/response payload、PIIはDashboardへ出さない。

### 2.5 MCP Registry

- デモMCP serverをKonnect MCP Registryへpublishする。
- name、description、version、streamable HTTP remote URL、該当するpackage情報を登録する。
- publish payloadまたは生成元definitionと、publish/read-back commandをリポジトリへ保存する。
- credentialや実tokenは保存しない。
- MCP RegistryはTech Previewであるため、対象orgで未提供の場合は無断で代替実装せず停止する。Catalog MCP serverへ切り替える場合はADRと利用者確認を必要とする。

### 2.6 Catalog AI Model

- 接続先Azure OpenAIをCatalogのAI Modelとして登録する。
- provider、target model、version、descriptionを持たせる。
- 現構成はclassic Gateway + AI Proxy Advancedのため、AI Gateway 2.0 implementationへの自動linkを前提にしない。Catalogへ手動定義する。
- API key、secret endpoint、deployment credentialはCatalog definitionやgitへ含めない。

### 2.7 テスト範囲

今回はスモークテストのみとする。既存の全Playwright E2E、3ユーザー全マトリクス、Customer API全条件の回帰テストは再実施しない。

## 3. 将来要件

- Tool/API追加時に`conversion-listener`から`listener` + `conversion-only`へ移行できること。
- MCP Registry API変更またはCatalog MCP serverへの移行に備え、MCP metadataの正本を単一のversioned JSON/YAMLへ寄せること。
- AI Gateway 2.0へ移行する場合にCatalog AI ModelをGateway implementationへlinkできるよう、Catalog identifierとmodel metadataを安定させること。
- IdPはEntra IDを維持する。

## 4. 非スコープ

- Chat UI、Customer Inquiry / Details API、Entra ID権限モデルの全面再設計
- production hardening、CI/CD新設、IdP変更、デモdata拡張
- フルE2E / 回帰テストの再実施
- Vault側でのコード実装

## 5. アーキテクチャ

```text
Browser
  |
  v
Local self-hosted Kong Data Plane
(Docker Compose, kong/kong-gateway:3.16.0.0, DB-less, Konnect managed)
  |-- login Route -- OIDC authorization code/session -- Chat UI/Agent
  |-- MCP Route ----- OIDC OBO -- AI MCP Proxy ACL -- Customer APIs
  `-- LLM Route ----- AI Proxy Advanced --------------- Azure OpenAI

Konnect Control Plane
  |-- Gateway configuration + implicit license delivery
  |-- telemetry / Observability custom dashboard
  |-- MCP Registry
  `-- Catalog AI Model
```

### 5.1 OIDC OBO

正式版3.16でも次の構成を維持する。

- `config.token_exchange.grant_type = jwt_bearer`
- `config.token_exchange.provider = microsoft`
- `config.token_exchange.subject_token_issuers`で信頼するEntra ID issuerを制限
- `config.token_exchange.map_identities_from`は交換後tokenをACLへ渡す設定を維持
- `ai-mcp-oauth2`を重複して有効化せず、OpenID Connectプラグインが提供する交換後claim contextをAI MCP Proxyが使う

既存の以下の実装上の制約も維持する。

- login Routeの`auth_methods`には`authorization_code`と`session`を明示する。
- AI MCP ProxyのTool pathは相対pathを使い、自己リクエスト用の無認証Routeを追加しない。
- AI Proxy Advancedのclient-facing model名には既存の`model_alias`を使う。
- secretを参照するdecK環境変数は`DECK_` prefixを使う。

### 5.2 Bootstrap milestone

次を別milestoneとして検証する。

1. Control Planeが意図したregion/nameで存在する
2. local Data Planeが対象Control Planeへ接続しtelemetryを送信する
3. decKの最初のGateway configが対象Control Planeへ適用される
4. smoke trafficがObservabilityへ反映される
5. MCP RegistryとCatalog AI Modelがread-backできる

## 6. 技術スタック

- Kong Gateway: `kong/kong-gateway:3.16.0.0`
- Runtime: Docker Compose、Konnect self-hosted Data Plane、DB-less
- Gateway config: decK declarative YAML
- Identity: Microsoft Entra ID、OIDC authorization code/session、OBO JWT Bearer + Microsoft provider
- MCP: AI MCP Proxy `conversion-listener`、OAuth access token claim ACL
- LLM: Azure OpenAI、AI Proxy Advanced
- Application: Next.js + Vercel AI SDK、TypeScript + Bun
- Konnect: Gateway Control Plane、Observability Custom Dashboards、MCP Registry、Catalog AI Model
- IaC: Terraform `azuread` provider（Entra ID / Azureのみ）

## 7. スモークテスト

| 要件 | 検証方法 | 合格条件 | 証跡 |
|---|---|---|---|
| GA image / license廃止 | Compose configと起動logを確認 | `3.16.0.0`で起動し、local licenseなしでlicense errorがない | `docker compose config`と起動log |
| Konnect DP接続 | Konnect UI/APIでDP statusを確認 | 対象DPがhealthy/connectedで想定CPに所属 | screenshotまたはread-only API出力 |
| Gateway config | decK validate/diff後に承認済みsync | login / MCP / LLMの3 Routeが対象CPに存在 | validate/diff/sync出力 |
| OIDC OBO + ACL | 権限ありユーザーでlogin→tools/list→1 Tool call、権限不足1ケース | 許可Toolが成功し、不許可Toolが非表示または403 | request ID付き結果と必要最小限のlog |
| LLM Route | Chat UIから1応答 | Chat UIがAzure credentialを持たずに応答成功 | request IDと非機密レスポンス |
| Dashboard | smoke traffic後にDashboardを確認 | 3 RouteとMCP/LLM主要指標を表示 | dashboard ID/URLとscreenshot |
| MCP Registry | publish後にGET/UIでread-back | name/version/remoteが一致 | secretを除くrequest/response |
| Catalog AI Model | UI/APIでread-back | Azure provider、target model、versionが一致 | Catalog ID/URLとread-only出力 |

## 8. 成果物と完了条件

### 成果物

- GA + Konnect Data Plane対応済み`docker-compose.yml`と`.env.example`
- Konnect Control Plane向けdecK設定と安全なvalidate/diff/sync手順
- Observability Dashboard definition/exportと再現手順
- MCP Registry publish definition/commandとread-back手順
- Catalog AI Model definition/commandとread-back手順
- 更新済みREADME、TESTING.md、design brief、agent instruction
- 必要なADR、troubleshooting log、smoke test evidence

### 完了条件

- 7節のスモークテストが合格する。
- local license、Postgres、migrations、local Admin API前提が設定と文書から削除される。
- secret、certificate private key、token、実ユーザー情報がcommitされていない。
- PRにWhat / Why / Testing / 未検証事項 / agent instructionへの改善提案が記載される。
- 未検証のフル回帰、長時間負荷、Dashboard長期trend、Registry GA互換性をTESTING.mdへ明記する。

## 9. 実装前に確定する入力

- Konnect region、Control Plane name/ID、既存CP再利用か新規作成か
- CP endpoint、telemetry endpoint、mTLS certificate/key
- decK、Dashboard、MCP Registry、Catalog操作に必要な最小権限
- 対象orgでMCP Registry Tech Previewが有効か
- Catalogへ登録するAzure OpenAI provider/target model/version

これらはenvironment固有入力であり、self-hosted Data Planeを使うアーキテクチャ自体の再確認事項ではない。

2026-09-20確定済み入力:

- Konnect organization: `hashi-sandbox`
- Konnect geo: North America / US（利用者指定）
- Control Plane名: `azure-obo-demo`。対象Orgでの既存同名CP有無とIDは、`hashi-sandbox`へ認証した後に確認する
- Gateway entityの管理: 既存decKファイルを維持し、Azure/Entra用TerraformへKonnect resourceを追加しない

## 10. 実装順序

1. cleanなfeature branchまたはworktreeを用意する。
2. 本Design Briefとagent instructionを現在要件へ更新する。
3. ComposeをGA + Konnect Data Plane構成へ変更する。
4. decKの接続先をKonnect Control Planeへ変更する。
5. Dashboard / MCP Registry / Catalog definitionと手順を追加する。
6. スモークテストを実行し証跡をTESTING.mdへ残す。
7. 1 PR = 1 themeでPRを作成し、開発エージェントはmergeせず停止する。

## 11. 参考資料

- [Kong Gateway changelog](https://developer.konghq.com/gateway/changelog/)
- [OpenID Connect plugin changelog](https://developer.konghq.com/plugins/openid-connect/changelog/)
- [Konnect license management](https://developer.konghq.com/konnect-platform/account/)
- [Control Plane and Data Plane communication](https://developer.konghq.com/gateway/cp-dp-communication/)
- [Custom Dashboards](https://developer.konghq.com/custom-dashboards/)
- [MCP registries in Catalog](https://developer.konghq.com/catalog/mcp-registry/)
- [AI Models in Catalog](https://developer.konghq.com/catalog/ai-models/)
- `docs/OBO.md`
- `docs/decisions/0001-terraform-azure-auth-method.md`
- `docs/decisions/0002-mcp-llm-route-network-isolation.md`
- `docs/troubleshooting-log.md`
- `TESTING.md`
