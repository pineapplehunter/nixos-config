import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { Type } from "typebox";

export default function (pi: ExtensionAPI) {
  pi.registerTool({
    name: "notify",
    label: "Notify",
    description:
      "Send a local Discord notification to the user through the host notification service",
    promptSnippet: "Send the user a local notification through the host notification service",
    promptGuidelines: [
      "When using notify, use #57F287 for successful results, #ED4245 for failures, and omit color for neutral messages.",
    ],
    parameters: Type.Object({
      title: Type.String({ description: "Short notification title" }),
      content: Type.String({ description: "Notification body" }),
      color: Type.Optional(
        Type.String({
          description: "Optional Discord embed color in #RRGGBB form",
          pattern: "^#[0-9A-Fa-f]{6}$",
        }),
      ),
    }),
    async execute(_toolCallId, params, signal) {
      const args = [
        "--username",
        "pi",
        "--icon",
        "https://raw.githubusercontent.com/pineapplehunter/nixos-config/main/home/notification-icons/pi.png",
        "--title",
        params.title,
        "--content",
        params.content,
      ];
      if (params.color !== undefined) {
        args.push("--color", params.color);
      }

      const result = await pi.exec("local-notify", args, {
        signal,
        timeout: 5000,
      });
      if (result.code !== 0) {
        throw new Error(
          result.stderr.trim() || `local-notify exited with status ${result.code}`,
        );
      }
      return {
        content: [{ type: "text", text: "Notification sent." }],
        details: {},
      };
    },
  });
}
