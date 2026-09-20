# Kong Gateway 3.16 — Entra ID OBO × AI MCP Proxy ACL デモ

Chat AIエージェントからMCP経由でバックエンドAPIへアクセスするデモです。「エージェントとしてログインする権限」と「個々のAPI（Tool）を実行する権限」を分離し、Kong Gateway 3.16のOpenID ConnectプラグインのOBO（On-Behalf-Of）機能でトークン交換、AI MCP ProxyのACL機能でTool単位の認可を行う一連の流れを実地検証します。Kong GatewayはDocker Compose上のself-hosted Data Planeとして起動し、Konnect Control Planeから設定とライセンスを受信します。

着手前の基本設計は [docs/design-brief.md](./docs/design-brief.md) を参照してください。個別の設計判断（検討した選択肢・判断基準）は [docs/decisions/](./docs/decisions/) に記録します。

![Chat UI画面](./docs/testing-images/02-chat-inquiry-only-details-denied.png)

**実際に動かして動作確認したい方は [TESTING.md](./TESTING.md) を参照してください**（スクリーンショット付きの検証手順）。**OBO（On-Behalf-Of）によるトークン交換の仕組みを図解付きで理解したい方は [docs/OBO.md](./docs/OBO.md) を参照してください**。

## 全体アーキテクチャ

Kong Gatewayが3系統のRoute/Serviceをフロントします（詳細は [docs/design-brief.md](./docs/design-brief.md) 参照）:

1. **Chat UI/エージェント アクセス用Route**: `openid-connect`（認可コードフロー、ログイン可否判定のみ。OBOなし）
2. **MCPエンドポイント用Route**: `openid-connect`（`token_exchange` でOBO）＋ `ai-mcp-proxy`（ACL）
3. **LLM（Azure OpenAI）アクセス用Route**: `ai-proxy-advanced`（LLMアクセスの抽象化）

Chat UI（Next.js）はKongの認証を全面的に信頼し、独自のOAuthクライアント実装（Auth.js等）を持ちません。

## 必要なもの
- Docker / Docker Compose
- Kong KonnectのorganizationとGateway Control Plane
- Control Planeへ登録済みのData Plane用mTLS certificate/key
- decK >= 1.40.0と対象Control Planeを操作できるKonnect token
- Terraform >= 1.5（`azuread` / `azurerm` / `kong/konnect` provider）
- Microsoft Entra IDテナントと管理者権限（App Registration・Security Group作成のため）
- Azure OpenAIリソース

## 技術スタック
- **Kong Gateway**: `kong/kong-gateway:3.16.0.0`、Konnect管理のself-hosted Data Plane（DB-less）、decKで宣言的管理
- **Konnect / Entra ID連携**: Terraform（Konnectは`terraform/konnect/`、Azure/Entra IDは`terraform/`の独立state）
- **Chat UI/エージェント**: Next.js（App Router）+ Vercel AI SDK
- **デモAPI（Customer Inquiry/Customer Details）**: TypeScript + Bun
- **実LLM**: Azure OpenAI（`ai-proxy-advanced`経由で抽象化）

## Konnect bootstrap入力

- **Organization**: `hashi-sandbox`
- **Geo**: North America / US（Konnect API: `https://us.api.konghq.com`）
- **Control Plane名**: `azure-obo-demo`
- **Data Plane**: このリポジトリのDocker Composeで起動するself-hosted Data Plane
- **管理境界**: Control PlaneとData Plane client certificateは`terraform/konnect/`、Gateway entityは既存の`kong/*.yaml`をdecKで管理する。Azure/Entra IDの`terraform/`とはstateを分離する（判断根拠: [ADR-0003](./docs/decisions/0003-konnect-terraform-state-boundary.md)）

## デモAPI（Customer Inquiry/Customer Details）

`services/demo-api`（Bun/TypeScript）が、design-brief 2節のAPI仕様をひとつのHTTPサーバーとして実装しています。

### エンドポイント
| メソッド/パス | 相当するAPI | 検索条件 | 戻り値 |
|---|---|---|---|
| `GET /customers?name=&gender=&prefecture=` | Customer Inquiry | 氏名（部分一致）/性別/都道府県、AND条件（全て省略可） | `id`/`name`/`gender`/`prefecture`の4項目のみ |
| `GET /customers/:id` | Customer Details | 顧客ID（UUID）による完全一致のみ | フル項目（下記参照）。一覧・部分一致検索のエンドポイントは存在しないため、Customer Inquiryを経由しないとID自体を取得できない |

