# OBO（On-Behalf-Of）解説

このデモにおける全体構成と、Kong Gateway と Entra ID の間で実際に行われている OBO（On-Behalf-Of）トークン交換の詳細をまとめます。設計判断の背景は [design-brief.md](./design-brief.md) を、実装時に判明した挙動は [troubleshooting-log.md](./troubleshooting-log.md) を参照してください。

## 1. 全体構成

Kong Gateway が単一のエントリポイント（`http://localhost:8000`）として、性質の異なる3系統の通信をフロントします。ブラウザ・Next.js・デモAPI・Azure OpenAI はいずれも Kong を介してのみ到達可能で、相互に直接通信しません（`kong-internal` ネットワーク、`internal: true`）。

```mermaid
flowchart TB
    subgraph Browser["ブラウザ"]
        User["ユーザー"]
    end

    subgraph EntraID["Entra ID"]
        IdP["IdP\n（ミドル層App / ダウンストリームAPI App）"]
    end

    subgraph Kong["Kong Gateway 3.16（Postgres backed）"]
        R1["Route① /\nopenid-connect\n（認可コードフロー、OBOなし）"]
        R2["Route② /mcp/customers\nopenid-connect（OBO）\n+ ai-mcp-proxy（ACL）"]
        R3["Route③ /llm\nai-proxy-advanced"]
    end

    subgraph Internal["kong-internalネットワーク（外部到達不可）"]
        ChatUI["chat-ui\n（Next.js + Vercel AI SDK）"]
        DemoAPI["demo-api\n（Bun/TypeScript）\nCustomer Inquiry / Details"]
    end

    AOAI["Azure OpenAI"]

    User -- "① ログイン（認可コードフロー）" --> R1
    R1 <-- "認証・トークン発行" --> IdP
    R1 -- "X-User-Name/Email\nAuthorization: Bearer" --> ChatUI

    ChatUI -- "② tools/call（Bearerトークン再提示）" --> R2
    R2 <-- "③ OBOトークン交換\n(token_exchange)" --> IdP
    R2 -- "④ ACL通過後、実データ取得" --> DemoAPI

    ChatUI -- "⑤ LLM呼び出し\nmodel: kong-demo-llm" --> R3
    R3 -- "Azure資格情報を注入" --> AOAI
```

- **Route①（`kong/login-route.yaml`）**: ブラウザ⇄Next.jsの経路。`openid-connect` が認可コードフローとセッションCookieの発行のみを扱う。OBOはしない
- **Route②（`kong/mcp-route.yaml`）**: Next.jsのエージェント（サーバーサイド）⇄デモAPIの経路。`openid-connect` が OBO（`token_exchange`）でトークンを交換し、`ai-mcp-proxy` がACLを評価してからMCP変換済みのTool呼び出しとしてデモAPIへ中継する
- **Route③（`kong/llm-route.yaml`）**: Next.jsのエージェント⇄Azure OpenAIの経路。`ai-proxy-advanced` がAzure固有の資格情報・エンドポイント詳細を注入する（OBOとは無関係）

「エージェントとしてログインする権限」（Route①）と「個々のAPIを実行する権限」（Route②）が別々のEntra ID Security Groupで判定される点が、このデモの核心（[design-brief.md](./design-brief.md) 2節）です。

## 2. OBOフロー

OBOの本質は、**「ミドル層App（Kongが代理人として振る舞うApp）宛てのトークン」を、ユーザーの同意を都度求めることなく「ダウンストリームAPI App宛てのトークン」へ交換する**ことです。RFC 7523（JWT Bearer）を使い、Entra ID向けには `provider: microsoft` を指定することで `requested_token_use=on_behalf_of` が自動付与されます（[design-brief.md](./design-brief.md) 3節）。

```mermaid
sequenceDiagram
    actor U as ユーザー（ブラウザ）
    participant K1 as Kong Route①<br/>(openid-connect)
    participant Entra as Entra ID
    participant CUI as chat-ui (Next.js)
    participant K2 as Kong Route②<br/>(openid-connect + ai-mcp-proxy)
    participant API as demo-api

    U->>K1: GET / （未ログイン）
    K1->>Entra: 認可コードフローへリダイレクト
    Entra->>U: ログイン画面（メール→パスワード）
    U->>Entra: 認証情報を入力
    Entra->>K1: 認可コード（scopes: openid, profile,<br/>api://<ミドル層App>/access_as_user）
    K1->>Entra: コード→トークン交換
    Entra-->>K1: Token A（aud=ミドル層App）
    Note over K1: セッションCookie発行。<br/>upstream_headersでname/preferred_usernameを<br/>X-User-Name/X-User-Emailへ、<br/>upstream_access_token_headerでToken Aを<br/>Authorization: Bearerへマッピング
    K1->>CUI: X-User-Name, X-User-Email,<br/>Authorization: Bearer Token A
    CUI-->>U: Chat UI表示（ログイン中: ユーザー名）

    U->>CUI: プロンプト送信（例:「東京都の顧客を検索して」）
    CUI->>K2: tools/call<br/>Authorization: Bearer Token A（そのまま再提示）
    Note over K2: openid-connectがToken Aを検証。<br/>client_id（ミドル層App）がToken Aのaudienceと<br/>一致するためOBO交換を実行できる
    K2->>Entra: token_exchange(grant_type=jwt_bearer,<br/>provider=microsoft, assertion=Token A,<br/>scope=api://<ダウンストリームAPI App>/.default)
    Entra-->>K2: Token B（aud=ダウンストリームAPI App、groupsクレーム付き）
    Note over K2: openid-connectがkong.ctx.shared.ai_mcp_oauth2に<br/>Token Bのクレームを書き込み、<br/>ai-mcp-proxyのACL評価に渡す（map_identities_from: exchanged_tokens）
    K2->>K2: ai-mcp-proxy: groupsクレームを<br/>tools[].acl.allowと照合
    alt ACL許可
        K2->>API: GET /customers?... <br/>Authorization: Bearer Token B（再転送）
        API-->>K2: 実データ（顧客ID/氏名/性別/都道府県）
        K2-->>CUI: tools/callレスポンス
    else ACL拒否
        K2-->>CUI: 403 Forbidden（tools/listにも出現しない）
    end
    CUI-->>U: 回答を表示
```

