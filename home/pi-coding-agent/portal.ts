import { stat } from "node:fs/promises";
import { resolve } from "node:path";
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
    name: "open_file",
    label: "Open File",
    description: "Ask the user, then open a sandbox-visible regular file in a host application",
    promptSnippet: "Open an explicitly requested file through the desktop portal",
    promptGuidelines: [
      "Use open_file only when the user explicitly asks to open a file. To open generated or raw content, first write it to a project or /tmp file and pass that path to open_file.",
    ],
    parameters: Type.Object({ path: Type.String({ description: "Project or /tmp file path" }) }),
    async execute(_id, params, signal, _update, ctx) {
      const path = resolve(ctx.cwd, params.path.replace(/^@/, ""));
      const info = await stat(path);
      if (!info.isFile()) throw new Error(`Not a regular file: ${path}`);
      if (!(await confirm(ctx, `Open this file on the host?\n${path}`))) {
        return resultText("Opening the file was cancelled by the user.");
      }
      const result = await runPortal(pi, "pi-open-file", ["--timeout", "120", path], signal);
      return "code" in result
        ? resultText(`File opened through the desktop portal: ${path}`)
        : result;
    },
  });

  pi.registerTool({
    name: "choose_file",
    label: "Choose File",
    description: "Show the host file chooser and return one read-only sandbox-visible file path",
    promptSnippet: "Choose a host file through the desktop portal when explicitly requested",
    promptGuidelines: [
      "Use choose_file only when the user explicitly asks to choose a host file; use its returned /run/flatpak/doc path to read the selected file.",
    ],
    parameters: Type.Object({
      title: Type.Optional(Type.String({ description: "Optional file chooser title" })),
    }),
    async execute(_id, params, signal) {
      const args = ["--timeout", "120"];
      if (params.title) args.push("--title", params.title);
      const result = await runPortal(pi, "pi-choose-file", args, signal);
      if ("code" in result) {
        const path = result.stdout.trim();
        return resultText(`Selected sandbox-visible file: ${path}`);
      }
      return result;
    },
  });
}
