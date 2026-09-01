# 動作確認手順

このページだけを見れば、design-brief（[docs/design-brief.md](./docs/design-brief.md) 5節）が定めた検証項目を一通り実地確認できます。セットアップ手順（`docker compose up` / `deck gateway sync`）は済んでいる前提です。未セットアップの場合は [README.md](./README.md) の「セットアップ手順」を先に行ってください。

## アクセス先

| 用途 | URL |
|---|---|
| Chat UI（ここからログインして操作します） | http://localhost:8000/ |
| Kong Admin API（decK同期状態の確認用、通常は使いません） | http://localhost:8001/ |

## テストユーザー

Entra IDテナント上に作成済みの3ユーザーです。全員同じパスワード体系のダミーアカウントで、実在の人物とは無関係です。

| ユーザー | ログインID (UPN) | パスワード | 割り当てられた権限 |
|---|---|---|---|
| ① ログイン不可の反例 | `demo-no-agent-access@hashipicketfence.onmicrosoft.com` | `08yv)Gg1*EwR2hO#*ItHsyXt` | なし（AIエージェントへのアクセス自体が未割当） |
| ② Inquiryのみ | `demo-inquiry-only@hashipicketfence.onmicrosoft.com` | `V+F8(U*6wd4h))T(wM12kd0p` | 顧客検索（Customer Inquiry）のみ |
| ③ 両方 | `demo-both-apis@hashipicketfence.onmicrosoft.com` | `e6(lx02!QzbgZ!&FtAQKL=mP` | 顧客検索＋顧客詳細（Customer Inquiry・Customer Details両方） |

複数ユーザーを行き来する場合、Entra IDのアカウント選択画面で「別のアカウントを使用する」を選ぶか、ブラウザのプライベートウィンドウを使うとスムーズです。

## テストデータの生成タイミングと構造

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

---

## シナリオ①: 未割当ユーザーはログインできないこと

1. http://localhost:8000/ を開く（未ログインなら自動的にEntra IDのログイン画面へ遷移します）

   ![Entra IDログイン画面（メールアドレス入力）](./docs/testing-images/03-entraid-login-email.png)

2. ユーザー①（`demo-no-agent-access@...`）のメールアドレス・パスワードを入力してサインインを試みる

   ![パスワード入力画面](./docs/testing-images/04-entraid-login-password.png)

3. **Entra ID自体が`AADSTS50105`エラーでログインを拒否**することを確認（Kongより手前、Entra IDの「割り当てが必要」設定による）

   ![ログイン拒否画面（AADSTS50105）](./docs/testing-images/06-entraid-login-blocked.png)

## シナリオ②: Inquiryのみユーザー（検索はできるが詳細取得はできない）

1. ユーザー②（`demo-inquiry-only@...`）でログイン（今度はEntra IDの認証を通過し、Chat UIへ遷移します）
2. 画面上部に「ログイン中: Demo User - Inquiry Only（demo-inquiry-only@...）」と表示されることを確認（Kongが転送したトークン情報がChat UIに反映されている証跡）
3. チャット欄に「**東京都在住の顧客を検索して**」と入力 → 顧客ID・氏名・性別・都道府県のサマリのみが返る
4. 続けて「**（表示された顧客名）さんの詳細情報を教えて**」と入力 → **拒否される**（`customer_details` Toolがこのユーザーには表示されず呼び出せないため）

   ![Inquiryのみユーザー: 検索は成功、詳細は取得不可](./docs/testing-images/02-chat-inquiry-only-details-denied.png)

## シナリオ③: 両方権限ユーザー（検索も詳細取得もできる）

1. ログアウトし、ユーザー③（`demo-both-apis@...`）でログイン
2. 画面上部の表示がユーザー③に変わることを確認
3. チャット欄に「**（同じ顧客名）さんの詳細情報を教えて**」と入力 → **今度は住所・電話番号・マイナンバー等のフル情報まで返る**

   ![両方権限ユーザー: 詳細情報まで取得できる](./docs/testing-images/05-chat-both-apis-full-details.png)

同じ質問でもログインユーザーによって回答内容（取得できる情報の範囲）が変わることが、AI MCP ProxyのACL（Entra IDのSecurity Groupベース）がOBO交換後のトークンに対して機能している証跡です。

---

## その他の確認項目（design-brief 5節、画面操作以外での確認）

上記シナリオで画面から確認できない残りの項目は、コードや通信ログから確認できます:

- **AND条件検索**: 「東京都在住の**女性**を検索して」のように条件を追加すると、該当者のみに絞り込まれること（性別を指定しなければ都道府県内の全員が返る点と比較すると分かりやすいです）
- **ログアウト**: 画面右上の「ログアウト」ボタン → Entra IDのサインアウト画面へ遷移 → 再度トップページへ戻ると未ログイン状態に戻っていること
- **顧客IDの推測不可**: Customer Details用の一覧・検索エンドポイントは存在しないため（[services/demo-api/src/server.ts](./services/demo-api/src/server.ts)参照）、Customer Inquiryを経由せずに顧客IDを得る手段が無いこと
- **エージェントのAzure非依存**: `services/chat-ui/src/app/api/chat/route.ts`がAzure OpenAIのエンドポイント・APIバージョン・デプロイ名を一切保持せず、固定のモデル名`kong-demo-llm`のみでKongの`/llm`エンドポイントを呼び出していること
