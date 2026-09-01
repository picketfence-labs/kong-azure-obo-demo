import { describe, expect, test } from "bun:test";
import { generateCustomers, getCustomerById, searchCustomers, toSummary } from "./data";

const customers = generateCustomers(100, 42);

describe("generateCustomers", () => {
  test("生成される人数が指定通り", () => {
    expect(customers).toHaveLength(100);
  });

  test("固定シードなら再生成しても同じ結果", () => {
    const again = generateCustomers(100, 42);
    expect(again).toEqual(customers);
  });

  test("顧客IDはUUID形式で重複しない", () => {
    const ids = new Set(customers.map((c) => c.id));
    expect(ids.size).toBe(customers.length);
    for (const id of ids) {
      expect(id).toMatch(/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/);
    }
  });

  test("マイナンバーは12桁の数字文字列", () => {
    for (const c of customers) {
      expect(c.myNumber).toMatch(/^\d{12}$/);
    }
  });
});

describe("searchCustomers", () => {
  test("フィルタ無しなら全件をサマリ形式で返す", () => {
    const results = searchCustomers(customers, {});
    expect(results).toHaveLength(customers.length);
    expect(results[0]).not.toHaveProperty("myNumber");
  });

  test("性別・都道府県はAND条件で絞り込む", () => {
    const target = customers[0]!;
    const results = searchCustomers(customers, {
      gender: target.gender,
      prefecture: target.prefecture,
    });
    expect(results.length).toBeGreaterThan(0);
    for (const r of results) {
      expect(r.gender).toBe(target.gender);
      expect(r.prefecture).toBe(target.prefecture);
    }
  });

  test("氏名は部分一致", () => {
    const target = customers[0]!;
    const partialName = target.name.slice(0, 1);
    const results = searchCustomers(customers, { name: partialName });
    expect(results.some((r) => r.id === target.id)).toBe(true);
    for (const r of results) {
      expect(r.name.includes(partialName)).toBe(true);
    }
  });

  test("氏名・性別・都道府県の組み合わせはAND条件", () => {
    const target = customers[0]!;
    const results = searchCustomers(customers, {
      name: target.name,
      gender: target.gender === "male" ? "female" : "male",
    });
    expect(results.some((r) => r.id === target.id)).toBe(false);
  });
});

describe("getCustomerById", () => {
  test("正しいIDならフル項目を返す", () => {
    const target = customers[0]!;
    const found = getCustomerById(customers, target.id);
    expect(found).toEqual(target);
  });

  test("存在しないIDはundefined", () => {
    expect(getCustomerById(customers, "00000000-0000-0000-0000-000000000000")).toBeUndefined();
  });
});

describe("toSummary", () => {
  test("フル項目からサマリ4項目だけを取り出す", () => {
    const target = customers[0]!;
    expect(toSummary(target)).toEqual({
      id: target.id,
      name: target.name,
      gender: target.gender,
      prefecture: target.prefecture,
    });
  });
});
