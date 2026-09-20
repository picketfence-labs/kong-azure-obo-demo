# ADR-0006: OIDCの外向きTLS証明書検証を有効にする

- **日付**: 2026-09-20
- **状態**: 決定

## コンテキスト
Konnect Control Plane上のdecK構成は無差分だったが、local Data Planeで`http://localhost:8000/`へアクセスすると`no Route matched with those values`になった。Data Plane logには、2つの`openid-connect` pluginについて次の構成拒否が記録されていた。

`ssl_verify invalid value: global tls_certificate_verify option is enabled, ssl_verify cannot be disabled`

Kong Gateway 3.16.0.0ではglobal TLS証明書検証が有効なため、OIDC pluginの`ssl_verify: false`という既定値を含むControl Plane構成全体がData Planeでrejectされ、Routeが反映されていなかった。Data Planeは`KONG_LUA_SSL_TRUSTED_CERTIFICATE=system`でOS trust storeを使用しており、OIDC issuerはMicrosoft Entra IDの公開HTTPS endpointである。

## 検討した選択肢

### 1. OIDC plugin 2件に`ssl_verify: true`を明示する

- メリット: Microsoft endpointのserver certificateをsystem CAで検証し、global policyと整合する。token交換や認可コードフローの機密通信で証明書検証を維持できる。
- デメリット: issuer側の証明書chainまたはlocal trust storeに問題がある場合、OIDC通信が失敗する。

### 2. Data Planeのglobal `tls_certificate_verify`を無効にする

- メリット: plugin既定値のまま構成を受信できる。
- デメリット: OIDC以外を含む外向きTLS検証をglobalに弱める。Entra ID token endpointとの通信に対する中間者攻撃耐性を落とし、最小権限・機密情報保護の要件に反する。

### 3. 構成rejectを既知制約として許容する

- メリット: 宣言ファイルの変更が不要。
- デメリット: 3 RouteすべてがData Planeへ反映されず、デモが動作しないため採用不能。

## 決定
選択肢1を採用する。login RouteとMCP Routeの`openid-connect` pluginへ`ssl_verify: true`を明示し、global TLS policyと一致させる。

## 判断基準・根拠
- OIDC authorization codeとOBO token exchangeはいずれも機密tokenを扱うため、外向きTLSのserver certificate検証を無効化しない。
- Entra IDは公開CA certificateを使用し、Data Planeはsystem trust storeを設定済みである。
- design briefの構成を変更せず、Data Planeが正式版3.16のglobal security policy下で受理できる最小変更である。
- 将来ToolやRouteを追加しても、OIDC通信のTLS検証を維持する方針と矛盾しない。

## 想定していたこと vs 実際どうだったか
- 宣言ファイルへの実装後、local/online validateは想定どおり成功した。
- sync前diffは想定どおり、login RouteとMCP RouteのOIDC plugin 2件に対する`ssl_verify: false`から`true`への更新だけ（作成0、削除0）だった。
- sync、Data Plane反映、browser smoke testの結果は実施後に追記する。

## 影響・トレードオフ
- Entra IDのcertificate chainをsystem trust storeで検証できない環境ではOIDCが失敗する。その場合も検証無効化ではなくtrust storeを修正する。
- Gateway entityの管理責務は引き続きdecKに置く。

## 関連する決定
- [ADR-0003: Konnect platform resourcesを独立Terraform rootで管理する](./0003-konnect-terraform-state-boundary.md)
- [ADR-0005: OIDC cache saltとtoken exchange TTLを明示してdecK syncを冪等化する](./0005-oidc-cache-salt-and-token-exchange-ttl.md)
