import type { Metadata } from "next";
import { headers } from "next/headers";
import { Geist, Geist_Mono } from "next/font/google";
import "./globals.css";

const geistSans = Geist({
  variable: "--font-geist-sans",
  subsets: ["latin"],
});

const geistMono = Geist_Mono({
  variable: "--font-geist-mono",
  subsets: ["latin"],
});

export const metadata: Metadata = {
  title: "Kong OBO Demo Chat",
  description: "Kong Gateway Entra ID OBO x AI MCP Proxy ACL デモ",
};

// ログイン中のユーザー情報はKong(kong/login-route.yaml)のopenid-connectが
// upstream_headersでこのアプリへ転送する。このアプリ自身はOAuthクライアントを持たない
// （design-brief 3節）。
export default async function RootLayout({ children }: LayoutProps<"/">) {
  const headerList = await headers();
  const userName = headerList.get("x-user-name");
  const userEmail = headerList.get("x-user-email");

  return (
    <html
      lang="ja"
      className={`${geistSans.variable} ${geistMono.variable} h-full antialiased`}
    >
      <body className="min-h-full flex flex-col">
        <header className="flex items-center justify-between border-b border-black/10 px-4 py-2 text-sm">
          <span className="font-semibold">Kong OBO Demo</span>
          {userName ? (
            <div className="flex items-center gap-3">
              <span>
                ログイン中: {userName}
                {userEmail ? `（${userEmail}）` : ""}
              </span>
              <form action="/?logout" method="POST">
                <button
                  type="submit"
                  className="rounded border border-black/20 px-2 py-1 hover:bg-black/5"
                >
                  ログアウト
                </button>
              </form>
            </div>
          ) : (
            <span className="text-black/50">未ログイン</span>
          )}
        </header>
        <main className="flex-1 flex flex-col min-h-0">{children}</main>
      </body>
    </html>
  );
}