テストデータの生成タイミングと構造（生成される具体的なフィールド・サンプル）は [TESTING.md](./TESTING.md) を参照してください。

### ローカル起動
```bash
cd services/demo-api
bun run dev   # PORT環境変数で変更可（デフォルト3001）
bun test      # ユニットテスト（検索AND条件・ID一意取得等）
```

## セットアップ手順

### Azure/Entra ID 認証（Terraformを実行する前に一度だけ）
Terraform（`terraform/`配下）は、クライアントシークレット等の静的資格情報を持たず、Azure CLIの委譲認証に委ねる（判断根拠: [ADR-0001](./docs/decisions/0001-terraform-azure-auth-method.md)）。

1. Azure CLIをインストール: `brew install azure-cli`
2. ログイン: `az login`（ブラウザが開くのでAzureアカウントでサインインする）
3. 対象テナント/サブスクリプションを確認: `az account show --output table`
   - 複数サブスクリプションがある場合は `az account set --subscription <id>` で切り替える
4. 疎通確認: `cd terraform && terraform init && terraform plan`
   - `auth_check` outputに想定通りのテナントID/サブスクリプションIDが出れば成功（この段階ではリソースは何も作成されない）

### Konnect Control Plane（Terraform）

Konnect platform resourceはAzure/Entra IDとは別の`terraform/konnect/` rootで管理する。認証情報はコードやtfvarsへ書かず、実行時環境変数で渡す。

```bash
export KONNECT_TOKEN='<personal-access-token>'
# System Accountを使う場合はKONNECT_SPATを使用する

cd terraform/konnect
terraform init
terraform validate
terraform plan -out=tfplan
terraform apply tfplan

# local stateにはData Plane private keyが含まれるため、apply後に必ず制限する
chmod 600 terraform.tfstate
cd ../..
```

このapplyで次を作成する。

- USリージョンのself-managed Control Plane `azure-obo-demo`
- Docker Compose Data Plane用のRSA key / self-signed client certificate
- Control Planeへのclient certificate登録
- `secrets/konnect/tls.crt`、`secrets/konnect/tls.key`
- Composeへ渡す`secrets/konnect/compose.env`

`terraform/konnect/terraform.tfstate`と`secrets/`はgitignore対象。stateにも秘密鍵が含まれるため、共有・commitしない。

### Kong Gateway（decK宣言的設定）
`kong/`配下がRoute別のdecK state file（`login-route.yaml`: Chat UIログイン、`mcp-route.yaml`: OBO+ACL、`llm-route.yaml`: Azure OpenAI抽象化）。秘匿値は平文で書かず、decKの環境変数テンプレート`${{ env "DECK_XXX" }}`（`DECK_`プレフィックス必須）で参照する。

1. `cp .env.example .env`を実行し、Entra ID / Azure OpenAI等のlocal設定を入力する。Konnect endpointとcertificate pathはTerraform生成の`secrets/konnect/compose.env`から後勝ちで読み込む。
2. Compose構成を確認してからData Planeを起動する。local Postgres、migrations、Admin API、`KONG_LICENSE_DATA`は使用しない。
   ```bash
   docker compose --env-file .env --env-file secrets/konnect/compose.env config --quiet
   docker compose --env-file .env --env-file secrets/konnect/compose.env up -d
   ```
