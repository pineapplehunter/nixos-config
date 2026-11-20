import { randomUUID } from "node:crypto";
import { readFile } from "node:fs/promises";
import { join } from "node:path";
import { ModelRuntime } from "@PI_RUNTIME@/index.js";
import { runAuthLogin } from "@PI_RUNTIME@/cli/auth-login.js";
import { createProcessLoginTerminal } from "@PI_RUNTIME@/cli/auth-terminal.js";
import { extractImageAccountId, imageAuthProvider, IMAGE_AUTH_PROVIDER } from "@IMAGE_PACKAGE@/src/image-oauth.js";
import { buildImagesRequest } from "@IMAGE_PACKAGE@/src/images-request.js";
import { MAX_IMAGE_BYTES, parseCodexImages, parseCodexSse } from "@IMAGE_PACKAGE@/src/codex-response.js";

const MiB = 1024 * 1024;
const MAX_INPUT = 50 * MiB;
export const IMAGE_BODY_LIMIT = 4 * Math.ceil(MAX_INPUT / 3) + 512 * 1024;
const BASE = "https://chatgpt.com/backend-api/codex";
const accounts = ["work", "personal"];
const DEFAULT_MODEL = "gpt-6-astra";

async function imageRuntime(dir) {
  const runtime = await ModelRuntime.create({ authPath: join(dir, "auth.json"), modelsPath: null, refreshOnCreate: false });
  runtime.registerNativeProvider(imageAuthProvider);
  return runtime;
}

export async function imageAuth(operation, dir) {
  const runtime = await imageRuntime(dir);
  if (operation === "status") {
    const ready = (await runtime.checkAuth(IMAGE_AUTH_PROVIDER))?.type === "oauth";
    console.log(ready ? "configured" : "not configured");
    return ready ? 0 : 1;
  }
  if (operation === "logout") { await runtime.logout(IMAGE_AUTH_PROVIDER); return 0; }
  if (operation !== "login") return 2;
  const controller = new AbortController();
  const interrupt = () => controller.abort();
  process.on("SIGINT", interrupt);
  try {
    return await runAuthLogin([IMAGE_AUTH_PROVIDER], {
      modelRuntime: runtime, agentDir: dir, cwd: dir, signal: controller.signal,
      terminal: createProcessLoginTerminal(interrupt),
    });
  } finally {
    process.off("SIGINT", interrupt);
    await runtime.settleCredentialWrites();
  }
}

function validImage(input) {
  const { mimeType, data } = input ?? {};
  if (typeof data !== "string" || data.length > 4 * Math.ceil(20 * MiB / 3) || !data.length ||
      data.length % 4 || /[^A-Za-z0-9+/=]/.test(data)) return;
  const bytes = Buffer.from(data, "base64");
  if (bytes.length > 20 * MiB) return;
  if (mimeType === "image/png" && bytes.subarray(0, 8).equals(Buffer.from([137, 80, 78, 71, 13, 10, 26, 10])) ||
      mimeType === "image/jpeg" && bytes[0] === 255 && bytes[1] === 216 && bytes[2] === 255 ||
      mimeType === "image/webp" && bytes.toString("ascii", 0, 4) === "RIFF" && bytes.toString("ascii", 8, 12) === "WEBP") return bytes.length;
}

const failure = (status, error) => [status, { error }];

