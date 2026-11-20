import { randomUUID } from "node:crypto";
import { readFile } from "node:fs/promises";
import { join } from "node:path";
import { hasCode, isAccount, list, record, type Account } from "./codex_protocol.mts";
import { ModelRuntime } from "@PI_RUNTIME@/index.js";
import { runAuthLogin } from "@PI_RUNTIME@/cli/auth-login.js";
import { createProcessLoginTerminal } from "@PI_RUNTIME@/cli/auth-terminal.js";
import {
  extractImageAccountId,
  imageAuthProvider,
  IMAGE_AUTH_PROVIDER,
} from "@IMAGE_PACKAGE@/src/image-oauth.js";
import { buildImagesRequest } from "@IMAGE_PACKAGE@/src/images-request.js";
import {
  MAX_IMAGE_BYTES,
  parseCodexImages,
  parseCodexSse,
} from "@IMAGE_PACKAGE@/src/codex-response.js";

const MiB = 1024 * 1024;
const MAX_INPUT = 50 * MiB;
export const IMAGE_BODY_LIMIT = 4 * Math.ceil(MAX_INPUT / 3) + 512 * 1024;
const BASE = "https://chatgpt.com/backend-api/codex";
const DEFAULT_MODEL = "gpt-6-astra";

async function imageRuntime(dir: string) {
  const runtime = await ModelRuntime.create({
    authPath: join(dir, "auth.json"),
    modelsPath: null,
    refreshOnCreate: false,
  });
  runtime.registerNativeProvider(imageAuthProvider);
  return runtime;
}

export async function imageAuth(operation: string, dir: string) {
  const runtime = await imageRuntime(dir);
  if (operation === "status") {
    const ready = (await runtime.checkAuth(IMAGE_AUTH_PROVIDER))?.type === "oauth";
    console.log(ready ? "configured" : "not configured");
    return ready ? 0 : 1;
  }
  if (operation === "logout") {
    await runtime.logout(IMAGE_AUTH_PROVIDER);
    return 0;
  }
  if (operation !== "login") return 2;
  const controller = new AbortController();
  const interrupt = () => controller.abort();
  process.on("SIGINT", interrupt);
  try {
    return await runAuthLogin([IMAGE_AUTH_PROVIDER], {
      modelRuntime: runtime,
      agentDir: dir,
      cwd: dir,
      signal: controller.signal,
      getDeviceId: randomUUID,
      terminal: createProcessLoginTerminal(interrupt),
    });
  } finally {
    process.off("SIGINT", interrupt);
    await runtime.settleCredentialWrites();
  }
}

type InputImage = { mimeType: "image/png" | "image/jpeg" | "image/webp"; data: string };

function validImage(input: unknown): { image: InputImage; size: number } | undefined {
  const { mimeType, data } = record(input) ?? {};
  if (
    typeof data !== "string" ||
    data.length > 4 * Math.ceil((20 * MiB) / 3) ||
    !data.length ||
    data.length % 4 ||
    /[^A-Za-z0-9+/=]/.test(data)
  )
    return;
  const bytes = Buffer.from(data, "base64");
  if (bytes.length > 20 * MiB) return;
  if (
    (mimeType === "image/png" &&
      bytes.subarray(0, 8).equals(Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]))) ||
    (mimeType === "image/jpeg" && bytes[0] === 255 && bytes[1] === 216 && bytes[2] === 255) ||
    (mimeType === "image/webp" &&
      bytes.toString("ascii", 0, 4) === "RIFF" &&
      bytes.toString("ascii", 8, 12) === "WEBP")
  ) {
    if (bytes.length > 0) return { image: { mimeType, data }, size: bytes.length };
  }
  return undefined;
}

const failure = (status: number, error: string) => [status, { error }] as const;

type ImageRuntime = Pick<ModelRuntime, "checkAuth" | "getAuth">;

