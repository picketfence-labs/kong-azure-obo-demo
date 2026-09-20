# Troubleshooting Log（知見ログ）

実装中に**想定通りに動かなかったこと**を、その場で漏れなく記録するログです。`docs/decisions/`のADR（複数の妥当な選択肢がある判断ポイント専用）とは異なり、判断ポイントかどうかに関わらず、あらゆる「期待と実際のギャップ」（エラー、ドキュメントと異なる挙動、想定した設定で動かなかった、リトライが必要だった等）を対象にします。

## 記入ルール
- **その場で書く**。後からまとめて思い出して書かない
- 追記専用。「大したことではない」と判断して省略しない
- 本プロジェクトはKong Gateway 3.16のベータ機能（Entra ID OBO）を使うため、**公式ドキュメントとの乖離・ドキュメント自体の不在**は特に優先して記録する

## 記入項目（1エントリあたり）
```markdown
## YYYY-MM-DD HH:MM（または該当タスク名） タイトル
- **何を期待していたか**:
- **実際どうだったか**（エラーメッセージ・症状を具体的に）:
- **原因**（分かれば。不明なら「不明」と書く）:
- **対処・回避方法**（または未解決なら次にどうするか）:
- **コスト**（任意。試行回数・かかった時間等、目立って大きい場合のみ）:
```

<!-- 以下、実際のログをこの下に追記していく -->

## 2026-09-01 Azure/Terraform bootstrap `.gitignore`が`.terraform.lock.hcl`を誤って除外
- **何を期待していたか**: `terraform init`で生成される`.terraform.lock.hcl`はプロバイダーバージョン固定のためコミット対象になる想定だった
- **実際どうだったか**: 初期Scaffolding時の`.gitignore`に`.terraform.lock.hcl`が（`!`否定無しで）そのまま列挙されており、`git check-ignore -v`で除外対象になっていることを確認
- **原因**: 汎用的なTerraform用`.gitignore`テンプレートをそのまま流用した際に、通常除外すべきでないファイルまで含めてしまったと推測（不明、要因は推測）
- **対処・回避方法**: `.gitignore`から`.terraform.lock.hcl`の行を削除しコミット対象に戻した
- **コスト**: 軽微（`git check-ignore`で1回確認しただけ）

## 2026-09-01 Azure OpenAI: Japan Eastではgpt-4o-miniに`Standard`（リージョン固定）SKUが無い
- **何を期待していたか**: リージョンをJapan Eastに固定すれば、デプロイのSKUも`Standard`（そのリージョン内で処理が完結）を選べる想定だった
- **実際どうだったか**: `az rest`で`.../locations/japaneast/models`を確認したところ、`gpt-4o-mini`の利用可能SKUは`GlobalStandard`/`GlobalBatch`/`ProvisionedManaged`/`GlobalProvisionedManaged`のみで、リージョン固定の`Standard`は提供されていなかった
- **原因**: Azure OpenAIの新しめのモデルは、容量確保のため`GlobalStandard`系SKUのみで提供され、リージョン固定SKUの提供が無いことがある（Azure側の仕様。今回のモデル・リージョンの組み合わせ固有）
- **対処・回避方法**: `azurerm_cognitive_deployment`のsku.nameを`GlobalStandard`に変更して実装。`GlobalStandard`はリクエストが（Azureが管理する）他リージョンにルーティングされる可能性がある仕様のため、Japan Eastを選んでもリクエスト処理が同リージョン内に閉じるとは限らない点に留意（今回は合成テストデータのみを扱うデモのため実害なしと判断、影響なしとして進行）

## 2026-09-01 azuread_application と azuread_application_identifier_uri がidentifier_urisを取り合う
- **何を期待していたか**: `azuread_application_identifier_uri`（別リソース）でidentifier_urisを設定すれば、`azuread_application`本体側は関与せず安定する想定だった
- **実際どうだったか**: Azure OpenAI用のTerraformを追加した後の`terraform plan`で、既に適用済みのはずの`azuread_application.middle_tier`/`downstream_api`が「更新」対象として現れ、`identifier_uris`を空に戻そうとする差分が出た（`azuread_application`のconfigにidentifier_urisを書いていないため「設定なし＝空にすべき」と誤認）
- **原因**: `azuread_application`リソースの`identifier_uris`属性はoptional+computedであり、別リソースが外部から設定した値をrefreshで検知しても、configで明示されていなければ「意図した状態=空」とみなして差分を出す（両リソースが同じ属性の所有権を取り合う既知の設計上の癖）
- **対処・回避方法**: `azuread_application.middle_tier`/`downstream_api`双方に`lifecycle { ignore_changes = [identifier_uris] }`を追加し、`azuread_application`側にこの属性の管理を諦めさせた。`terraform apply`前の`terraform plan`で検知できたため実害なし

