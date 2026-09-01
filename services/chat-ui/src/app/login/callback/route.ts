// kong/login-route.yamlのopenid-connectはlogin_action:upstream（既定値）のため、
// Entra IDからのコールバックのリクエストパス自体がそのままここへ転送される。
// 認証自体はKongの時点で完了済み（セッションcookie発行済み）なので、ここでは
// トップページへ送り返すだけでよい（docs/troubleshooting-log.md参照）。
export async function GET() {
  return Response.redirect("http://localhost:8000/", 303);
}
