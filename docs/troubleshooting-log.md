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

## 2026-09-01 未検証のまま実装した値（`deck gateway sync`実行前に要確認）
`kong/`配下のdecK state fileは、Kong/Azure OpenAIの現物環境に対してまだ一度も`deck gateway sync`していない（Kong Enterpriseライセンスが必要な操作のため、実際の起動・同期は利用者確認後に行う）。以下は`kong-ee`のスキーマ定義から妥当と判断したが、実機での動作は未確認:
- `openid-connect`の`subject_token_issuers[].issuer`に設定した`https://login.microsoftonline.com/{tenant}/v2.0`形式が、実際にEntra IDが発行するBearerトークンの`iss`クレームと一致するか
- `ai-proxy-advanced`の`model.options.azure_api_version`に設定した`2024-10-21`が、`terraform/azure_openai.tf`でデプロイした`gpt-5-mini`（2026-09時点の新しいモデル）に対して有効なAPIバージョンか
- `deck gateway validate`/`deck gateway diff`自体を、対象の`kong/kong-gateway-dev:pr-21082-ubuntu`イメージに対してまだ実行できていない（Docker Compose起動にはKong Enterpriseライセンスが必要なため、利用者確認後の次ステップとする）
- `kong/login-route.yaml`の`upstream_headers`（`path: [name]`/`path: [preferred_username]`）が、Entra IDの実際のid_token/userinfoレスポンスのクレーム名と一致するか（`preferred_username`ではなく`email`/`upn`にすべき可能性がある）
- Route 1（`login-route.yaml`）でセッションcookieにより再認証した場合でも、`upstream_access_token_header`（デフォルト`authorization:bearer`）が最初のログイン時と同じアクセストークンをNext.jsへ転送し続けるか（`openid-connect`のセッションストレージ実装依存。セッションが有効な間、Next.js側の`/api/chat`がKongのMCP Routeへ再提示できるトークンを毎回受け取れることが前提）
- `services/chat-ui/src/app/api/chat/route.ts`の`createMCPClient`が`transport.type: "http"`（Streamable HTTPトランスポート）で`ai-mcp-proxy`（`conversion-listener`モード）に接続できるか。`ai-mcp-proxy`側の実際のトランスポート実装は未確認

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

## 2026-09-01 デモAPI: テストデータ生成方法の記録
CLAUDE.md「セキュリティ・クラウド認証」の要求に基づく記録。`services/demo-api/src/data.ts`の100人分の顧客データ（マイナンバーを模した12桁の値を含む）は、固定シード（42）のmulberry32擬似乱数生成器のみから機械的に組み立てた完全な架空データ。実在の人物・実在の番号を一切参照していない。氏名は姓・名それぞれ10種の一般的な単語からの組み合わせ、マイナンバー相当値は12桁の乱数文字列（チェックデジット等の実仕様は再現していない）。