## 2026-09-01 Azure OpenAI: gpt-4o-miniがJapan Eastで新規デプロイ不可（lifecycleStatus: Deprecating）
- **何を期待していたか**: 事前に`az rest`でモデル一覧を確認しSKU（GlobalStandard）の存在は確認済みだったため、`terraform apply`でそのままデプロイできる想定だった
- **実際どうだったか**: `azurerm_cognitive_deployment`作成時に`ServiceModelDeprecating: The model 'Format:OpenAI,Name:gpt-4o-mini,Version:2024-07-18' is in deprecating state and cannot be used for new deployments.`（400）で失敗。改めてモデル一覧の`lifecycleStatus`フィールドを見るとgpt-4o-miniは`Deprecating`（実際の`deprecation.inference`日付は2027-04-14と先だが、新規デプロイ自体は日付を待たず既に不可）だった
- **原因**: 環境の現在日時（2026-09-01）がClaudeの学習データのカットオフ（2026年1月）より後であり、モデルカタログがカットオフ後に大きく更新されていた（gpt-4o-mini/gpt-4.1系はLegacy、gpt-5系が主流に）。事前確認時は`skus`フィールドのみ見て`lifecycleStatus`を見落としていた
- **対処・回避方法**: モデル一覧を`lifecycleStatus!=Deprecating`かつ`chatCompletion=true`で絞り込み、mini/nanoティアの代替候補をユーザーに提示。`gpt-5.4-mini`（2026-03-17、GenerallyAvailable）へのユーザー確認済み変更で解消
- **教訓**: Azure OpenAIのようにカタログが頻繁に更新されるサービスでは、モデル選定時に`skus`の有無だけでなく`lifecycleStatus`も必ず確認する

## 2026-09-01 Azure OpenAI: gpt-5.4-miniはこのサブスクリプションでクォータ0
- **何を期待していたか**: `lifecycleStatus: GenerallyAvailable`かつSKU一覧に`GlobalStandard`があったため、そのままデプロイできる想定だった
- **実際どうだったか**: `azurerm_cognitive_deployment`作成時に`InsufficientQuota: ...current available capacity 0...quota limit is 0`（400）で失敗
- **原因**: モデルがリージョンで提供されていること（`lifecycleStatus`/`skus`）と、このサブスクリプションに既定クォータが割り当てられていること（`.../locations/{region}/usages`のlimitフィールド）は別軸。新しいモデルほど既定クォータが未割当（0）なことがある
- **対処・回避方法**: `az rest .../usages`でlimit>0のモデルを確認したところ`OpenAI.GlobalStandard.gpt-5-mini`（limit=500）に既定クォータがあることが判明。ユーザー確認の上gpt-5-miniへ変更
- **教訓**: モデル選定時は`models`（提供有無）に加えて`usages`（実際に使えるクォータ）も確認する

## 2026-09-01 Kong: `proxy_listen`はRoute単位でポートを分離できない
- **何を期待していたか**: `docs/design-brief.md`の「LLM/MCP RouteはDocker Composeの内部専用ネットワークで保護する」という記述から、Kongの`proxy_listen`に複数ポートを設定し、一部だけをdocker-composeでhost公開すれば、そのポート専用のRouteだけが外部到達不可になる想定だった
- **実際どうだったか**: `kong-ee/kong/templates/nginx_kong.lua`を確認すると、全`proxy_listen`エントリは単一のnginx `server {}`ブロックが複数`listen`ディレクティブを持つ構成であり、Route/ServiceはどのポートからのリクエストかによらずKong全体で同一に評価される。Route側に「このポートのみ」という紐付けフィールドも存在しない
- **原因**: Kong OSS/EEの設計上、ポートとRouteの紐付けという概念自体が無い（不明ではなく、実装上そもそも存在しない機能）
- **対処・回避方法**: 利用者に3つの実現方式（Kong複数インスタンス化／`ip-restriction`プラグイン／ポート非公開のみの簡易対応）を提示し確認を取った。詳細と採用した選択肢は[ADR-0002](./decisions/0002-mcp-llm-route-network-isolation.md)参照

## 2026-09-01 decKの環境変数テンプレート構文は`DECK_`プレフィックス必須
- **何を期待していたか**: `${{ env "変数名" }}`構文で任意の環境変数名を参照できると想定していた
- **実際どうだったか**: 調査の結果、decK（`go-database-reconciler`）の実装は環境変数名に`DECK_`プレフィックスを強制しており、それ以外の名前ではエラーになることが判明（`kong/mcp-route.yaml`・`kong/llm-route.yaml`内の変数名は全て`DECK_`始まりで統一済み）
- **原因**: decK側の仕様（`getPrefixedEnvVar`）
- **対処・回避方法**: `kong-mcp-testbed`の実例（`DECK_AUTH0_ISSUER`等）でも同じ命名規則だったことを確認し、本リポジトリでも踏襲した

