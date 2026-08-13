import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { Container, Text } from "@earendil-works/pi-tui";
import { Type } from "typebox";

function formatDuration(ms: number): string {
  return `${(ms / 1000).toFixed(1)}s`;
}

function getTextOutput(result: { content: Array<{ type: string; text?: string }> }): string {
  return result.content
    .filter((item) => item.type === "text")
    .map((item) => item.text ?? "")
    .join("\n");
}

function styleOutput(output: string, color: (text: string) => string): string {
  return output
    .split("\n")
    .map(color)
    .join("\n");
}

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
          `Timed out after ${timeoutSeconds} seconds waiting for pueue tasks. The tasks remain managed by pueue.\n\nQueued pueue tasks:\n${queuedTasks}`,
        );
      }
      if (waitResult.code !== 0) {
        throw new Error(
          `Failed while waiting for pueue tasks: ${waitResult.stderr || waitResult.stdout}\n\nQueued pueue tasks:\n${queuedTasks}`,
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

    renderCall(_args, theme, context) {
      const state = context.state as {
        startedAt?: number;
        endedAt?: number;
        interval?: ReturnType<typeof setInterval>;
      };
      if (context.executionStarted && state.startedAt === undefined) {
        state.startedAt = Date.now();
        state.endedAt = undefined;
      }

      const text = (context.lastComponent as Text | undefined) ?? new Text("", 0, 0);
      text.setText(theme.fg("toolTitle", theme.bold("Pueue")));
      return text;
    },

    renderResult(result, options, theme, context) {
      const state = context.state as {
        startedAt?: number;
        endedAt?: number;
        interval?: ReturnType<typeof setInterval>;
      };
      if (state.startedAt !== undefined && options.isPartial && !state.interval) {
        state.interval = setInterval(() => context.invalidate(), 1000);
      }
      if (!options.isPartial || context.isError) {
        state.endedAt ??= Date.now();
        if (state.interval) {
          clearInterval(state.interval);
          state.interval = undefined;
        }
      }

      const component =
        (context.lastComponent as Container | undefined) ?? new Container();
      component.clear();

      const output = getTextOutput(result);
      if (output) {
        component.addChild(
          new Text(
            `\n${styleOutput(output, (line) => theme.fg("toolOutput", line))}`,
            0,
            0,
          ),
        );
      }
      if (state.startedAt !== undefined) {
        const label = options.isPartial ? "Elapsed" : "Took";
        const endTime = state.endedAt ?? Date.now();
        component.addChild(
          new Text(
            `\n${theme.fg("muted", `${label} ${formatDuration(endTime - state.startedAt)}`)}`,
            0,
            0,
          ),
        );
      }

      component.invalidate();
      return component;
    },
  });
}
