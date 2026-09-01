import { createMCPClient } from "@ai-sdk/mcp";
import { createOpenAI } from "@ai-sdk/openai";
import { convertToModelMessages, stepCountIs, streamText, type UIMessage } from "ai";

export const maxDuration = 30;

// KongをホストするDocker Composeの内部ネットワーク名（docker-compose.yml参照）。
const KONG_BASE_URL = process.env.KONG_INTERNAL_BASE_URL ?? "http://kong:8000";

// kong/llm-route.yamlのmodel.model_aliasと一致させる固定値。
// エージェント側はAzure OpenAIのデプロイ名・エンドポイント・APIバージョンを一切知らない
// （design-brief 2節、検証方法9番目の要件）。
const KONG_LLM_MODEL_ALIAS = "kong-demo-llm";

export async function POST(req: Request) {
  const { messages }: { messages: UIMessage[] } = await req.json();

  // kong/login-route.yamlのopenid-connect（upstream_access_token_header、デフォルト
  // "authorization:bearer"）がこのリクエストにAuthorizationヘッダーとして転送した
  // アクセストークン。同じトークンをMCPエンドポイント用Route（kong/mcp-route.yaml）へ
  // 再提示することで、そちらのOBO(token_exchange)のassertionとして使われる。
  const authorization = req.headers.get("authorization");
  if (!authorization) {
    return new Response("Unauthorized: no access token forwarded by Kong", {
      status: 401,
    });
  }

  const mcpClient = await createMCPClient({
    transport: {
      type: "http",
      url: `${KONG_BASE_URL}/mcp/customers`,
      headers: { Authorization: authorization },
    },
  });

  const openai = createOpenAI({
    baseURL: `${KONG_BASE_URL}/llm`,
    // ai-proxy-advancedがAzure OpenAIの認証情報を保持するため、ここでのAPIキーは
    // Kong側では検証されない（このRouteには追加認証を掛けない設計。design-brief 3節、
    // 実際の保護はADR-0002参照）。SDKがAuthorizationヘッダーの送信を必須とするための
    // ダミー値。
    apiKey: "kong-manages-auth",
  });

  try {
    const tools = await mcpClient.tools();

    const result = streamText({
      model: openai.chat(KONG_LLM_MODEL_ALIAS),
      system:
        "あなたは顧客情報APIへアクセスできるアシスタントです。顧客の詳細情報が必要な場合は、" +
        "必ず先にcustomer_inquiryで検索して顧客IDを取得してから、customer_detailsを呼び出してください。",
      messages: await convertToModelMessages(messages),
      tools,
      stopWhen: stepCountIs(5),
      onFinish: async () => {
        await mcpClient.close();
      },
    });

    return result.toUIMessageStreamResponse();
  } catch (error) {
    await mcpClient.close();
    throw error;
  }
}