## 2026-09-01 【解決・実機確認済み】未検証のまま実装していた値（`deck gateway sync`実行前の懸念点）
以下は実装当初、`kong-ee`のスキーマ定義から妥当と判断したが実機未確認だった項目。利用者からKong Enterpriseライセンスの提供を受け、実際に`docker compose up`→`deck gateway sync`→Playwrightによる実ブラウザ操作で全て確認できた:
- ✅ `openid-connect`の`subject_token_issuers[].issuer`（`https://login.microsoftonline.com/{tenant}/v2.0`）は実際のBearerトークンの`iss`クレームと一致し、OBOトークン交換が成功した
- ✅ `ai-proxy-advanced`の`model.options.azure_api_version`（`2024-10-21`）は`gpt-5-mini`デプロイに対して有効で、実際にAzure OpenAIから応答を得られた
- ✅ `kong/login-route.yaml`の`upstream_headers`（`path: [name]`/`path: [preferred_username]`）はEntra IDの実際のid_tokenクレーム名と一致し、画面上部に正しくユーザー名・メールが表示された
- ✅ セッションcookieによる再認証時も`upstream_access_token_header`が正しくアクセストークンをNext.jsへ転送し続けることを確認（複数回のチャット送信で毎回MCP Routeへの再提示に成功）
- ✅ `createMCPClient`の`transport.type: "http"`（Streamable HTTPトランスポート）で`ai-mcp-proxy`（`conversion-listener`モード）に接続できることを確認（`initialize`→`notifications/initialized`→`tools/list`→`tools/call`の一連のJSON-RPCが正常に機能）

## 2026-09-01 openid-connect: セッション管理は`auth_methods`に明示的に`session`を含めないと有効にならない
- **何を期待していたか**: `session_secret`等の`session_*`系フィールドを設定しさえすれば、`authorization_code`ログイン後のセッションcookie発行・検証は自動的に有効になると想定していた
- **実際どうだったか**: `kong-ee/kong/plugins/openid-connect/handler.lua`を確認すると、`auth_methods`配列に`session`を明示的に含めない限りセッションcookieの読み取り自体が試行されない（`session_*`設定があっても無関係）。`kong/login-route.yaml`では`auth_methods: [authorization_code, session]`と両方を指定済み
- **原因**: `session`はセッションストレージ設定とは独立した、他のgrant種別（`bearer`等）と同格の認証方式選択肢として実装されている（設計上の仕様）
- **対処・回避方法**: `auth_methods`に`session`を含めることを確認した上で実装。実機での動作（cookie発行・次回リクエストでの再利用）は未検証（本ログ内「未検証のまま実装した値」参照）

## 2026-09-01 ai-proxy-advanced: リクエストの`model`フィールドは検証され、設定と不一致だと400になる
- **何を期待していたか**: design-brief検証方法9番目の要件（エージェントがAzure OpenAI固有の設定を一切持たない）を満たすため、単一ターゲット構成なら`model`フィールドを省略するかどうでもいい値を送ってもKongが常に設定済みターゲットへルーティングしてくれると想定していた
- **実際どうだったか**: `kong-ee/kong/llm/plugin/shared-filters/normalize-request.lua`（187-206行）を確認すると、クライアントの`model`が空でも`config.targets[].model.name`とも`model_alias`とも一致しない非空文字列の場合`400 "cannot use own model - must be: <model_t.name>"`を返す。一方、Vercel AI SDKの`@ai-sdk/openai`は`.chat(modelId)`実行時に必ず具体的な文字列を`model`として送信する仕様のため、「何も送らない」選択肢はSDK都合で取れなかった
- **原因**: `ai-proxy-advanced`はクライアントが誤って別モデルを指定していないかを検証する仕様（`kong-ee/kong/llm/schemas/init.lua`213-216行の`model_alias`フィールドが、この検証を回避しつつ実際のモデル名を隠すための正規の抜け道として用意されている）
- **対処・回避方法**: `kong/llm-route.yaml`の`model.model_alias`に固定値`kong-demo-llm`を設定し、エージェント側は常にこの値のみを送信するよう実装（`services/chat-ui/src/app/api/chat/route.ts`）。これによりAzureのデプロイ名等はエージェント側から完全に隠蔽されたまま要件を満たせる

## 2026-09-01 ai-proxy-advanced: `config.logging`はtargets[]要素の中に置く必要がある（実機`deck gateway validate`で発覚）
- **何を期待していたか**: `kong-ee/spec-ee`の一部抜粋から、`logging`（`log_statistics`/`log_payloads`）は`config`直下のフィールドだと判断していた
- **実際どうだったか**: 実際のKong（`kong/kong-gateway-dev:pr-21082-ubuntu`）に対して`deck gateway validate`を実行したところ`schema violation (config.logging: unknown field)`で失敗
- **原因**: `kong-ee/kong/plugins/ai-proxy-advanced/schema.lua:270`（`target.logging.log_payloads`参照）で確認した通り、`logging`は`config.targets[]`の各要素の中のフィールドだった（`config`直下ではない）
- **対処・回避方法**: `kong/llm-route.yaml`の`logging`を`targets[0]`の中へ移動。修正後`deck gateway validate`成功

## 2026-09-01 Docker Compose起動・実機`deck gateway sync`・E2E動作確認（design-brief 5節の検証方法）
利用者からKong Enterpriseライセンス（`.env`の`KONG_LICENSE_DATA`）の提供を受け、`docker compose up -d`→`deck gateway sync`→Playwright（実ブラウザ操作）による実地検証を実施。

