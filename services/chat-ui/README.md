# Chat UI/エージェント

Kong Gateway 3.16 OBO デモのChat UI。詳細はリポジトリルートの[README.md](../../README.md)の「Chat UI/エージェント」節を参照。

このアプリ自身はOAuthクライアントを持たない。ログイン・セッション管理は[`kong/login-route.yaml`](../../kong/login-route.yaml)のopenid-connectプラグインが担い、Next.jsはKongが転送するヘッダーを信頼するだけの構成（詳細は[docs/design-brief.md](../../docs/design-brief.md) 3節）。単体（`bun run dev`、http://localhost:3000）で開いても認証ヘッダーが無いため、Kong経由（http://localhost:8000、`docker compose up -d`）でのアクセスが前提。
