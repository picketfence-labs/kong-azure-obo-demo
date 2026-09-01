import { customers, getCustomerById, searchCustomers, type Gender } from "./data";

const port = Number(process.env.PORT ?? 3001);

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json" },
  });
}

Bun.serve({
  port,
  fetch(req) {
    const url = new URL(req.url);

    // Customer Inquiry: 氏名（部分一致）/性別/都道府県、AND条件
    if (req.method === "GET" && url.pathname === "/customers") {
      const gender = url.searchParams.get("gender") ?? undefined;
      if (gender !== undefined && gender !== "male" && gender !== "female") {
        return json({ error: "gender must be 'male' or 'female'" }, 400);
      }

      const results = searchCustomers(customers, {
        name: url.searchParams.get("name") ?? undefined,
        gender: gender as Gender | undefined,
        prefecture: url.searchParams.get("prefecture") ?? undefined,
      });
      return json(results);
    }

    // Customer Details: 顧客ID（UUID）による一意取得のみ
    const detailMatch = url.pathname.match(/^\/customers\/([^/]+)$/);
    if (req.method === "GET" && detailMatch) {
      const customer = getCustomerById(customers, detailMatch[1]!);
      if (!customer) {
        return json({ error: "not found" }, 404);
      }
      return json(customer);
    }

    return json({ error: "not found" }, 404);
  },
});

console.log(`demo-api listening on :${port}`);
