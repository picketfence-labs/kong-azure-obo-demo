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

## セットアップ手順
（実装が進むにつれて具体化します）

## 知見の記録
- 設計判断（選択肢・判断基準・想定と実際の差分）: [docs/decisions/](./docs/decisions/)（1判断＝1ファイル、`TEMPLATE.md`参照）
- 想定通りに動かなかったこと（漏れなく記録）: [docs/troubleshooting-log.md](./docs/troubleshooting-log.md)

## クリーンアップ
```bash
docker compose down -v
terraform destroy
```
