import { request } from "node:http";
import { MAX_IMAGE_BYTES, type ParsedCodexResponse } from "./codex-response.js";

export async function hostImageRequest(socketPath: string, data: object, signal: AbortSignal): Promise<ParsedCodexResponse> {
  const body = Buffer.from(JSON.stringify(data));
  const failure = "Codex image broker disconnected. Check the host service before trying again; no automatic retry was made.";
  return new Promise((resolve, reject) => {
    const req = request({ socketPath, path: "/v1/image", method: "POST", signal, agent: false,
      headers: { "Content-Type": "application/json", "Content-Length": body.length },
    }, async (res) => {
      try {
        const chunks: Buffer[] = [];
        let size = 0;
        for await (const chunk of res) {
          size += chunk.length;
          if (size > Math.ceil(MAX_IMAGE_BYTES / 3) * 4 + 64 * 1024) throw new Error("Image broker response exceeded the size limit. No retry was made.");
          chunks.push(chunk);
        }
        const value = JSON.parse(Buffer.concat(chunks).toString("utf8"));
        if (res.statusCode !== 200) throw new Error(typeof value.error === "string" ? value.error : failure);
        resolve(value);
      } catch (error) { res.destroy(); reject(error); }
    });
    req.on("error", () => reject(signal.aborted ? signal.reason : new Error(failure)));
    req.end(body);
  });
}
