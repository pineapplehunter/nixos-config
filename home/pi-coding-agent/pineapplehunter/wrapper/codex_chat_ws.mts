// A WebSocket does not go through the broker's fetch guard. Construct its SDK
// request here with a fixed model endpoint and a host-resolved credential.
import { createHash } from "node:crypto";
import type { Api, Message, Model, ModelsApiStreamOptions, SimpleStreamOptions } from "@earendil-works/pi-ai";
import { normalizeContext } from "@PI_TRANSCRIPT@";
import { stream, streamSimple, closeOpenAICodexWebSocketSessions, resetOpenAICodexWebSocketDebugStats } from "@PI_CODEX_API@";

const leases = new Map<string, NodeJS.Timeout>();
function socketSession(namespace: string, token: string) {
  // No socket survives a change of credential. Never put a token in cache keys
  // or send it as the upstream prompt cache key.
  const id = createHash("sha256").update(token).update("\0").update(namespace).digest("hex");
  const previous = leases.get(id);
  if (previous) previous.refresh();
  else {
    if (leases.size >= 256) return undefined; // Permit the chat without retaining a socket.
    leases.set(id, setTimeout(() => {
      leases.delete(id);
      closeOpenAICodexWebSocketSessions(id);
      resetOpenAICodexWebSocketDebugStats(id);
    }, 30 * 60_000).unref());
  }
  return id;
}

export function socketClient(original: Model<Api>, messages: Message[], apiKey: string, session: string | undefined) {
  const model: Model<"openai-codex-responses"> = { ...original, api: "openai-codex-responses",
    provider: "openai-codex", baseUrl: "https://chatgpt.com/backend-api/codex/responses", headers: undefined };
  const context = normalizeContext({ messages });
  const auth = { apiKey, sessionId: session ? socketSession(session, apiKey) : undefined };
  return {
    stream: (options: ModelsApiStreamOptions<"openai-codex-responses">) => stream(model, context, { ...options, ...auth }),
    streamSimple: (options: SimpleStreamOptions) => streamSimple(model, context, { ...options, ...auth }),
  };
}
