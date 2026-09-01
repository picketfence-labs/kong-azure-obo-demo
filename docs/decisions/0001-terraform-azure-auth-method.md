# ADR-0001: Terraform ⇔ Azure/Entra ID の認証方式

- **日付**: 2026-09-01
- **状態**: 決定

## コンテキスト
Terraformで Entra ID（App Registration・Security Group、`azuread` provider）とAzure OpenAI（`azurerm` provider）を管理する。ユーザーはAzureアカウントを作成した直後で、Claude Code（ローカルで`terraform`を実行する主体）にAzure/Entra IDへのアクセスを与える必要がある。認証方式には複数の技術的に妥当な選択肢があるため、実装前に検討する。

## 検討した選択肢

**A. Azure CLIへの委譲認証**（`az login` → `azuread`/`azurerm` providerは明示的な認証情報を持たず、CLIのキャッシュ済みトークンを使う）
- Pros: クライアントシークレット等の長期間有効な静的資格情報が一切不要。セットアップは`az login`一度のみ。誰が実行したかがそのままユーザー本人のIDに紐づき監査しやすい
- Cons: `terraform`実行時にそのマシンでインタラクティブな`az login`セッションが有効である必要がある。リフレッシュトークン失効時は再ログインが要る。CI等の非対話環境では使えない

**B. 専用Service Principal + クライアントシークレット**（`az ad sp create-for-rbac`で作成し、`.env`等でARM_CLIENT_SECRET等をexport）
- Pros: 特定ユーザーのログインから切り離せる。CIへそのまま持ち込める
- Cons: 長期間有効な静的シークレットを保管・ローテーションする必要があり漏洩リスクが生じる。今回はCIをスコープ外としているため、この構成が解決する問題（非対話実行）自体が存在しない

**C. Service Principal + Workload Identity Federation（OIDC、シークレットレス）**
- Pros: シークレットなしでCI/CDから使える、ベストプラクティス
- Cons: 外部のOIDCトークン発行者（GitHub Actions等）が前提。ローカルでの`terraform`実行のみの現状では成立しない・過剰な複雑さ

## 決定
**A. Azure CLIへの委譲認証**を採用する。

## 判断基準・根拠
- `docs/design-brief.md`の要件「長期間有効な静的な認証情報より、可能な範囲で一時的な認証方式を優先する」と「CI化: 今回はスコープ外」の2点だけで一意に決まる（BはCLAUDE.mdのセキュリティ方針に反し、CはCI前提の解決策であり今回不要）
- Azureアカウントを新規作成したユーザーは、その既定テナントのGlobal Administratorであるのが通常であり、App Registration/Security Group作成・Enterprise Appの「割り当てが必要」設定・グループメンバー管理、およびAzure OpenAIリソース作成（サブスクリプションへのContributor/Owner）に必要な権限を、追加のロール割り当てなしで既に持っていると想定できる

## 想定していたこと vs 実際どうだったか
（実装・検証を経てから追記する）

## 影響・トレードオフ
- `terraform init/plan/apply`は、実行するマシン上で`az login`済みのセッションがある前提になる。セッション切れ時は`az login`のやり直しが必要
- 将来CI化する場合（現状スコープ外）は、この決定を見直し選択肢Cへの移行を検討する

## 関連する決定
なし
