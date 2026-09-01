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