- **ライセンス状態**: Kongログに`Your license is expired. You have 18 days left in the renewal grace period.`と出力される。grace period中のためEnterprise機能（openid-connect/ai-mcp-proxy/ai-proxy-advanced）は問題なく動作した（実際に以下の検証で確認）。18日以内に本番相当の検証を行う場合は要更新
- **確認できたこと（design-brief 5節テストケース）**:
  - ✅ AIエージェント未割当ユーザー（`demo-no-agent-access`）: Entra IDが`AADSTS50105`でログイン自体を拒否（Kong側の実装は無関係、想定通り）
  - ✅ 割当済み2ユーザーのログイン・画面上部のユーザー名/メール表示: `upstream_headers`（`path: [name]`/`path: [preferred_username]`）が実際のid_tokenクレームと一致し正しく表示された（未検証項目としていた懸念は解消）
  - ✅ ログアウト: ログアウトボタン→Entra IDのサインアウト画面→再度ログインが必要になることを確認（セッションが実際にクリアされたことの間接証跡）
  - ✅ ACL: `demo-inquiry-only`ユーザーはMCPの`tools/list`に`customer_inquiry`のみ表示され、`customer_details`を直接`tools/call`すると**403 Forbidden**。`demo-both-apis`ユーザーは両方のToolが`tools/list`に表示され、`customer_details`も許可（ACL 403にならない）。OBOトークン交換＋`groups`クレームによるACL評価が実機で正しく機能することを確認
  - ✅ `ai-proxy-advanced`経由のLLM呼び出し自体は成功（Chat UIから自然文で応答が返る）。エージェント側は`model: "kong-demo-llm"`固定値のみ送信し、Azure固有設定は一切持たない
- **当初未解決だった問題2件（下記2エントリ）は、同セッション内でいずれも原因特定・修正・再検証まで完了した**

## 2026-09-01 【解決済み】Kong: `openid-connect`のログイン/ログアウトコールバックが`login_action: upstream`のためNext.js側に404で着地する
- **何を期待していたか**: Entra IDからの`/login/callback`・`/logout/callback`リダイレクト後、Kongが認証完了を検知してブラウザを`/`等の実在パスへ送り届けてくれると想定していた
- **実際どうだったか**: `openid-connect`の`login_action`はデフォルト`upstream`（design-brief上「認可コードフロー」としか書いておらず値自体は未指定だったため既定値を使用）。このモードでは認証完了後もコールバックの**リクエストパス自体（`/login/callback`等）がそのままNext.jsへ転送される**。Next.js側に該当パスの実装が無いため実際に404が表示された（ただしセッションcookie自体は正しく発行されており、その後`/`へ手動遷移すればログイン状態は維持されていることを確認した＝機能的には成功、UXの見た目が悪いだけ）
- **原因**: `login_action: upstream`の仕様上の挙動（`kong-ee/kong/plugins/openid-connect/schema.lua:2073-2083`）
- **対処・回避方法**: `services/chat-ui/src/app/login/callback/route.ts`・`.../logout/callback/route.ts`を追加し、`/`へ303リダイレクトするだけの薄いRoute Handlerを実装。実機（Playwright操作）で再検証し、ログイン・ログアウトとも404を経由せず`/`へシームレスに遷移することを確認した

