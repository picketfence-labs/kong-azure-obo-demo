# ADR-0007: 使い捨てEntra IDテストユーザーのMFA登録方式

- **日付**: 2026-09-20
- **状態**: 提案中

## コンテキスト
Terraformで作成した`demo-inquiry-only`ユーザーのUPN/passwordはEntra IDに受理されたが、初回対話ログイン直後に「アカウントをセキュリティ保護しましょう」が表示され、Microsoft Authenticator登録を必須要求された。画面にスキップ導線はなかった。

有効なConditional Access policyは0件だった。一方、Security DefaultsとAuthentication Methods Policyは現在のAzure CLI token/roleでは403となり、設定値を直接確認できなかった。Microsoft公式資料では、Security Defaultsは全ユーザーにMicrosoft Authenticatorを使ったMFA登録を要求し、2024-07-29以降は14日間の登録猶予も廃止されたと説明されており、観測した挙動と整合する。

このデモではテストユーザーをデモごとにTerraformで作成・destroyし、passwordを通常のデモサイクル外でローテーションしない運用を採用している。毎回の手動Authenticator登録はこの再現性を損なう。MFA登録、tenant policy変更、認証方法credentialの作成はいずれもセキュリティ状態を変えるため、方式を決める前に実施しない。

## 検討した選択肢

### 1. 各デモでテストユーザーをMicrosoft Authenticatorへ手動登録する

- メリット: 現在のtenant security policyを変更せず、既存フローをそのまま使える。
- デメリット: テストユーザーをdestroyするたびに登録をやり直す必要がある。端末・担当者への依存と手作業が増え、Terraform中心の再現可能なデモにならない。

### 2. 現tenantのSecurity Defaultsを無効化し、Conditional Accessで管理者等を保護しつつデモ用groupをMFA対象外にする

- メリット: テストユーザーはpassword-onlyの認可コードフローを完了でき、現在の作成・destroy運用を維持しやすい。対象をgroupで明示できる。
- デメリット: tenant-wide security postureを変更する。Conditional Accessに必要なlicenseと既存管理者の保護設計が必要で、デモrepositoryのスコープを超える可能性がある。Security DefaultsとConditional Accessは併用できない。

### 3. Security Defaultsを無効化した専用デモtenantへ分離する

- メリット: 既存tenantのsecurity postureを変えず、password-onlyテストをデモ用途へ隔離できる。Terraformで作成・destroyする運用とも整合する。
- デメリット: tenant作成、subscription/Azure OpenAI配置、Konnect/Entra設定の移行が必要で、準備と維持コストが最も大きい。

### 4. テストユーザーをdestroyせず、MFA登録済みの固定デモユーザーとして再利用する

- メリット: 現tenant policyを維持し、Authenticator登録を初回だけにできる。
- デメリット: 利用者が指定したデモごとの登録/破棄運用を変更する。認証方法の所有者・端末管理・credential lifecycleを別途定める必要がある。

## 決定
未決定。利用者確認後に採択する。現時点ではAuthenticator登録、Security Defaults/Conditional Access変更、テストユーザーlifecycle変更のいずれも実施しない。

## 判断基準・根拠
- 既存tenantのsecurity postureを不用意に弱めないこと。
- テストユーザーをデモごとにTerraformで作成・destroyするという現在の運用を、変更する場合は明示的に合意すること。
- OBO/ACLのデモが担当者の個人端末や手動Authenticator登録へ依存せず、再現可能であること。
- 認証方法credentialや例外設定も可能な限り宣言的に管理し、機密情報をrepositoryへ保存しないこと。
- [Microsoft Security Defaults公式資料](https://learn.microsoft.com/en-us/entra/fundamentals/security-defaults)と[Authentication Methods Policy API公式資料](https://learn.microsoft.com/en-us/graph/api/authenticationmethodspolicy-get?view=graph-rest-1.0)に従うこと。

## 想定していたこと vs 実際どうだったか
- 当初はTerraform生成passwordだけでテストユーザーが対話ログインできると想定していた。
- 実際にはpassword受理後にAuthenticator登録が必須となり、OBO/ACLのbrowser E2Eへ進めなかった。
- 方式決定・実装後に結果を追記する。

## 影響・トレードオフ
- 選択肢1または4は人・端末への依存を残す。
- 選択肢2は既存tenant全体のsecurity設計に影響する。
- 選択肢3は最も安全に分離できるが、Azure/Entra resource移行の作業量が大きい。

## 関連する決定
- [ADR-0003: Konnect platform resourcesを独立Terraform rootで管理する](./0003-konnect-terraform-state-boundary.md)
- [ADR-0006: OIDCの外向きTLS証明書検証を有効にする](./0006-oidc-tls-verification.md)
