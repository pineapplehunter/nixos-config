import {
  createBashToolDefinition,
  type ExtensionAPI,
} from "@earendil-works/pi-coding-agent";

function shellQuote(value: string): string {
  return `'${value.replaceAll("'", `'\\''`)}'`;
}

function inNixDevelop(command: string): string {
  return `nix develop --quiet -c bash -c ${shellQuote(command)}`;
}

export default function (pi: ExtensionAPI) {
  const nixBash = createBashToolDefinition(process.cwd(), {
    spawnHook: (context) => ({
      ...context,
      command: inNixDevelop(context.command),
    }),
  });

  pi.registerTool({
    ...nixBash,
    name: "nix_bash",
    label: "Nix Bash",
    description:
      "Execute a bash command in the current flake's Nix development environment. Returns stdout and stderr. Output is truncated using the same limits as the built-in bash tool.",
    promptSnippet: "Execute bash commands in the current flake's Nix development environment",
    promptGuidelines: [
      "Use nix_bash for commands that need tools provided by the current flake's development shell.",
      "Use the built-in bash tool instead when debugging nix develop itself or when a command must run outside the development shell.",
    ],
    renderCall(args, theme, context) {
      const bashCall = nixBash.renderCall!(args, theme, {
        ...context,
        lastComponent: undefined,
      });
      return {
        render: (width) => [
          theme.fg("muted", "[nix_bash]"),
          ...bashCall.render(width),
        ],
        invalidate: () => bashCall.invalidate(),
      };
    },
  });
}
