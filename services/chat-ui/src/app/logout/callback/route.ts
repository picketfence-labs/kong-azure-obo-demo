// kong/login-route.yamlのopenid-connectはlogin_action:upstream（既定値）のため、
// Entra IDからのpost_logout_redirect_uriコールバックのリクエストパス自体がそのまま
// ここへ転送される。ログアウト自体（セッションcookie破棄）はKongの時点で完了済みなので、
// ここではトップページへ送り返すだけでよい。トップページはセッションが無いため、
// 再度Kongのopenid-connectがログイン画面へ誘導する（docs/troubleshooting-log.md参照）。
export async function GET() {
  return Response.redirect("http://localhost:8000/", 303);
}
