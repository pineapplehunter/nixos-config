import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { Type } from "typebox";

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
      "Queue one or more commands in the background using pueue. Optionally set a timeout to wait for them.",
    promptSnippet: "Queue commands and optionally wait with a timeout",
    promptGuidelines: [
      "Use pueue for background commands and when multiple commands can be queued together.",
      "After using pueue, inspect a task's results with `pueue log <id>` with the bash tool.",
      "After using pueue, wait for all queued tasks to finish with `pueue wait` with bash tool.",
      "Use `pueue --help` for more information about pueue commands.",
    ],
    parameters: Type.Object({
      commands: Type.Array(
        Type.String({ minLength: 1, description: "Command to queue" }),
        { minItems: 1, description: "Commands to queue as separate pueue tasks" },
      ),
      timeout: Type.Integer({
        minimum: 0,
        description:
          "Maximum wait time in seconds; use 0 to return immediately without waiting",
      }),
    }),

    async execute(_toolCallId, params, signal, onUpdate, ctx) {
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

      if (params.timeout === 0) {
        return {
          content: [{ type: "text", text: `Queued pueue tasks:\n${queuedTasks}` }],
          details: { taskIds, commands: params.commands, waited: false },
        };
      }

      const timeoutSeconds = params.timeout;
      onUpdate?.({
        content: [
          {
            type: "text",
            text: `Queued pueue tasks:\n${queuedTasks}\nWaiting for completion...`,
          },
        ],
        details: {
          taskIds,
          commands: params.commands,
          waited: false,
          timeoutSeconds,
        },
      });

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
