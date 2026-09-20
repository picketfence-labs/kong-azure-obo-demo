# ADR-0005: OIDC cache saltとtoken exchange TTLを明示してdecK syncを冪等化する

- **日付**: 2026-09-20
- **状態**: 決定

## コンテキスト
初回`deck gateway sync`はService 3件、Route 3件、Plugin 4件の作成に成功したが、直後のdiffで2つの`openid-connect` pluginが更新対象として残った。

Konnectのlive plugin schemaでは`cache_tokens_salt`が`auto: true`であり、未指定時にplugin instanceごとの値が自動生成される。宣言側は未指定のため`null`として比較され、syncのたびに差分となる。またMCP Routeでは、省略した`token_exchange.cache.ttl`とlive側の`null`にも正規化差分が生じた。live schema上、上位`cache_ttl`の既定値は3600秒である。

Kong公式のOIDC構成例も、token endpoint cache key用saltをsync間で維持するには安定値を明示する必要があるとしている。

## 検討した選択肢

### 1. Gateway自動生成値を使い、2 pluginの残存diffを既知差分として許容する

- メリット: 構成変更が不要。
- デメリット: すべてのsync前に実変更と正規化差分を見分ける必要があり、GitOpsの無差分確認が成立しない。再syncでsaltが変わり、token cacheを維持できない。

### 2. 既存の`DECK_SESSION_SECRET`を`cache_tokens_salt`にも流用する

- メリット: Terraform resourceと環境変数を増やさず、安定値にできる。
- デメリット: session cookie署名とtoken cache key saltという異なる用途を同じ値へ結合する。2つのplugin instanceも同じsaltを共有し、Gatewayが既定でinstanceごとに生成する分離を失う。

### 3. plugin instanceごとのcache saltをTerraformで生成する

- メリット: 用途とinstanceを分離し、安定した値をTerraform stateで管理できる。既存の`secrets/deck.env`経由で平文をcommitせずdecKへ渡せる。
- デメリット: `random_password` resourceと環境変数が2件増える。stateを失って再作成した場合はtoken cache keyが変わる。

`token_exchange.cache.ttl`については、未指定のまま正規化差分を許容する案と、上位`cache_ttl`の既定値と同じ3600秒を明示する案を比較した。後者は通常の既定動作を変えず、宣言値とlive値を一致させられる。

## 決定
選択肢3を採用し、login Route用とMCP Route用に別々の32文字saltをTerraformで生成する。`secrets/deck.env`へ別々の環境変数として出力し、各`openid-connect` pluginの`cache_tokens_salt`から参照する。

MCP Routeの`token_exchange.cache.ttl`は3600秒を明示する。

## 判断基準・根拠
- decKのpost-sync diffが無差分になることを、Gateway設定反映の完了条件として維持する。
- 公式資料が、cache entryをsync間で維持するため安定した`cache_tokens_salt`を明示するよう案内している。
- Gatewayの自動生成値がplugin instanceごとに異なるため、Terraform管理値もinstanceごとに分離する。
- session cookie署名secretを別用途へ流用せず、secret/saltの責務を分離する。
- TTL 3600秒はlive schemaで確認した上位`cache_ttl`の既定値と同じであり、通常動作を意図的に変更しない。

## 想定していたこと vs 実際どうだったか
- 想定: Terraform applyでsalt 2件を作成し、`secrets/deck.env`の置換以外の既存resourceは変更しない。実際: `3 added, 0 changed, 1 destroyed`で完了し、destroyはlocal sensitive fileの置換のみ。後続planは`No changes`。
- 想定: 生成済み実値でonline validateでき、sync前の差分はOIDC plugin 2件に限定される。実際: `deck gateway validate`は成功し、diffは更新2・作成0・削除0。
- 想定: 再sync後のdiffが無差分になる。実際: OIDC plugin 2件の更新後、`deck gateway diff --non-zero-exit-code`はexit 0、作成0・更新0・削除0となった。

## 影響・トレードオフ
- `terraform/terraform.tfstate`と`secrets/deck.env`に2つのsaltが追加されるため、既存どおりcommitせずmode `0600`を維持する。
- state喪失やresourceの明示的な再作成時だけsaltが変わり、対応するtoken cacheが無効になる。
- Gateway entityの反映責務は引き続きdecKに置き、Terraformは値のライフサイクルだけを所有する。

## 関連する決定
- [ADR-0003: Konnect platform resourcesを独立Terraform rootで管理する](./0003-konnect-terraform-state-boundary.md)
- [ADR-0004: decK用セッションシークレットをTerraformで管理する](./0004-terraform-managed-deck-session-secret.md)
