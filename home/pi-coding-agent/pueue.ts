import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { Type } from "typebox";

const DEFAULT_WAIT_TIMEOUT_SECONDS = 600;

function shellQuote(value: string): string {
  return `'${value.replaceAll("'", `'\\''`)}'`;
}

function inNixDevelop(command: string): string {
  return `nix develop --quiet -c bash -c ${shellQuote(command)}`;
}

export default function (pi: ExtensionAPI) {
  pi.registerTool({
    name: "pueue",
    label: "Pueue",
    description:
      "Queue one or more commands with pueue. Commands run in the current flake's Nix development environment. Optionally wait for only the newly queued tasks. The timeout is in seconds and is ignored when wait is false.",
    promptSnippet:
      "Queue multiple long-running commands, optionally waiting for their completion",
    promptGuidelines: [
      "Use pueue for long-running commands and when multiple commands can be queued together.",
    ],
    parameters: Type.Object({
      commands: Type.Array(
        Type.String({ minLength: 1, description: "Command to queue" }),
        { minItems: 1, description: "Commands to queue as separate pueue tasks" },
      ),
      wait: Type.Optional(
        Type.Boolean({
          description: "Wait for the newly queued tasks to finish (default: false)",
        }),
      ),
      timeout: Type.Optional(
        Type.Integer({
          minimum: 1,
          description:
            "Maximum wait time in seconds (default: 600); ignored when wait is false",
        }),
      ),
    }),

    async execute(_toolCallId, params, signal, _onUpdate, ctx) {
      const taskIds: string[] = [];

      for (const command of params.commands) {
        const result = await pi.exec(
          "pueue",
          [
            "add",
            "--print-task-id",
            "--working-directory",
            ctx.cwd,
            "--",
            inNixDevelop(command),
          ],
          { signal },
        );

        if (result.code !== 0) {
          const queued = taskIds.length > 0 ? ` Tasks already queued: ${taskIds.join(", ")}.` : "";
          throw new Error(
            `Failed to queue command ${JSON.stringify(command)}: ${result.stderr || result.stdout}.${queued}`,
          );
        }

        const taskId = result.stdout.trim();
        if (!/^\d+$/.test(taskId)) {
          throw new Error(
            `pueue returned an invalid task id for ${JSON.stringify(command)}: ${JSON.stringify(taskId)}`,
          );
        }
        taskIds.push(taskId);
      }

      const queuedTasks = taskIds
        .map((taskId, index) => `- ${taskId}: ${params.commands[index]}`)
        .join("\n");

      if (!params.wait) {
        return {
          content: [{ type: "text", text: `Queued pueue tasks:\n${queuedTasks}` }],
          details: { taskIds, commands: params.commands, waited: false },
        };
      }

      const timeoutSeconds = params.timeout ?? DEFAULT_WAIT_TIMEOUT_SECONDS;
      const waitResult = await pi.exec(
        "pueue",
        ["wait", "--quiet", "--", ...taskIds],
        { signal, timeout: timeoutSeconds * 1000 },
      );

      if (waitResult.killed) {
        throw new Error(
          `Timed out after ${timeoutSeconds} seconds waiting for pueue tasks ${taskIds.join(", ")}. The tasks remain managed by pueue.`,
        );
      }
      if (waitResult.code !== 0) {
        throw new Error(
          `Failed while waiting for pueue tasks ${taskIds.join(", ")}: ${waitResult.stderr || waitResult.stdout}`,
        );
      }

      return {
        content: [
          { type: "text", text: `Pueue tasks finished:\n${queuedTasks}` },
        ],
        details: {
          taskIds,
          commands: params.commands,
          waited: true,
          timeoutSeconds,
        },
      };
    },
  });
}
