# CLAUDE.md

このファイルはClaude Codeがこのリポジトリで作業する際のガイドです。

## このリポジトリについて
Kong Gateway 3.16（ベータ）のOpenID Connectプラグイン新機能「Entra ID OBO（On-Behalf-Of）」を、AI MCP ProxyのACL機能・AI Proxy AdvancedによるLLMアクセス抽象化と組み合わせて実地検証するデモ。Chat AIエージェント→Kong Gateway→（OBOでトークン交換）→MCP化されたバックエンドAPI、という流れを構築する。**Konnectは使用しない**（Kong Gateway単体、Postgres backed）。

## 基本設計
[docs/design-brief.md](./docs/design-brief.md) を必ず参照すること。Projectゴール・要件（現在＋将来）・アーキテクチャ（Kongがフロントする3系統のRoute/Service構成、Entra IDアプリ構成、OBOの実装詳細）・技術スタック・検証方法・成果物を記載済み。全論点はPicketfence Labs Obsidian Vault側とのヒアリングで確定済みで、着手前の再確認は不要（ただし実装中に新たな判断ポイントが見つかった場合は下記「アーキテクチャ上の分岐点」の手順に従う）。

## 開発フロー
- `main`ブランチはbranch protection有効化を試みる（PR必須、`enforce_admins: true`）。ただし本リポジトリはprivate。**private + GitHub Freeプランではbranch protection APIが403で有効化できない既知の制約がある**（有効化できなかった場合はこのCLAUDE.mdの運用規約として「直接pushしない」ことを守ること）
- `git checkout -b <branch>` → 実装・検証 → `git push -u origin <branch>` → `gh pr create` → `gh pr merge --squash --delete-branch`
- PRの粒度は1PR=1テーマ。descriptionにWhat/Why/Testingを含める

## アーキテクチャ上の分岐点に遭遇した時の取り決め（重要）
過去の別プロジェクト（`aws-konnect-dcgw`）で、将来要件を確認せずに1つの選択肢を選んで進めてしまい手戻りが発生した実例がある。この再発防止:
1. 複数の技術的に妥当な選択肢がある判断ポイントに遭遇したら、**1つを選んで実装を進める前に必ず立ち止まる**
2. `docs/decisions/`に`docs/decisions/TEMPLATE.md`の形式でADRを作成し、「検討した選択肢」「判断基準・根拠」を**決定を下す前に**埋める
3. `docs/design-brief.md`の要件（現在＋将来）で選択肢が一意に決まるなら、その判断過程をADRに記録した上でそのまま進めてよい
4. 要件だけでは一意に決まらない場合は、**選択肢と判断基準を提示し確認を取ってから進める**（実装後の事後報告にしない）

具体例として、`docs/design-brief.md`にまだ明記されていない実装の細部（例: `ai-mcp-proxy`のツール定義の具体的なJSON Schema、decKのファイル分割方針等）は自己判断してよいが、記載されているアーキテクチャ方針（3 Route構成、`conversion-listener`モード、Auth.js不採用等）を覆す変更は必ずADR化＋確認を取ること。

## 想定通りに動かなかったことの記録（漏れなく）
判断ポイントかどうかに関わらず、日常的な小さな想定外（エラー、ドキュメントと異なる挙動、想定した設定で動かなかった等）も対象。
1. 遭遇したら**その場で**`docs/troubleshooting-log.md`に追記する（後から思い出して書かない、大したことではないと省略しない）
2. 各ステップの区切り・完了報告のタイミングで、このログの新規追加分を要約して報告に含める
3. 特にKong 3.16のベータ機能（`openid-connect`のOBO、`ai-mcp-proxy`との連携）は未リリース機能のため、公式ドキュメントとの乖離やドキュメント自体の不在が起こりやすい。実際に動かして確認した挙動を優先して記録する

## エスカレーション条件（必ず確認を取る）
1. 不可逆・破壊的な操作（`terraform apply`・`terraform destroy`、Entra IDのApp Registration/Security Groupの削除・再作成、decKの`sync`による本番相当環境への反映）
2. 継続的にコストが発生する操作（Azure OpenAIの利用、Kong Enterpriseライセンスの消費等）
3. 要件の曖昧さが設計の方向性に影響する場合
4. スコープ逸脱
5. 機密情報の扱いに確信が持てない場合（Entra IDのclient secret、Azure OpenAI APIキー、Postgres認証情報、マイナンバー等を模したテストデータ等）