3. Terraform outputとKonnect接続情報から、decKが使う環境変数を設定する:
   ```bash
   export DECK_KONNECT_TOKEN='<personal-or-system-access-token>'
   export DECK_KONNECT_ADDR='https://us.api.konghq.com'
   export DECK_KONNECT_CONTROL_PLANE_NAME='azure-obo-demo'

   cd terraform
   export DECK_ENTRA_ISSUER="https://login.microsoftonline.com/$(terraform output -raw entra_tenant_id)/v2.0"
   export DECK_MIDDLE_TIER_CLIENT_ID=$(terraform output -raw middle_tier_client_id)
   export DECK_MIDDLE_TIER_CLIENT_SECRET=$(terraform output -raw middle_tier_client_secret)
   export DECK_DOWNSTREAM_API_APPLICATION_ID_URI=$(terraform output -raw downstream_api_application_id_uri)
   export DECK_GROUP_API_CUSTOMER_INQUIRY_OBJECT_ID=$(terraform output -raw group_api_customer_inquiry_object_id)
   export DECK_GROUP_API_CUSTOMER_DETAILS_OBJECT_ID=$(terraform output -raw group_api_customer_details_object_id)
   export DECK_AZURE_OPENAI_API_KEY=$(terraform output -raw azure_openai_api_key)
   export DECK_AZURE_OPENAI_DEPLOYMENT_NAME=$(terraform output -raw azure_openai_deployment_name)
   export DECK_AZURE_OPENAI_INSTANCE_NAME=kong-obo-demo-openai
   # Kongのセッションcookie署名用シークレット（decK専用の値、Terraform outputではない）。
   # 再syncのたびに値を変えると既存セッションが無効化されるため、.env等に一度保存して使い回すこと
   export DECK_SESSION_SECRET=$(openssl rand -base64 32)
   cd ..
   ```
4. ローカルでの構文検証（Kongへの接続不要）: `deck file validate kong/login-route.yaml kong/mcp-route.yaml kong/llm-route.yaml`
5. 対象Control Planeに対するonline validationと差分確認:
   ```bash
   deck gateway validate kong/login-route.yaml kong/mcp-route.yaml kong/llm-route.yaml
   deck gateway diff kong/login-route.yaml kong/mcp-route.yaml kong/llm-route.yaml
   ```
6. 差分をレビューし、人間の明示承認を得た後だけ`deck gateway sync kong/login-route.yaml kong/mcp-route.yaml kong/llm-route.yaml`で反映する。

ネットワーク分離の考え方（MCP/LLM Routeをブラウザから到達不可にする方式と、その実際の限界）は[ADR-0002](./docs/decisions/0002-mcp-llm-route-network-isolation.md)を参照。

### Chat UI/エージェント

`services/chat-ui`（Next.js App Router + Vercel AI SDK）。design-brief 3節の通り、Auth.js等のOAuthクライアント実装は持たず、`kong/login-route.yaml`のopenid-connectプラグインが認可コードフロー・セッション管理・ログアウトを全て担う。Next.js側はKongが`upstream_headers`/`upstream_access_token_header`で転送するヘッダーを信頼するだけ:

- `X-User-Name`/`X-User-Email`: ログイン中ユーザーの表示用（画面上部のヘッダーバー）
- `Authorization: Bearer <access_token>`: Route 1のログインで取得したアクセストークン（audienceはミドル層App自身）。`src/app/api/chat/route.ts`がこれをそのままMCPエンドポイント用Route（`kong/mcp-route.yaml`）へのBearerトークンとして再提示し、そちらのOBO(`token_exchange.grant_type=jwt_bearer`)のassertionとして使われる

LLM呼び出しは`kong/llm-route.yaml`の`ai-proxy-advanced`（Route `/llm`）を、Azure固有の設定を一切持たないOpenAI互換クライアントとして叩く。`model`には固定値`kong-demo-llm`（`llm-route.yaml`の`model_alias`と一致）を送るだけで、実際のAzureデプロイ名・APIバージョン・エンドポイントはエージェント側から完全に隠蔽される（design-brief 検証方法9番目の要件）。

ローカル起動（Docker Composeを使わない場合）:
```bash
cd services/chat-ui
bun install
bun run dev   # http://localhost:3000 単体では認証ヘッダーが無いため、Kong経由（http://localhost:8000）でのアクセスが前提
```

## 知見の記録
- 設計判断（選択肢・判断基準・想定と実際の差分）: [docs/decisions/](./docs/decisions/)（1判断＝1ファイル、`TEMPLATE.md`参照）
- 想定通りに動かなかったこと（漏れなく記録）: [docs/troubleshooting-log.md](./docs/troubleshooting-log.md)

## クリーンアップ
```bash
docker compose down
terraform -chdir=terraform/konnect destroy
terraform -chdir=terraform destroy
```

2つのdestroyは別stateを対象にする。Azure/Entra ID側の現在stateが空の場合、それはデモresourceのdestroy完了後を表すため、再作成は新しいplanをレビューしてから行う。destroy前の`.backup`を現在stateへ復旧しない。