## 2026-09-01 【解決済み】ai-mcp-proxy(conversion-listener)のtools/callが実データを返さない（isError:false・content空）
- **何を期待していたか**: ACLが許可された`tools/call`（`customer_inquiry`/`customer_details`）は、demo-apiの実データをMCPレスポンスのcontentに含めて返すと想定していた
- **実際どうだったか**: ACL評価自体は完全に正しく動作（403/200の出し分けは設計通り）。しかしACLが許可されるケースでも、レスポンスは常に`{"isError":false,"content":[{"type":"text","text":""}]}`（空）。Kongのアクセスログを見ると、`ai-mcp-proxy`がツール実行のため内部的に発行する自己完結HTTPリクエスト（`kong/plugins/ai-mcp-proxy/tools.lua`の`send_http_call`、Kong専用unixソケット`KONG_AI_MCP_SOCK`経由）が、意図した`demo-api`への到達ではなく**302（空ボディ）**を返している
- **原因（調査済み・確定）**: `send_http_call`はKongの共有nginx server blockを再度介する自己リクエストであり（`kong-ee/kong/templates/nginx_kong.lua:153`、`ai_mcp_listener_enabled`のunixソケットは公開TCPポートと**同一**server block内）、Kongの通常のRoute/Serviceルーターを再度通過する。`kong/mcp-route.yaml`のTool定義で`path: /customers`のように**絶対パス**を指定すると、`resolve_final_path`（`kong-ee/kong/plugins/ai-mcp-proxy/tools.lua:72-110`）が元のRouteのパス（`/mcp/customers`）を無視して`/customers`のみで自己リクエストを組み立てる。この結果、自己リクエストは`mcp-customers` Routeにマッチせず、`paths: ["/"]`で無関係にキャッチオールしている`kong/login-route.yaml`の`chat-ui` Routeに落ち、その`openid-connect`（`auth_methods: [authorization_code, session]`）が未認証と判定し302リダイレクトを返す。`send_http_call`は`status >= 400`のみエラー扱いのため302は「成功」として処理され、空ボディがそのままcontentになる（`tools.lua`の`convert_resp_as_tool_call_result`はstatusを見ずcontentへ素通しする）
- **検討した対処案とセキュリティ上の懸念**: 単純に「`/customers`にマッチする無認証Routeを追加する」対処は、この自己リクエスト用unixソケットが公開TCPポート（8000）と**同一のnginx server block・同一Routerテーブル**を共有するため、外部から`Host: demo-api`ヘッダーを偽装した通常のTCPリクエストでも同じRouteにマッチしてしまい、OIDC/OBO/ACLを完全にバイパスする経路になる懸念があった。この案は採用せず、より安全な下記の対処を採用した
- **対処・回避方法（採用）**: Tool定義の`path`を**絶対パス（`/customers`）から相対パス（`customers`）に変更**。`resolve_final_path`は相対パスの場合、元Routeのパス（`/mcp/customers`）と結合するため、自己リクエストは`mcp-customers` Route自身に正しく着地する。この時、`openid-connect`のOBOトークン交換（`token_exchange`）が書き込んだ`Authorization: Bearer <交換後トークン>`ヘッダー（`upstream_access_token_header`デフォルト`authorization:bearer`によりKongが`ngx.req.set_header`でライブのリクエストオブジェクトを直接書き換え済み、かつ`ai-mcp-proxy`の`forward_client_headers`は既定`true`）がそのまま自己リクエストにも引き継がれるため、Routeへ再度着地した際の認証は「バイパス」ではなく、有効な（実際にOBO交換済みで対象APIのaudienceを持つ）トークンによる**正規の再認証**として通る。新規Routeの追加は不要で、認証バイパスの懸念も生じない
- **検証結果**: 修正後`deck gateway sync`し、実際のトークンで`tools/call`を直接叩いて確認: `customer_inquiry`（都道府県のみ／都道府県+性別のAND条件）・`customer_details`とも実データが返ることを確認。ACL（inquiry_onlyユーザーの`customer_details`が403のまま）も修正前と変わらず正しく機能。Chat UI経由でも「東京都在住の女性を検索して、見つかった顧客の詳細情報も教えて」という自然文プロンプトに対し、LLMが`customer_inquiry`→`customer_details`の順でToolを実行し、demo-apiの実データ（氏名・年齢・マイナンバー・住所等）と完全に一致する正確な回答を生成することを確認した（design-brief 5節の複数テストケースがこれで実地確認できた）

## 2026-09-01 デモAPI: テストデータ生成方法の記録
CLAUDE.md「セキュリティ・クラウド認証」の要求に基づく記録。`services/demo-api/src/data.ts`の100人分の顧客データ（マイナンバーを模した12桁の値を含む）は、固定シード（42）のmulberry32擬似乱数生成器のみから機械的に組み立てた完全な架空データ。実在の人物・実在の番号を一切参照していない。氏名は姓・名それぞれ10種の一般的な単語からの組み合わせ、マイナンバー相当値は12桁の乱数文字列（チェックデジット等の実仕様は再現していない）。

## 2026-09-20 07:48 JST `gh pr merge --delete-branch`がローカルブランチ削除だけ失敗
- **何を期待していたか**: PR #14をsquash mergeし、リモート・ローカルの作業ブランチも後処理として削除できること
- **実際どうだったか**（エラーメッセージ・症状を具体的に）: PRは正常にマージされたが、`failed to delete local branch docs/konnect-update-design-brief: ... used by worktree .../kong-azure-obo-demo-konnect-update`でコマンドが非ゼロ終了した
- **原因**: `docs/konnect-update-design-brief`ブランチが別worktreeでcheckout中のため、Gitがローカルブランチ削除を拒否した
- **対処・回避方法**: `gh pr view 14`でPRの`MERGED`状態とmerge commit `a79371b350c9490c59e94450b92f94617b21deca`を確認した。別worktreeとローカルブランチは破壊せず保持し、実装は更新後の`main`を基点とする

## 2026-09-20 07:52 JST sandbox内からDocker socketへ接続できない
- **何を期待していたか**: `docker image inspect kong/kong-gateway:3.16.0.0`で対象イメージのローカル有無をread-only確認できること
- **実際どうだったか**（エラーメッセージ・症状を具体的に）: `permission denied while trying to connect to the docker API at unix:///Users/shinichi.hashitanikonghq.com/.docker/run/docker.sock`で失敗した
- **原因**: Codex sandboxからユーザーのDocker socketへのアクセスが許可されていないため
- **対処・回避方法**: Docker操作自体の失敗とは判断せず、同じread-onlyコマンドをsandbox外の承認済み実行として再試行する

