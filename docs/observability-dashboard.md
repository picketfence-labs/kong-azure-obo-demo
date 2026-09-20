# Konnect Observability Dashboard

`Azure OBO Demo Observability`は、`azure-obo-demo` control planeのAPI、MCP、LLM trafficを1画面で確認するCustom Dashboardです。TerraformがDashboardのdefinitionとlifecycleを管理します。

## 表示する指標

Dashboardは直近24時間をAsia/Tokyoで表示し、control plane IDをpreset filterへ設定します。

| 対象 | 指標と内訳 |
|---|---|
| API / Gateway Route | Route別request count、P95 response latency、error rate |
| API client | Routeと`principal`別request count |
| Latency分析 | P95 response、upstream、Kong internal latency |
| MCP | Tool別request count、P95 response latency、error rate |
| MCP client | `principal`とMCP method別request count |
| MCP Tool | MCP methodとTool名別request count |
| LLM summary | request count、平均LLM latency、error rate、total/prompt/completion token |
| LLM model | response model別request countとtoken、provider別tokenとcost |
| LLM client | `principal`と`application`別request countとtotal token |

CostはAI Proxy Advancedのmodel cost設定とprovider telemetryがある場合に表示されます。未設定の場合は空または0になります。

## clientの識別方法

Konnect Analyticsが標準で集計する`principal`、`consumer`、`application`をclient identityとして使います。このDashboardでは次を優先します。

- API: `route`と`principal`
- MCP: `principal`と`mcp_method`
- LLM: `principal`と`application`

`principal`は認証された主体、`consumer`はKong Consumer、`application`はKonnect applicationです。現在のLLM RouteはDocker内部networkで保護し、Kong認証を設定していません。そのためLLM client chartではidentityが`None`になる可能性があります。任意の`User-Agent`、IP address、独自headerはCustom Dashboardのclient dimensionとして直接集計しません。caller applicationを必ず区別する要件が追加された場合は、Kong Consumerへ安全に対応付ける認証方式を別ADRで決定します。

## Terraformで作成する

Dashboardは`terraform/konnect/dashboard.tf`で定義します。安定版`kong/konnect` providerはDashboard resourceを提供しないため、Dashboardだけ`kong/konnect-beta`を使います。provider境界は[ADR-0008](./decisions/0008-konnect-dashboard-terraform-provider.md)を参照してください。

```bash
export KONNECT_TOKEN='KONNECT_PERSONAL_ACCESS_TOKEN'
```

```bash
terraform -chdir=terraform/konnect init
```

```bash
terraform -chdir=terraform/konnect validate
```

```bash
terraform -chdir=terraform/konnect plan -out=dashboard.tfplan
```

planが`konnect_dashboard.azure_obo_demo`の作成だけであることを確認してからapplyします。

```bash
terraform -chdir=terraform/konnect apply dashboard.tfplan
```

## 作成結果を確認する

apply後にDashboard URLを取得します。

```bash
terraform -chdir=terraform/konnect output -raw dashboard_url
```

KonnectでDashboardを開き、次を確認します。

1. Dashboard名が`Azure OBO Demo Observability`である。
2. preset filterが`azure-obo-demo` control planeだけを対象にしている。
3. Chat UIからsmoke trafficを送信すると、API/MCP/LLMのcall、latency、error、LLM token tileへ反映される。
4. `terraform -chdir=terraform/konnect plan -detailed-exitcode`が`No changes`になる。

Analyticsの反映には遅延が発生する場合があります。API、LLM、Agenticは別datasetです。特定datasetだけ空の場合は、他datasetの表示を根拠に全telemetryの障害と判断しないでください。
