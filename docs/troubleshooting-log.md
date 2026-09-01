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