export function createImageHandler(state, findModel, openRuntime = imageRuntime) {
  const runtimes = new Map();
  let active = 0;
  return async (readBody, signal) => {
    if (active >= 2) return failure(429, "Image broker is busy. No generation request was made.");
    active++;
    try {
      const account = await readFile(join(state, "image-account"), "utf8").then((value) => value.trim(), (error) => {
        if (error.code === "ENOENT") return "work";
        throw error;
      });
      if (!accounts.includes(account)) return failure(503, "Host image generation is off. Configure pi-codex-auth on the host.");
      const data = await readBody();
      const { prompt, background, outputFormat, transport, inputImages, model, sessionId } = data ?? {};
      if (typeof prompt !== "string" || !prompt.trim() || prompt.length > 32000 ||
          !["png", "jpeg", "webp"].includes(outputFormat) ||
          (background !== undefined && !["auto", "opaque", "transparent"].includes(background)) ||
          (background === "transparent" && outputFormat === "jpeg") ||
          !["responses", "images"].includes(transport) ||
          (transport === "images" && (outputFormat !== "png" || model !== undefined)) ||
          !Array.isArray(inputImages) || inputImages.length > 5) return failure(400, "Invalid image request. No generation request was made.");
      let total = 0;
      for (const image of inputImages) {
        const bytes = validImage(image);
        if (!bytes || (total += bytes) > MAX_INPUT) return failure(400, "Invalid or oversized reference image. No generation request was made.");
      }
      const routingModel = model ?? DEFAULT_MODEL;
      if (transport === "responses" && (typeof routingModel !== "string" || !findModel(routingModel))) {
        return failure(400, "Unknown Codex routing model. Refresh the model catalog or omit the model override.");
      }
      if (!runtimes.has(account)) {
        runtimes.set(account, openRuntime(join(state, "images", account)).catch((error) => {
          runtimes.delete(account);
          throw error;
        }));
      }
      const runtime = await runtimes.get(account);
      let token, accountId;
      try {
        if ((await runtime.checkAuth(IMAGE_AUTH_PROVIDER, { signal }))?.type === "oauth") {
          token = (await runtime.getAuth(IMAGE_AUTH_PROVIDER, { signal }))?.auth.apiKey;
          if (token) accountId = extractImageAccountId(token);
        }
      } catch { /* No credential diagnostics cross the socket. */ }
      if (!accountId) return failure(401, `Run pi-codex-auth image-login ${account} on the host.`);
      const images = transport === "images";
      const endpoint = images ? `${BASE}/images/${inputImages.length ? "edits" : "generations"}` : `${BASE}/responses`;
      const payload = images ? buildImagesRequest(prompt, background, inputImages) : {
        model: routingModel, store: false, stream: true,
        prompt_cache_key: typeof sessionId === "string" && /^[\w-]{1,128}$/.test(sessionId) ? sessionId : undefined,
        instructions: "Generate a bitmap image. Call the image_generation tool exactly once.",
        input: [{ role: "user", content: [{ type: "input_text", text: prompt }, ...inputImages.map(({ mimeType, data }) => ({
          type: "input_image", image_url: `data:${mimeType};base64,${data}`,
        }))] }],
        tools: [{ type: "image_generation", output_format: outputFormat, background }],
        tool_choice: "auto", parallel_tool_calls: false, text: { verbosity: "low" },
      };
      signal.throwIfAborted();
      const response = await fetch(endpoint, { method: "POST", redirect: "error", signal,
        headers: { Authorization: `Bearer ${token}`, "chatgpt-account-id": accountId, originator: "pi",
          "OpenAI-Beta": "responses=experimental", "content-type": "application/json", "x-client-request-id": randomUUID(),
          accept: images ? "application/json" : "text/event-stream", ...(images ? { "x-codex-image-turn-id": randomUUID() } : {}) },
        body: JSON.stringify(payload),
      });
      if (!response.ok) {
        void response.body?.cancel().catch(() => {});
        return failure(response.status, `Codex Images rejected the ${account} request (HTTP ${response.status}). No retry was made.`);
      }
      const parsed = await (images ? parseCodexImages : parseCodexSse)(response, signal, [token, accountId]);
      if (!parsed.image) return failure(502, "Codex returned no image. No retry was made.");
      if (parsed.image.result.length > 4 * Math.ceil(MAX_IMAGE_BYTES / 3)) return failure(502, "Codex image exceeded the output limit. No retry was made.");
      return [200, parsed];
    } catch {
      return failure(502, "Codex image request did not complete. It may have used quota; no retry was made.");
    } finally { active--; }
  };
}