## 2026-09-20 07:54 JST `TESTING.md`にテストアカウントの平文パスワードが残存
- **何を期待していたか**: 認証情報がコード・文書・commit履歴へ平文保存されていないこと
- **実際どうだったか**（エラーメッセージ・症状を具体的に）: `TESTING.md`のテストユーザー表に、Entra IDデモアカウント3件のパスワードが平文で記載されていた
- **原因**: 初回実機検証時の操作手順へ認証情報を直接記載していたため
- **対処・回避方法**: 現在の文書から値を除去し、安全な保管先から取得する表記へ変更した。既存commit履歴には残るため、対象パスワードのローテーションは別途必要

## 2026-09-20 07:55 JST ローカル環境に`gitleaks`が未導入
- **何を期待していたか**: `gitleaks`で現在の作業ツリーに対するsecret scanを実行できること
- **実際どうだったか**（エラーメッセージ・症状を具体的に）: `gitleaks version`が`No such file or directory`で失敗した
- **原因**: ローカル環境に`gitleaks`実行ファイルがインストールされていないため
- **対処・回避方法**: 今回はリポジトリ内の既知secret名・旧credential記載箇所を直接検索し、差分レビューで平文値が追加されていないことを確認する。専用scanner導入は本PRのスコープ外

## 2026-09-20 07:57 JST sandbox内でTerraform provider schemaを読み込めない
- **何を期待していたか**: `terraform -chdir=terraform validate`で既存Terraform構成の妥当性を確認できること
- **実際どうだったか**（エラーメッセージ・症状を具体的に）: `azuread`、`azurerm`、`random`の各providerで`Unrecognized remote plugin message`と`Failed to read any lines from plugin's stdout`が発生した。provider binaryのarchitecture・permission自体は正しかった
- **原因**: Codex sandbox内でTerraform provider subprocessの起動またはplugin handshakeが制限された可能性が高い
- **対処・回避方法**: 構成エラーとは判断せず、同じvalidateをsandbox外の承認済み実行として再試行する

## 2026-09-20 07:57 JST Terraform planが既存デモを認識せず26件すべてを新規作成予定
- **何を期待していたか**: 既存Azure/EntraリソースとTerraform stateが対応し、今回のCompose変更に伴うTerraform差分がないこと
- **実際どうだったか**（エラーメッセージ・症状を具体的に）: `terraform -chdir=terraform plan`が`Plan: 26 to add, 0 to change, 0 to destroy`を返した。`terraform/terraform.tfstate`とrepository rootの`terraform.tfstate`はいずれも約180 bytesで、`terraform state list`は空だった
- **原因**: 現在ローカルにあるTerraform stateが空で、過去に作成したAzure/Entraリソースとのstate対応が失われているか、別のstate保存先を使っていた可能性がある
- **対処・回避方法**: `terraform apply`は実行しない。既存resourceの所在と正しいstateを確認し、必要ならimport/recovery方針を別途決めるまでTerraformによる変更を禁止する

## 2026-09-20 07:59 JST sandbox内でGit index lockを作成できない
- **何を期待していたか**: 変更対象を明示した`git add`で6ファイルだけをstageできること
- **実際どうだったか**（エラーメッセージ・症状を具体的に）: `.git/index.lock: Operation not permitted`でstage前に失敗した
- **原因**: Codex sandboxではrepositoryの`.git`配下への書き込みが許可されていないため
- **対処・回避方法**: 対象pathを明示した同じ`git add`をsandbox外の承認済み実行として再試行する。未追跡の`AGENTS.md`はstage対象に含めない

## 2026-09-20 08:16 JST Konnect bootstrap入力とテストユーザーpassword lifecycleを確定
- **確認結果**: Konnectの既存Control Plane 162件はすべてUS geoで、`azure-obo-demo`という同名CPは存在しなかった。新規CP名は`azure-obo-demo`、geoはUS（North America）とする
- **password lifecycle**: テストユーザーのpasswordはTerraformの`random_password.test_user`が作成時に生成し、sensitive outputとしてのみ参照する。ユーザーをデモごとに作成・destroyする運用では再作成時に新しい値となる
- **対処・運用方針**: passwordを文書へ平文保存しない。通常のデモサイクル外のローテーションは利用者の明示指示なしに実行しない。既存stateが空の問題は別途解消が必要

## 2026-09-20 08:17 JST `gh pr edit`がProjects Classic関連GraphQLエラーで失敗
- **何を期待していたか**: PR #15の本文を、確定したUS geo・Control Plane名・password運用へ更新できること
- **実際どうだったか**（エラーメッセージ・症状を具体的に）: `GraphQL: Projects (classic) is being deprecated in favor of the new Projects experience`で本文更新前に失敗した
- **原因**: `gh pr edit`がPR本文編集と無関係なProjects ClassicのGraphQL fieldも取得し、GitHub側の廃止仕様に当たったため
- **対処・回避方法**: Pull Requests REST APIのPATCHへ切り替え、本文のみを更新する