export function createImageHandler(
  state: string,
  findModel: (id: string) => unknown,
  openRuntime: (dir: string) => Promise<ImageRuntime> = imageRuntime,
) {
  const runtimes = new Map<Account, Promise<ImageRuntime>>();
  let active = 0;
  return async (readBody: () => Promise<unknown>, signal: AbortSignal) => {
    if (active >= 2) return failure(429, "Image broker is busy. No generation request was made.");
    active++;
    try {
      const account = await readFile(join(state, "image-account"), "utf8").then(
        (value) => value.trim(),
        (error: unknown) => {
          if (hasCode(error, "ENOENT")) return "work";
          throw error;
        },
      );
      if (!isAccount(account))
        return failure(503, "Host image generation is off. Configure pi-codex-auth on the host.");
      const {
        prompt,
        background,
        outputFormat,
        transport,
        inputImages: references,
        model,
        sessionId,
      } = record(await readBody()) ?? {};
      if (
        typeof prompt !== "string" ||
        !prompt.trim() ||
        prompt.length > 32000 ||
        (outputFormat !== "png" && outputFormat !== "jpeg" && outputFormat !== "webp") ||
        (background !== undefined &&
          background !== "auto" &&
          background !== "opaque" &&
          background !== "transparent") ||
        (background === "transparent" && outputFormat === "jpeg") ||
        (transport !== "responses" && transport !== "images") ||
        (transport === "images" && (outputFormat !== "png" || model !== undefined)) ||
        !Array.isArray(references) ||
        references.length > 5
      )
        return failure(400, "Invalid image request. No generation request was made.");
      let total = 0;
      const inputImages: InputImage[] = [];
      for (const reference of list(references)) {
        const decoded = validImage(reference);
        if (!decoded || (total += decoded.size) > MAX_INPUT)
          return failure(
            400,
            "Invalid or oversized reference image. No generation request was made.",
          );
        inputImages.push(decoded.image);
      }
      const routingModel = model ?? DEFAULT_MODEL;
      if (
        transport === "responses" &&
        (typeof routingModel !== "string" || !findModel(routingModel))
      ) {
        return failure(
          400,
          "Unknown Codex routing model. Refresh the model catalog or omit the model override.",
        );
      }
      let pending = runtimes.get(account);
      if (!pending) {
        pending = openRuntime(join(state, "images", account)).catch((error: unknown) => {
          runtimes.delete(account);
          throw error;
        });
        runtimes.set(account, pending);
      }
      const runtime = await pending;
      let token: string | undefined;
      let accountId: string | undefined;
      try {
        if ((await runtime.checkAuth(IMAGE_AUTH_PROVIDER, { signal }))?.type === "oauth") {
          token = (await runtime.getAuth(IMAGE_AUTH_PROVIDER, { signal }))?.auth.apiKey;
          if (token) accountId = extractImageAccountId(token);
        }
      } catch {
        /* No credential diagnostics cross the socket. */
      }
      if (!token || !accountId)
        return failure(401, `Run pi-codex-auth image-login ${account} on the host.`);
      const images = transport === "images";
      const endpoint = images
        ? `${BASE}/images/${inputImages.length ? "edits" : "generations"}`
        : `${BASE}/responses`;
      const payload = images
        ? buildImagesRequest(prompt, background, inputImages)
        : {
            model: routingModel,
            store: false,
            stream: true,
            prompt_cache_key:
              typeof sessionId === "string" && /^[\w-]{1,128}$/.test(sessionId)
                ? sessionId
                : undefined,
            instructions: "Generate a bitmap image. Call the image_generation tool exactly once.",
            input: [
              {
                role: "user",
                content: [
                  { type: "input_text", text: prompt },
                  ...inputImages.map(({ mimeType, data }) => ({
                    type: "input_image",
                    image_url: `data:${mimeType};base64,${data}`,
                  })),
                ],
              },
            ],
            tools: [{ type: "image_generation", output_format: outputFormat, background }],
            tool_choice: "auto",
            parallel_tool_calls: false,
            text: { verbosity: "low" },
          };
      signal.throwIfAborted();
      const response = await fetch(endpoint, {
        method: "POST",
        redirect: "error",
        signal,
        headers: {
          Authorization: `Bearer ${token}`,
          "chatgpt-account-id": accountId,
          originator: "pi",
          "OpenAI-Beta": "responses=experimental",
          "content-type": "application/json",
          "x-client-request-id": randomUUID(),
          accept: images ? "application/json" : "text/event-stream",
          ...(images ? { "x-codex-image-turn-id": randomUUID() } : {}),
        },
        body: JSON.stringify(payload),
      });
      if (!response.ok) {
        void response.body?.cancel().catch(() => {});
        return failure(
          response.status,
          `Codex Images rejected the ${account} request (HTTP ${response.status}). No retry was made.`,
        );
      }
      const parsed = await (images ? parseCodexImages : parseCodexSse)(response, signal, [
        token,
        accountId,
      ]);
      if (!parsed.image) return failure(502, "Codex returned no image. No retry was made.");
      if (parsed.image.result.length > 4 * Math.ceil(MAX_IMAGE_BYTES / 3))
        return failure(502, "Codex image exceeded the output limit. No retry was made.");
      return [200, parsed] as const;
    } catch {
      return failure(
        502,
        "Codex image request did not complete. It may have used quota; no retry was made.",
      );
    } finally {
      active--;
    }
  };
}
