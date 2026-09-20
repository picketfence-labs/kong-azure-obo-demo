# ADR-0004: decK用セッションシークレットをTerraformで管理する

- **日付**: 2026-09-20
- **状態**: 決定

## コンテキスト
`openid-connect`プラグインの`session_secret`はKongのセッションcookie署名に使うため、decKのvalidate/diffだけでなく実環境へのsyncでも安定した値が必要である。従来のREADMEは`openssl rand`で実行ごとに生成する例だったため、値を保存し忘れると再syncで既存セッションが無効になる。

利用者から、認証情報を含む作業も原則Terraformで管理し、指示がない限りローテーションしない方針が示された。既存のAzure/Entra ID Terraform rootは、decKが参照するclient secret、group ID、Azure OpenAI API keyも所有している。

## 検討した選択肢

### 1. 手動生成して`.env`へ保存する

- メリット: Terraform resourceを追加せずに済む。
- デメリット: 初回生成と保存が手作業になり、再生成や未設定による意図しないセッション無効化が起きやすい。Terraform管理を優先する利用者方針にも合わない。

### 2. Terraformで生成し、gitignore済みのlocal secret env fileへ出力する

- メリット: 値の生成とライフサイクルをstateで安定管理できる。既存Terraform output由来のdecK変数も同じmode `0600`のファイルへまとめられ、手作業の転記をなくせる。
- デメリット: Terraform stateとlocal fileの両方に機密値が残る。stateを失って再作成すると既存セッションが無効になる。

### 3. Azure Key Vault等の外部secret managerで管理する

- メリット: local state/fileからsecretを分離でき、集中管理と監査が可能になる。
- デメリット: 現在のlocal demoに対して追加のクラウドresource、権限、取得処理が必要となり、構成と継続コストが増える。

## 決定
選択肢2を採用する。Azure/Entra ID Terraform rootに`random_password.deck_session_secret`を追加し、既存Terraform-managed値とともに`local_sensitive_file.deck_environment`から`secrets/deck.env`へ出力する。

GatewayのService、Route、Pluginは引き続き`kong/`配下のdecK state fileが所有する。Konnect API tokenはTerraform stateやlocal fileへ保存せず、`KONNECT_TOKEN`から実行時に`DECK_KONNECT_TOKEN`へ渡す。

## 判断基準・根拠
- シークレットをTerraformのライフサイクルで安定管理するという利用者の明示方針に合う。
- 既存rootがdecKに必要なAzure/Entra IDの値をすでに所有しており、依存関係を重複させずに表現できる。
- `secrets/`はgitignore済みで、`local_sensitive_file`によりmode `0600`を強制できる。
- 現在の検証環境はlocal demoであり、外部secret manager追加による運用負荷とコストに見合う要件はない。
- `docs/design-brief.md`の3 Route構成、OBO方式、将来のTool追加方針は変更しない。

## 想定していたこと vs 実際どうだったか
実装とapply後に追記する。

## 影響・トレードオフ
- `terraform/terraform.tfstate`と`secrets/deck.env`は機密情報としてcommitせず、アクセス権を制限する。
- stateを失ってresourceを再作成した場合はsession secretがローテーションされ、既存のログインセッションが無効になる。
- Azure/Entra ID側の資格情報が更新された場合はTerraform applyでenv fileも更新される。
- Gateway entityの反映はTerraform applyでは行わず、従来どおりdecK validate/diffと明示承認後のsyncを使用する。

## 関連する決定
- [ADR-0001: TerraformのAzure認証方式](./0001-terraform-azure-auth-method.md)
- [ADR-0003: Konnect platform resourcesを独立Terraform rootで管理する](./0003-konnect-terraform-state-boundary.md)
