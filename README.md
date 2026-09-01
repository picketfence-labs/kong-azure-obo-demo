# Kong Gateway 3.16 (beta) — Entra ID OBO × AI MCP Proxy ACL デモ

Chat AIエージェントからMCP経由でバックエンドAPIへアクセスするデモです。「エージェントとしてログインする権限」と「個々のAPI（Tool）を実行する権限」を分離し、Kong Gateway 3.16のOpenID ConnectプラグインのOBO（On-Behalf-Of）機能でトークン交換、AI MCP ProxyのACL機能でTool単位の認可を行う一連の流れを実地検証します。**Konnectは使用しません**（Kong Gateway単体、Postgres backed）。

着手前の基本設計は [docs/design-brief.md](./docs/design-brief.md) を参照してください。個別の設計判断（検討した選択肢・判断基準）は [docs/decisions/](./docs/decisions/) に記録します。

## 全体アーキテクチャ

Kong Gatewayが3系統のRoute/Serviceをフロントします（詳細は [docs/design-brief.md](./docs/design-brief.md) 参照）:

1. **Chat UI/エージェント アクセス用Route**: `openid-connect`（認可コードフロー、ログイン可否判定のみ。OBOなし）
2. **MCPエンドポイント用Route**: `openid-connect`（`token_exchange` でOBO）＋ `ai-mcp-proxy`（ACL）
3. **LLM（Azure OpenAI）アクセス用Route**: `ai-proxy-advanced`（LLMアクセスの抽象化）

Chat UI（Next.js）はKongの認証を全面的に信頼し、独自のOAuthクライアント実装（Auth.js等）を持ちません。

## 必要なもの
- Docker / Docker Compose
- Kong Enterpriseライセンス
- Terraform >= 1.5（`azuread` provider）
- Microsoft Entra IDテナントと管理者権限（App Registration・Security Group作成のため）
- Azure OpenAIリソース

## 技術スタック
- **Kong Gateway**: `kong/kong-gateway-dev:pr-21082-ubuntu`（ベータ、Entra ID OBO対応ビルド）、Postgres backed、decKで宣言的管理
- **Entra ID連携**: Terraform（`azuread` provider）
- **Chat UI/エージェント**: Next.js（App Router）+ Vercel AI SDK
- **デモAPI（Customer Inquiry/Customer Details）**: TypeScript + Bun
- **実LLM**: Azure OpenAI（`ai-proxy-advanced`経由で抽象化）

## デモAPI（Customer Inquiry/Customer Details）

`services/demo-api`（Bun/TypeScript）が、design-brief 2節のAPI仕様をひとつのHTTPサーバーとして実装しています。

### エンドポイント
| メソッド/パス | 相当するAPI | 検索条件 | 戻り値 |
|---|---|---|---|
| `GET /customers?name=&gender=&prefecture=` | Customer Inquiry | 氏名（部分一致）/性別/都道府県、AND条件（全て省略可） | `id`/`name`/`gender`/`prefecture`の4項目のみ |
| `GET /customers/:id` | Customer Details | 顧客ID（UUID）による完全一致のみ | フル項目（下記参照）。一覧・部分一致検索のエンドポイントは存在しないため、Customer Inquiryを経由しないとID自体を取得できない |

### テストデータの生成タイミングと構造
`services/demo-api/src/data.ts`のモジュールトップレベルで`generateCustomers(100, 42)`が**プロセス起動時に一度だけ**実行され、以降はメモリ上の配列を参照するだけ（リクエスト毎の再生成やDB永続化は無い）。シード（`42`）固定の擬似乱数（mulberry32）のみから機械的に組み立てているため、プロセス/コンテナを再起動しても**毎回全く同じ100件（IDを含む）が再現**される。実在の人物・実在の番号は一切参照していない架空データ（生成方法の詳細: [docs/troubleshooting-log.md](./docs/troubleshooting-log.md)）。

生成される1件のフィールド構成:

| フィールド | 型 | Inquiryで返す | Detailsで返す |
|---|---|---|---|
| `id` | UUID v4形式の文字列 | ✅ | ✅ |
| `name` | 姓+名 | ✅ | ✅ |
| `gender` | `"male"` \| `"female"` | ✅ | ✅ |
| `prefecture` | 47都道府県のいずれか | ✅ | ✅ |
| `age` | 20〜79の整数 | ✗ | ✅ |
| `myNumber` | 12桁の数字文字列（マイナンバー相当、チェックデジット等の実仕様は再現していない） | ✗ | ✅ |
| `address` | `{都道府県}〇〇市X丁目X番X号`（架空の地名） | ✗ | ✅ |
| `phone` | `090-XXXX-XXXX` | ✗ | ✅ |
| `email` | `customer{連番}@example.com` | ✗ | ✅ |

サンプル（`GET /customers/849d73eb-438a-407d-8904-02c802d7c570`相当）:
```json
{
  "id": "849d73eb-438a-407d-8904-02c802d7c570",
  "name": "小林花",
  "gender": "female",
  "prefecture": "島根県",
  "age": 30,
  "myNumber": "055262378522",
  "address": "島根県〇〇市3丁目1番6号",
  "phone": "090-6690-9491",
  "email": "customer0@example.com"
}
```

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

## 知見の記録
- 設計判断（選択肢・判断基準・想定と実際の差分）: [docs/decisions/](./docs/decisions/)（1判断＝1ファイル、`TEMPLATE.md`参照）
- 想定通りに動かなかったこと（漏れなく記録）: [docs/troubleshooting-log.md](./docs/troubleshooting-log.md)

## クリーンアップ
```bash
docker compose down -v
terraform destroy
```