## 2026-09-20 08:20 JST Konnect MCPが対象外Organizationを参照していた
- **何を期待していたか**: 利用者指定の対象Org `hashi-sandbox`についてControl Plane一覧とgeoを確認できること
- **実際どうだったか**（エラーメッセージ・症状を具体的に）: `get_organizations_me`で、現在のKonnect MCPが`Kong Inc. - SE Team`（login path `se-kong`）を参照していることが判明した。08:16の「162 CPは全てUS、同名CPなし」という確認はこの別Orgに対する結果だった
- **原因**: live stateを読む前にMCP credentialのOrganization scopeを確認しなかったため
- **対処・回避方法**: 08:16の結果を対象Orgの証跡として使用しない。設計文書は利用者指定の`hashi-sandbox`へ訂正し、同名CP有無・endpoint・IDは対象Orgへ認証した後に再確認する

## 2026-09-20 08:20 JST `kongctl`で対象Organizationを代替確認できない
- **何を期待していたか**: `kongctl get organization`と`kongctl get me`で、MCPとは別に現在のOrganization scopeをread-only確認できること
- **実際どうだったか**（エラーメッセージ・症状を具体的に）: sandbox内では`~/.config/kongctl/logs/kongctl.log: operation not permitted`、sandbox外では`authentication token not available`で停止した
- **原因**: sandboxのログ書込制約に加え、ローカル`kongctl`にPATまたはlogin sessionが設定されていないため
- **対処・回避方法**: `hashi-sandbox`用credentialを明示的に接続するまで、`kongctl`からのlive確認・変更は行わない

## 2026-09-20 08:37 JST 最初に開いたChromeプロファイルが対象Konnect Organizationへ参加していなかった
- **何を期待していたか**: 既存のKonnect Organization `hashi-sandbox`へログインし、Control Planeを確認できること
- **実際どうだったか**（エラーメッセージ・症状を具体的に）: 最初のChromeプロファイルでは既存Orgではなく新規Organization作成画面が表示された。利用者が開いた仕事用Chromeプロファイルへ切り替えると、USリージョンの`hashi-sandbox`と既存Control Plane 20件を確認できた
- **原因**: 最初に使ったChromeプロファイルのGoogle identityが`hashi-sandbox`へ所属していなかったため
- **対処・回避方法**: Konnect UIの変更前に、ヘッダーのOrganization名とURLのgeoを必ず確認する。今回は`hashi-sandbox`かつ`/us/`を確認した後、対象名`azure-obo-demo`が存在しないことをUI検索で再確認した

## 2026-09-20 08:46 JST Chrome UIの作成フォームを閉じる操作前にComputer Use sessionが解除された
- **何を期待していたか**: Terraform管理へ切り替えるため、未送信のKonnect Control Plane作成フォームをCancelできること
- **実際どうだったか**（エラーメッセージ・症状を具体的に）: 最初のCancel操作は、Chromeに対するComputer Useがactiveでないため画面状態を再取得するよう要求され、操作されなかった
- **原因**: 利用者の追加指示を挟んだ時点で、Chrome UI操作sessionのactive stateが解除されていた
- **対処・回避方法**: 画面状態を再取得してフォーム内容が未送信であることを確認し、その後Cancelを実行した。Control PlaneはUIから作成されていない

## 2026-09-20 08:48 JST sandbox内の`terraform init`がTerraform Registryの名前解決に失敗
- **何を期待していたか**: `terraform/konnect/`で公式`kong/konnect`、`hashicorp/tls`、`hashicorp/local` providerを取得し、lock fileを生成できること
- **実際どうだったか**（エラーメッセージ・症状を具体的に）: `registry.terraform.io`のdiscovery document取得時に`dial tcp: lookup registry.terraform.io: no such host`となり、3 providerすべてのversion queryが失敗した
- **原因**: Codex sandboxのnetwork/DNS制限
- **対処・回避方法**: provider構成エラーとは判断せず、同じ`terraform init`をsandbox外の承認済み実行として再試行する

## 2026-09-20 08:49 JST sandbox内でKonnect rootのprovider schemaを読み込めない
- **何を期待していたか**: `terraform/konnect/`で`terraform validate`と`terraform providers schema -json`を実行できること
- **実際どうだったか**（エラーメッセージ・症状を具体的に）: `konnect`、`tls`、`local`の全providerで`Unrecognized remote plugin message`と`Failed to read any lines from plugin's stdout`が発生した。provider binaryのarchitecture・permissionは正しかった
- **原因**: 既存Azure rootで確認済みの事象と同じく、Codex sandboxがTerraform provider subprocessの起動またはplugin handshakeを制限している可能性が高い
- **対処・回避方法**: HCLエラーとは判断せず、validateとschema inspectionをsandbox外の承認済み実行として再試行する

## 2026-09-20 08:51 JST local Terraform stateが秘密鍵を含む状態でmode `0644`になった
- **何を期待していたか**: Data Plane private keyを含む`terraform/konnect/terraform.tfstate`がownerのみ読み書き可能なpermissionで作成されること
- **実際どうだったか**（エラーメッセージ・症状を具体的に）: apply後のstateはmode `0644`で、同一端末の他ユーザーから読み取り可能な設定だった。生成した`tls.crt`と`tls.key`自体は指定どおり`0600`だった
- **原因**: local backendがstate fileを既定のprocess umaskに従って作成し、HCLからfile permissionを指定できないため
- **対処・回避方法**: stateを直ちに`chmod 600`へ変更した。stateはgitignore対象のまま維持し、apply後にpermissionを確認する手順をREADMEへ明記する

