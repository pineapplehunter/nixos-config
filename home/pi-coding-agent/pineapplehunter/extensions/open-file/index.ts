import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

const PORTAL_TIMEOUT_MS = 125_000;

class PortalCancelled extends Error {}

async function choosePath(
  pi: ExtensionAPI,
  kind: "file" | "directory",
  access: "read-only" | "read-write",
): Promise<string> {
  const args = ["--timeout", "120"];
  args.push("--title", `Choose a ${kind} for Pi`);
  if (kind === "directory") args.push("--directory");
  if (access === "read-write") args.push("--writable");

  // Do not tie this user-initiated operation to an agent turn's abort signal.
  const result = await pi.exec("pi-choose-file", args, {
    timeout: PORTAL_TIMEOUT_MS,
  });
  const message = result.stderr.trim();
  if (result.code === 2) {
    throw new PortalCancelled(message || "File chooser cancelled by the user.");
  }
  if (result.code !== 0) {
    throw new Error(message || `pi-choose-file exited with status ${result.code}`);
  }

  const path = result.stdout.trim();
  if (!path) throw new Error("The file chooser returned an empty path.");
  return path;
}

export default function (pi: ExtensionAPI) {
  pi.registerCommand("open-file", {
    description: "Mount a host file or directory and provide its path to the agent",
    handler: async (_args, ctx) => {
      if (!ctx.hasUI) {
        ctx.ui.notify("/open-file requires an interactive UI.", "error");
        return;
      }

      const kindChoice = await ctx.ui.select("What do you want to open?", [
        "File",
        "Directory",
      ]);
      if (!kindChoice) return;
      const kind = kindChoice === "Directory" ? "directory" : "file";

      const accessChoice = await ctx.ui.select("Required access", [
        "Read-only",
        "Read/write",
      ]);
      if (!accessChoice) return;
      const access = accessChoice === "Read/write" ? "read-write" : "read-only";

      const userContext = await ctx.ui.editor(
        `Optional context for this ${kind} (submit empty for none)`,
        "",
      );
      if (userContext === undefined) return;

      try {
        const path = await choosePath(pi, kind, access);
        const accessNotice =
          access === "read-write"
            ? "This path provides direct read/write access to the host object. Copy it to persistent /tmp only if an independent copy is desired."
            : "If the contents are needed later, consider copying them to persistent /tmp.";
        const context = userContext.trim() || "No additional context was provided.";

        pi.sendMessage(
          {
            customType: "mounted-path",
            content: `The user mounted a ${access} ${kind} at:\n${path}\n\nThis portal-mounted path is temporary and may disappear at any point. ${accessNotice}\n\nUser context:\n${context}`,
            display: true,
            details: { kind, access, path, userContext: userContext.trim() },
          },
          { deliverAs: "nextTurn", triggerTurn: false },
        );
        ctx.ui.notify(`Mounted ${kind}: ${path}`, "info");
      } catch (error) {
        if (error instanceof PortalCancelled) {
          ctx.ui.notify(error.message, "info");
          return;
        }
        const message = error instanceof Error ? error.message : String(error);
        ctx.ui.notify(`Unable to mount ${kind}: ${message}`, "error");
      }
    },
  });
}
