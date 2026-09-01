export type Gender = "male" | "female";

export interface CustomerSummary {
  id: string;
  name: string;
  gender: Gender;
  prefecture: string;
}

export interface CustomerDetail extends CustomerSummary {
  age: number;
  myNumber: string;
  address: string;
  phone: string;
  email: string;
}

const PREFECTURES = [
  "北海道", "青森県", "岩手県", "宮城県", "秋田県", "山形県", "福島県",
  "茨城県", "栃木県", "群馬県", "埼玉県", "千葉県", "東京都", "神奈川県",
  "新潟県", "富山県", "石川県", "福井県", "山梨県", "長野県", "岐阜県",
  "静岡県", "愛知県", "三重県", "滋賀県", "京都府", "大阪府", "兵庫県",
  "奈良県", "和歌山県", "鳥取県", "島根県", "岡山県", "広島県", "山口県",
  "徳島県", "香川県", "愛媛県", "高知県", "福岡県", "佐賀県", "長崎県",
  "熊本県", "大分県", "宮崎県", "鹿児島県", "沖縄県",
];

const FAMILY_NAMES = [
  "佐藤", "鈴木", "高橋", "田中", "伊藤", "渡辺", "山本", "中村", "小林", "加藤",
  "吉田", "山田", "佐々木", "山口", "松本", "井上", "木村", "林", "斎藤", "清水",
];

const GIVEN_NAMES: Record<Gender, string[]> = {
  male: [
    "翔太", "大輝", "陸", "蓮", "悠斗", "颯", "湊", "陽翔", "樹", "拓海",
  ],
  female: [
    "陽菜", "凛", "結衣", "さくら", "美咲", "葵", "楓", "杏", "花", "莉子",
  ],
};

/**
 * 決定論的な擬似乱数生成器（mulberry32）。
 * デモデータをコンテナ再起動をまたいで再現可能にするための固定シード用途のみで、
 * 暗号用途・実在データの匿名化用途では使わない。
 */
function mulberry32(seed: number): () => number {
  let a = seed;
  return () => {
    a |= 0;
    a = (a + 0x6d2b79f5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

function pick<T>(rng: () => number, items: readonly T[]): T {
  return items[Math.floor(rng() * items.length)]!;
}

function randomDigits(rng: () => number, length: number): string {
  let out = "";
  for (let i = 0; i < length; i++) {
    out += Math.floor(rng() * 10).toString();
  }
  return out;
}

/** 固定シードのrngからUUID v4形式の文字列を生成する（crypto.randomUUID()は非決定的なため使わない）。 */
function seededUuid(rng: () => number): string {
  const hex = () => Math.floor(rng() * 16).toString(16);
  const bytes = Array.from({ length: 32 }, hex);
  bytes[12] = "4"; // version 4
  bytes[16] = ((parseInt(bytes[16]!, 16) & 0x3) | 0x8).toString(16); // variant
  const s = bytes.join("");
  return `${s.slice(0, 8)}-${s.slice(8, 12)}-${s.slice(12, 16)}-${s.slice(16, 20)}-${s.slice(20)}`;
}

/**
 * 100人分の顧客データを生成する。全項目（マイナンバーを模した12桁の値を含む）は
 * 固定シードの擬似乱数のみから機械的に組み立てた架空データであり、実在の人物・
 * 実在の番号とは一切対応しない（生成方法の記録: docs/troubleshooting-log.md）。
 */
export function generateCustomers(count: number, seed: number): CustomerDetail[] {
  const rng = mulberry32(seed);
  const customers: CustomerDetail[] = [];

  for (let i = 0; i < count; i++) {
    const gender: Gender = rng() < 0.5 ? "male" : "female";
    const familyName = pick(rng, FAMILY_NAMES);
    const givenName = pick(rng, GIVEN_NAMES[gender]);
    const prefecture = pick(rng, PREFECTURES);
    const age = 20 + Math.floor(rng() * 60);

    customers.push({
      id: seededUuid(rng),
      name: `${familyName}${givenName}`,
      gender,
      prefecture,
      age,
      myNumber: randomDigits(rng, 12),
      address: `${prefecture}〇〇市${1 + Math.floor(rng() * 9)}丁目${1 + Math.floor(rng() * 9)}番${1 + Math.floor(rng() * 9)}号`,
      phone: `090-${randomDigits(rng, 4)}-${randomDigits(rng, 4)}`,
      // 氏名はローマ字化していないためASCII化できず、email用途にはインデックスのみを使う
      email: `customer${i}@example.com`,
    });
  }

  return customers;
}

export const customers: CustomerDetail[] = generateCustomers(100, 42);

export function toSummary(customer: CustomerDetail): CustomerSummary {
  const { id, name, gender, prefecture } = customer;
  return { id, name, gender, prefecture };
}

export interface CustomerSearchQuery {
  name?: string;
  gender?: Gender;
  prefecture?: string;
}

/** design-brief: 氏名（部分一致）/性別/都道府県、AND条件 */
export function searchCustomers(
  all: CustomerDetail[],
  query: CustomerSearchQuery,
): CustomerSummary[] {
  return all
    .filter((c) => !query.name || c.name.includes(query.name))
    .filter((c) => !query.gender || c.gender === query.gender)
    .filter((c) => !query.prefecture || c.prefecture === query.prefecture)
    .map(toSummary);
}

/** design-brief: Customer Detailsは顧客ID（UUID）による一意取得のみ */
export function getCustomerById(all: CustomerDetail[], id: string): CustomerDetail | undefined {
  return all.find((c) => c.id === id);
}
