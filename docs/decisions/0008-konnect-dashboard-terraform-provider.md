# ADR-0008: Konnect DashboardのTerraform provider境界

- **日付**: 2026-09-20
- **状態**: 決定

## コンテキスト
Konnect ObservabilityのCustom Dashboardを再現可能なコードとして管理し、API、MCP、LLMのtraffic・latency・errorと、client別利用量、LLM token利用量を可視化する。既存のKonnect platform resourceは`terraform/konnect/`で公式`kong/konnect` providerにより管理している。一方、インストール済み`kong/konnect` 3.23.0のprovider schemaにはDashboard resourceがない。Kong公式手順はDashboardに`kong/konnect-beta`の`konnect_dashboard`を使用している。

## 検討した選択肢

### 1. `kong/konnect-beta`をDashboardだけに使用する
- Terraform stateでDashboardの作成・更新・削除を管理できる。
- 既存のControl Plane等は安定版providerのまま維持できる。
- beta API/providerであるためschema変更やprovider defectの影響を受ける。特にtileのchart/query wire formatについて既知issueがある。

### 2. Konnect APIを`terraform_data`とscriptから呼び出す
- beta providerを追加せずにTerraform起点で実行できる。
- TerraformがDashboardの属性差分を理解できず、refresh、update、delete、importのstate管理が弱い。認証情報を安全にscriptへ渡す設計も増える。

### 3. `kongctl` declarative、Konnect UI、またはAPIをTerraform外で使う
- Dashboard definitionの対応範囲は広い。
- 「基本的に全てTerraformで管理する」という利用者指示と、既存のKonnect Terraform root境界に合わない。UI操作はdriftを発生させる。

## 決定
`terraform/konnect/`へ`kong/konnect-beta`を追加し、`konnect_dashboard`だけをbeta providerで管理する。既存resourceは`kong/konnect`から移さない。Dashboard definition、filter、layout、labels、outputを同じrootでversion管理する。

## 判断基準・根拠
- 利用者がKonnect作業を原則Terraformで行うよう指定している。
- `docs/design-brief.md`はDashboard definition/exportと再現手順を成果物に要求している。
- 公式`kong/konnect` provider 3.23.0にはDashboard resourceがなく、Kong公式手順が`kong/konnect-beta`を指定している。
- beta providerの適用範囲をDashboardだけに限定すれば、既存の安定版provider所有resourceへの影響を抑えられる。

## 想定していたこと vs 実際どうだったか
- `kong/konnect-beta` 0.22.0でDashboardだけを追加する保存planは、既存Konnect resourceへの変更なしで`1 to add, 0 to change, 0 to destroy`となった。
- 保存planのapplyは成功し、22 tileを持つ`Azure OBO Demo Observability`（ID `312c1e16-e4b5-4794-a522-57037e30737b`）が作成された。state read-backでname、ID、Control Plane preset filterを確認し、後続planは`No changes`となった。
- Top N chartのdimension上限は生成文書の最大3ではなくprovider schema上は最大2だったため、実行時schemaに合わせて各queryを2 dimensionにした。またproviderが補完する小数既定値を宣言へ明示し、apply後のdriftを防いだ。
- Konnect UIでの目視確認は、Computer UseのChrome sessionが対象`hashi-sandbox`ではなく新規Organization作成画面へredirectされたため未完了。誤ったOrganizationは作成していない。

## 影響・トレードオフ
- Dashboardのschema互換性はbeta provider versionに依存するためversion constraintとlock fileを固定する。
- `terraform validate`だけでなくlive plan、apply後のstate/read-back、再planを必須にする。
- provider defectで安全に作成できない場合はAPIや`kongctl`へ黙って切り替えず、ADRを更新して利用者へ確認する。

## 関連する決定
- [ADR-0003: Konnect Terraform stateの分離](./0003-konnect-terraform-state-boundary.md)