## 2026-09-20 08:53 JST sandbox内からDocker socketへ接続できない
- **何を期待していたか**: Terraform生成のCompose env fragmentを使い、現在のData Plane稼働状態を`docker compose ps`でread-only確認できること
- **実際どうだったか**（エラーメッセージ・症状を具体的に）: `permission denied while trying to connect to the docker API`でDocker socketへの接続が拒否された
- **原因**: Codex sandboxからユーザーのDocker Desktop socketへのアクセスが制限されているため
- **対処・回避方法**: Compose構成の展開確認はsandbox内で完了済み。稼働確認・起動は同じenv file指定でsandbox外の承認済み実行として行う

## 2026-09-20 08:57 JST Azure/Entraの有効なbackup stateを発見
- **何を期待していたか**: 空になっている`terraform/terraform.tfstate`に対応するstate recovery元を特定できること
- **実際どうだったか**（エラーメッセージ・症状を具体的に）: `terraform/terraform.tfstate.backup`は現在stateと同じlineageで、serial 94、28 resource address、必要なsensitive outputを保持していた。現在stateはserial 124だがresource/outputが空。backupを明示したplanは`No changes`だった
- **原因**: 過去のTerraform操作で空stateが現在stateとして保存された一方、その直前の有効stateが自動backupに残っていた
- **対処・回避方法**: backupは現在HCLとの整合性が確認できた。ただし`-state` flagはdeprecated warningを出すため恒久運用には使用しない。現在の空stateを退避した上で、利用者承認後に`terraform state push -force`でbackupを正式stateへ復旧し、通常planでlive refreshを確認する

## 2026-09-20 09:04 JST backup stateは復旧元ではなくdestroy前のstale stateだった
- **何を期待していたか**: backup stateを正式stateへpushした後の通常planで、Azure/Entra実体とstateが一致して`No changes`になること
- **実際どうだったか**（エラーメッセージ・症状を具体的に）: live refreshによりApp Registration、Service Principal、Security Group、test user、Azure OpenAI、resource group等が実体側で削除済みと判明し、planは`23 to add, 0 to change, 0 to destroy`を提示した。`-refresh=false`での事前planはstateとHCLの一致しか確認せず、live resourceの存在を証明していなかった
- **原因**: 空stateは破損ではなく過去の`terraform destroy`後の正しい状態で、`.backup`はdestroy直前のstateだった可能性が高い
- **対処・回避方法**: applyは実行しない。事前退避したserial 124の空stateを直ちに正式stateへ戻す。今後、backup stateの復旧可否は必ずlive refresh結果で判断し、`-refresh=false`の結果だけを根拠にしない

## 2026-09-20 09:07 JST RTKのfiltered `git diff --cached --check`が診断を表示しなかった
- **何を期待していたか**: staged差分のwhitespace checkで、問題があれば対象file/lineが表示されること
- **実際どうだったか**（エラーメッセージ・症状を具体的に）: 通常のRTK経由ではoutputなしのexit 2となった。`rtk proxy`でunfiltered実行すると、Terraform 3 fileのEOFに余分な空行があることを確認できた
- **原因**: RTKの`git diff` output filterが`--cached --check`の診断を抑制したため
- **対処・回避方法**: 対象3 fileの余分なEOF空行を除去した。staged whitespace checkは結果が不明瞭な場合に`rtk proxy git diff --cached --check`で再確認する

## 2026-09-20 09:08 JST sandbox内からGitHub APIへ接続できない
- **何を期待していたか**: PR #15の現在本文を取得し、Terraform実装とlive検証結果へ更新できること
- **実際どうだったか**（エラーメッセージ・症状を具体的に）: `gh pr view`が`error connecting to api.github.com`で失敗した
- **原因**: Codex sandboxのnetwork制限
- **対処・回避方法**: 同じread/update操作をsandbox外の承認済み実行として再試行する

## 2026-09-20 09:40 JST sandbox内でAzure/Entra rootのprovider schemaを読み込めない
- **何を期待していたか**: `terraform/`で、追加した`local` providerを含む構成を`terraform validate`できること
- **実際どうだったか**（エラーメッセージ・症状を具体的に）: `azuread`、`azurerm`、`local`、`random`の全providerで`Unrecognized remote plugin message`と`Failed to read any lines from plugin's stdout`が発生した。provider binaryのarchitecture・permissionは正しかった
- **原因**: 新規`local` provider固有ではなく全providerが同じ症状のため、Codex sandboxがTerraform provider subprocessの起動またはplugin handshakeを制限している可能性が高い
- **対処・回避方法**: HCLまたはproviderの不具合とは判断せず、同じvalidateをsandbox外の承認済み実行として再試行し、`Success! The configuration is valid.`を確認した