### トークンの中身がどう変わるか

同じユーザーの同一ログインセッション内で、Kongが仲介する2つのトークンの中身を比較すると、OBOが何を変えているのかがわかります。`sub`/`oid`（ユーザー本人を指すクレーム）は同一のまま、**audienceとscopeがミドル層AppからダウンストリームAPI Appへ切り替わり、ACL評価に使う`groups`クレームがここで初めて現れる**点が要点です。

**Token A（Route①でEntra IDが発行、`Authorization: Bearer`としてNext.jsへ転送される）**
```json
{
  "aud": "11111111-1111-1111-1111-111111111111",
  "iss": "https://login.microsoftonline.com/<tenant-id>/v2.0",
  "sub": "AbCdEf...（ユーザー固有・アプリごとに異なるペアワイズ識別子）",
  "oid": "99999999-9999-9999-9999-999999999999",
  "appid": "11111111-1111-1111-1111-111111111111",
  "scp": "access_as_user",
  "name": "Demo User - Both APIs",
  "preferred_username": "demo-both-apis@hashipicketfence.onmicrosoft.com"
  // ※ groupsクレームは無い、またはこのAppに関係の無いグループのみ:
  //   ここで割り当てられているのは「AIエージェント」用Security Group
  //   （ログイン可否判定用、Enterprise Applicationの「割り当てが必要」設定でのみ使われ、
  //   Kongはこのクレームを見ない）
}
```

**Token B（Route②でopenid-connectがtoken_exchangeにより取得、demo-apiへ再転送される）**
```json
{
  "aud": "22222222-2222-2222-2222-222222222222",
  "iss": "https://login.microsoftonline.com/<tenant-id>/v2.0",
  "sub": "GhIjKl...（同一ユーザーだが、audience違いによりToken Aとは別の値になる）",
  "oid": "99999999-9999-9999-9999-999999999999",
  "appid": "11111111-1111-1111-1111-111111111111",
  "scp": ".default",
  "groups": [
    "33333333-3333-3333-3333-333333333333",
    "44444444-4444-4444-4444-444444444444"
  ]
  // ↑ ダウンストリームAPI Appに割り当てられた「API」用Security Group
  //   （Customer Inquiry用/Customer Details用）のObject IDがそのまま入る。
  //   ai-mcp-proxyのacl_attribute_type: oauth_access_token /
  //   access_token_claim_field: groups がこの配列を読み、
  //   tools[].acl.allowと突き合わせて許可/拒否を判定する
}
```

比較すると:

| クレーム | Token A（Route①） | Token B（Route②、OBO交換後） |
|---|---|---|
| `aud`（宛先） | ミドル層App | ダウンストリームAPI App |
| `scp`（スコープ） | `access_as_user` | `.default`（ダウンストリームAPI側の既定スコープ） |
| `oid`（ユーザー本人） | 同一 | 同一（変わらない） |
| `appid`（実行主体） | ミドル層App | ミドル層App（変わらない。Kongが代理人であり続けることを示す） |
| `groups` | ACL評価には無関係 | Customer Inquiry/Details用Security GroupのObject IDが出現し、これがACL判定の入力になる |

`oid`/`appid` が変わらないことは「ユーザー本人が、ミドル層App（Kong）を代理人として、ダウンストリームAPIへアクセスしている」というOBOの意味そのものを表しています。一方で `aud`/`scp`/`groups` が変わることで、Route①では判定できなかった「Tool単位の実行権限」がRoute②で初めて評価可能になります。

> [!note]
> 上記の値は説明用のサンプルであり、実際のテナントID・クライアントID・ユーザー識別子ではありません。実際のACL許可/拒否の動作確認手順（スクリーンショット付き）は [TESTING.md](../TESTING.md) を参照してください。

## 関連ドキュメント
- [design-brief.md](./design-brief.md) — 要件・アーキテクチャの正本
- [decisions/0002-mcp-llm-route-network-isolation.md](./decisions/0002-mcp-llm-route-network-isolation.md) — Route②/③をブラウザから隔離する方式とその限界
- [troubleshooting-log.md](./troubleshooting-log.md) — `ai-mcp-proxy`の自己リクエストが同じKongルーターを再度通過する挙動など、実機検証で判明した詳細
- [TESTING.md](../TESTING.md) — 実際にログインしてACLの許可/拒否を確認する手順
