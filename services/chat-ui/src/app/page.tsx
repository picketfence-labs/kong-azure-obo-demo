"use client";

import { useChat } from "@ai-sdk/react";
import { DefaultChatTransport } from "ai";
import { useState } from "react";

export default function Page() {
  const { messages, sendMessage, status } = useChat({
    transport: new DefaultChatTransport({ api: "/api/chat" }),
  });
  const [input, setInput] = useState("");

  return (
    <div className="flex flex-1 flex-col min-h-0 max-w-3xl w-full mx-auto p-4 gap-4">
      <div className="flex-1 min-h-0 overflow-y-auto flex flex-col gap-3">
        {messages.map((message) => (
          <div
            key={message.id}
            className={
              message.role === "user"
                ? "self-end rounded-lg bg-blue-600 text-white px-3 py-2 max-w-[80%] whitespace-pre-wrap"
                : "self-start rounded-lg bg-black/5 px-3 py-2 max-w-[80%] whitespace-pre-wrap"
            }
          >
            {message.parts.map((part, index) => {
              if (part.type === "text") {
                return <span key={index}>{part.text}</span>;
              }
              if (part.type.startsWith("tool-")) {
                return (
                  <div key={index} className="text-xs text-black/50 italic">
                    Tool呼び出し: {part.type.replace("tool-", "")}
                  </div>
                );
              }
              return null;
            })}
          </div>
        ))}
      </div>

      <form
        onSubmit={(event) => {
          event.preventDefault();
          if (input.trim()) {
            sendMessage({ text: input });
            setInput("");
          }
        }}
        className="flex gap-2"
      >
        <input
          value={input}
          onChange={(event) => setInput(event.target.value)}
          disabled={status !== "ready"}
          placeholder="顧客について質問してください（例: 島根県在住の女性を検索して）"
          className="flex-1 rounded border border-black/20 px-3 py-2"
        />
        <button
          type="submit"
          disabled={status !== "ready"}
          className="rounded bg-blue-600 text-white px-4 py-2 disabled:opacity-50"
        >
          送信
        </button>
      </form>
    </div>
  );
}
