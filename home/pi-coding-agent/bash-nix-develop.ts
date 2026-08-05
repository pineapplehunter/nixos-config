import {
  isToolCallEventType,
  type ExtensionAPI,
} from "@earendil-works/pi-coding-agent";

const NATIVE_BASH_PREFIX = "# pi:native\n";

function shellQuote(value: string): string {
  return `'${value.replaceAll("'", `'\\''`)}'`;
}

function inNixDevelop(command: string): string {
  return `nix develop --quiet -c bash -c ${shellQuote(command)}`;
}

export default function (pi: ExtensionAPI) {
  pi.on("before_agent_start", (event) => ({
    systemPrompt:
      `${event.systemPrompt}\n\n` +
      `All commands will run through the "nix develop -c" wrapper by default for convenience. ` +
      `When you need to debug the behaviour of nix develop itself, prefix the bash command ` +
      "with `# pi:native` on its own line to bypass the wrapper.",
  }));

  pi.on("tool_call", (event) => {
    if (!isToolCallEventType("bash", event)) {
      return;
    }

    if (event.input.command.startsWith(NATIVE_BASH_PREFIX)) {
      event.input.command = event.input.command.slice(NATIVE_BASH_PREFIX.length);
    } else {
      event.input.command = inNixDevelop(event.input.command);
    }
  });
}