## 自己判断で進めてよい条件
1. 読み取り専用の調査・確認作業（`terraform plan`、`deck diff`、`az`の参照系コマンド等）
2. 承認済みスコープ内の実装
3. 影響が閉じた環境（ローカルDocker Compose上の検証用リソース）への変更
4. 既存パターンに従った追加的（非破壊的）な変更
5. lint/format（`terraform fmt`、Bun/TypeScriptのformatter）等の定型作業

## 報告のタイミング
各ステップの区切り／エスカレーション対象操作の実行**前**／想定外のブロッカー遭遇時／アーキテクチャ上の分岐点に遭遇した時

## 完了報告フォーマット
1. 実施内容（サマリ）
2. どう検証したか（`terraform plan`出力、実際にログイン/OBO/ACLが動いた実測結果等。「動くはず」ではなく実際に確認した事実）
3. 指示から逸脱した判断とその理由（あれば）
4. 未解決・持ち越しの論点
5. CLAUDE.md・権限設定・連携ドキュメント自体に感じた摩擦・改善提案（無ければ「特になし」と明記）

## テスト方針
- テストケースの導出は`docs/design-brief.md`（要件から直接導出済み）を参照。後付けにしない
- `terraform validate`＋`terraform plan`出力のレビュー、`deck validate`/`deck diff`のレビューを最低限必須とする
- `docs/design-brief.md`の「5. 検証方法」にあるテストケースを実際に確認する

## セキュリティ・クラウド認証
- Entra IDのApp RegistrationのService Principal/クライアントシークレットには、タスク遂行に必要な最小限の権限のみを付与する（PoLP）
- 認証情報（Entra IDのclient secret、Azure OpenAI APIキー、Postgres認証情報等）はコード・CLAUDE.md・コミット履歴に平文で残さない
- Customer Inquiry/Customer Detailsのテストデータ（マイナンバー等を模した項目を含む）は、必ず**アルゴリズム的にランダムな架空データ**として生成し、実在する番号・個人情報を一切含めないこと。生成方法は`docs/troubleshooting-log.md`または`docs/decisions/`に一言記録する
- 長期間有効な静的な認証情報より、可能な範囲で一時的な認証方式を優先する

## Kong Gateway関連の技術メモ
- イメージ: `kong/kong-gateway-dev:pr-21082-ubuntu`（ベータ、Entra ID OBO対応）
- `openid-connect`プラグインの`token_exchange.grant_type=jwt_bearer`+`provider=microsoft`でEntra ID OBOを実装（詳細は`docs/design-brief.md`「3. アーキテクチャ」参照）
- `ai-mcp-proxy`は`conversion-listener`モードで開始（将来Tool追加時に`listener`+`conversion-only`へ作り替える）
- `ai-proxy-advanced`でAzure OpenAIへのアクセスを抽象化
- Kong Gateway自体の設定はdecKの宣言的YAMLで管理（Terraformの対象外）
- Kong公式の[`Kong/ai-marketplace`](https://github.com/Kong/ai-marketplace)（tech preview）に、decKのstate file・validate/diff/sync操作を支援する`deck-gateway`スキルが含まれる。導入を検討する場合は`/plugin marketplace add kong/ai-marketplace` → `/plugin install kong-konnect@ai-marketplace`（未使用検証、必要になったタイミングで判断する）
- terraform-mcp-serverは導入しない（Picketfence Labs Vaultの一般方針。ローカルの`.tf`＋`terraform`コマンド実行のみで運用し、HCP Terraform等のリモート管理は使わない）

## ローカル参照
Picketfence Labs Obsidian Vault側のセッションと同一端末で作業している場合、以下のローカルリポジトリが参照可能（`.claude/settings.json`の`additionalDirectories`で許可されている場合。無い場合は明示的に依頼して`--add-dir`で追加すること）:
- `kong-ee`（Kong EEソースコード。OBO機能・`ai-mcp-proxy`の実装詳細を確認する一次情報源）
- `kong-mcp-testbed`（Postgres+decKの実働構成サンプル、OIDC+`ai-mcp-proxy`ネイティブACLの実装例）

## セッション終了時
Picketfence Labs Obsidian Vault側のセッションが、このリポジトリの`git fetch`/`git diff`で直接検証する運用（オーケストレーション型）。完了報告は上記フォーマットで簡潔なメッセージとして返せばよい。CLAUDE.md・権限設定・連携ドキュメント自体への改善提案があれば、セッション終了を待たずその都度提案してよい。
