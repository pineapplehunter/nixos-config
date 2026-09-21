import { StringEnum } from "@earendil-works/pi-ai";
import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";
import { Type } from "typebox";

const PORTAL_TIMEOUT_MS = 125_000;

function resultText(text: string) {
  return { content: [{ type: "text" as const, text }], details: {} };
}

async function runPortal(
  pi: ExtensionAPI,
  command: string,
  args: string[],
  signal: AbortSignal | undefined,
) {
  const result = await pi.exec(command, args, {
    signal,
    timeout: PORTAL_TIMEOUT_MS,
  });
  const message = result.stderr.trim();
  if (result.code === 2) return resultText(message || "Portal request cancelled by the user.");
  if (result.killed || signal?.aborted) return resultText("Portal request cancelled.");
  if (result.code !== 0) {
    throw new Error(message || `${command} exited with status ${result.code}`);
  }
  return result;
}

async function confirm(ctx: ExtensionContext, action: string): Promise<boolean> {
  if (!ctx.hasUI) throw new Error(`${action} requires an interactive user confirmation`);
  return ctx.ui.confirm("Desktop portal", action, { signal: ctx.signal });
}

export default function (pi: ExtensionAPI) {
  pi.registerTool({
    name: "open_uri",
    label: "Open URI",
    description: "Ask the user, then open an HTTP or HTTPS URI in a host application",
    promptSnippet: "Open an explicitly requested HTTP or HTTPS URI through the desktop portal",
    promptGuidelines: [
      "Use open_uri only when the user explicitly asks to open an HTTP or HTTPS URI, and never for file:// URIs.",
    ],
    parameters: Type.Object({ uri: Type.String({ description: "HTTP or HTTPS URI" }) }),
    async execute(_id, params, signal, _update, ctx) {
      if (!(await confirm(ctx, `Open this URI on the host?\n${params.uri}`))) {
        return resultText("Opening the URI was cancelled by the user.");
      }
      const result = await runPortal(pi, "pi-open-uri", ["--timeout", "120", params.uri], signal);
      return "code" in result
        ? resultText("URI opened through the desktop portal.")
        : result;
    },
  });

  pi.registerTool({
    name: "choose_file",
    label: "Choose File or Folder",
    description:
      "Show the host file chooser and return one sandbox-visible file or folder path with the requested read-only or read/write access",
    promptSnippet:
      "Choose a host file or folder with read-only or read/write access through the desktop portal",
    promptGuidelines: [
      "Use choose_file only when the user explicitly asks to choose a host file or folder; request read/write access only when the user explicitly needs to modify it, and use the returned /run/flatpak/doc or /run/flatpak/doc-rw path.",
    ],
    parameters: Type.Object({
      title: Type.Optional(Type.String({ description: "Optional file chooser title" })),
      kind: Type.Optional(
        StringEnum(["file", "folder"] as const, {
          description: "Type of item to choose (default: file)",
        }),
      ),
      access: Type.Optional(
        StringEnum(["read", "read-write"] as const, {
          description: "Required sandbox access (default: read)",
        }),
      ),
    }),
    async execute(_id, params, signal) {
      const kind = params.kind ?? "file";
      const access = params.access ?? "read";
      const args = ["--timeout", "120"];
      if (params.title) args.push("--title", params.title);
      if (kind === "folder") args.push("--directory");
      if (access === "read-write") args.push("--writable");
      const result = await runPortal(pi, "pi-choose-file", args, signal);
      if ("code" in result) {
        const path = result.stdout.trim();
        return resultText(
          `Selected sandbox-visible ${kind} (${access}): ${path}`,
        );
      }
      return result;
    },
  });
}
