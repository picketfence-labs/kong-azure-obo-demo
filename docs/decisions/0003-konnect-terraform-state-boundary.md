# ADR-0003: Konnect platform resourcesを独立Terraform rootで管理する

- **日付**: 2026-09-20
- **状態**: 決定

## コンテキスト
Konnect Organization `hashi-sandbox`のUSリージョンへ、self-managed Control Plane `azure-obo-demo`を新規作成する。利用者からKonnectの作業も原則Terraformで行うよう明示された。

既存の`terraform/` rootはAzure/Entra IDリソースを管理するが、手元のstateは空であり、`terraform plan`は既存リソース26件をすべて新規作成すると判定している。このrootへKonnect resourceを追加して同時にapplyすると、対象外のAzure/Entra IDリソースを誤作成する危険がある。

## 検討した選択肢

### 1. 既存の`terraform/` rootへKonnect resourceを追加する

- メリット: Terraform rootと実行手順が1つで済む。
- デメリット: 空の既存stateと同じplan/apply境界になり、Konnectだけを安全にapplyできない。`-target`常用は依存関係を見落としやすく、state分離の代替にならない。

### 2. `terraform/konnect/`を独立Terraform rootとして追加する

- メリット: Konnect Control PlaneとData Plane certificateだけを独立してplan/applyでき、既存Azure/Entra IDの空state問題から隔離できる。provider credential、state、lifecycleも製品境界ごとに明確になる。
- デメリット: `terraform init/plan/apply`の実行ディレクトリが2つになり、local stateも別々に管理する必要がある。

### 3. 既存Azure/Entra ID stateを先に復旧してから同じrootへ統合する

- メリット: 将来的には単一rootで依存関係を表現できる。
- デメリット: state所在の特定と26リソースのimport検証が必要で、Konnect bootstrapを不必要にブロックする。異なるcredential・lifecycleを1つのapply境界に結合する。

## 決定
`terraform/konnect/`を独立Terraform rootとして追加し、公式`kong/konnect` providerでControl PlaneとData Plane client certificateを管理する。certificate/keyの生成とgitignore済み`secrets/konnect/`への保存もTerraform resourceで行う。

既存の`terraform/`は引き続きAzure/Entra ID専用とし、state復旧が完了するまでapplyしない。Gateway entityは既存方針どおりdecKで管理し、Konnect platform resourceとGateway configurationの責務を分離する。

## 判断基準・根拠
- 利用者がKonnect作業のTerraform管理を明示的に選択した。
- 現在の要件はControl Planeの新規作成であり、UIで`hashi-sandbox` USに同名resourceが存在しないことを確認済みのためimportは不要。
- 既存Azure/Entra ID stateが空という既知の危険をapply境界で隔離できる。
- 将来のKonnect Dashboard、Registry、Catalog対応も、provider coverageがあるresourceから同じKonnect rootへ追加できる。
- Gateway entityはdecKのvalidate/diff/sync承認フローを維持するため、既存の責務分離と矛盾しない。

## 想定していたこと vs 実際どうだったか
想定どおり、Konnect専用planはAzure/Entra ID resourceを含まず、初回applyは`7 added, 0 changed, 0 destroyed`で完了した。その後、Compose用env fragmentをTerraform管理へ追加し、合計8 resourceとなった。

Data PlaneはTerraform生成certificateでControl Planeへ接続し、control-plane ping、analytics websocket接続、KonnectからのEnterprise license受信をGateway logで確認できた。一方、local backendが秘密鍵を含むstateをmode `0644`で作成したため、apply後に`chmod 600 terraform.tfstate`を実施する運用上の補完が必要になった。

## 影響・トレードオフ
- `terraform/`と`terraform/konnect/`を別々にinit/plan/applyする必要がある。
- Konnect provider tokenはコードへ保存せず、`KONNECT_TOKEN`または`KONNECT_SPAT`で実行時に渡す。
- local stateにはData Plane private keyがsensitive値として含まれるため、stateをcommitせずアクセスを制限する。stateを失った場合はcertificateを再発行・再登録する。

## 関連する決定
- [ADR-0001: TerraformのAzure認証方式](./0001-terraform-azure-auth-method.md)
