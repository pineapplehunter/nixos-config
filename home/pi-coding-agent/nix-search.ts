import { mkdtemp, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import {
  DEFAULT_MAX_BYTES,
  DEFAULT_MAX_LINES,
  formatSize,
  truncateHead,
  type ExtensionAPI,
} from "@earendil-works/pi-coding-agent";
import { Type } from "typebox";

const DEFAULT_TIMEOUT = 10_000;

interface NixSearchResult {
  package_pname: string;
  package_attr_name: string;
  package_pversion: string;
}

function formatResults(results: NixSearchResult[]): string {
  if (results.length === 0) {
    return "(no results)";
  }

  return results
    .map((pkg) => {
      const name = pkg.package_attr_name || pkg.package_pname;
      return pkg.package_pversion ? `${name} @ ${pkg.package_pversion}` : name;
    })
    .join("\n");
}

export default function (pi: ExtensionAPI) {
  pi.registerTool({
    name: "nix-search",
    label: "Nix Search",
    description:
      `Search for packages in nixpkgs by name or attribute path using the search.nixos.org index. ` +
      `Output is truncated to ${DEFAULT_MAX_LINES} lines or ${formatSize(DEFAULT_MAX_BYTES)}; full truncated output is saved to a temporary file.`,
    promptSnippet: "Search nixpkgs packages by package name, command, or attribute path",
    promptGuidelines: [
      "Use nix-search to find nixpkgs package attribute names instead of guessing them.",
    ],
    parameters: Type.Object({
      query: Type.String({ description: "Package name or command to search for" }),
    }),

    async execute(_toolCallId, params, signal, _onUpdate, ctx) {
      const result = await pi.exec("nix-search", ["--json", params.query], {
        cwd: ctx.cwd,
        signal,
        timeout: DEFAULT_TIMEOUT,
      });

      if (result.stderr) {
        throw new Error(result.stderr.trim());
      }
      if (result.killed) {
        throw new Error(`nix-search timed out after ${DEFAULT_TIMEOUT / 1000} seconds`);
      }
      if (result.code !== 0) {
        throw new Error(`nix-search exited with status ${result.code}`);
      }

      let results: NixSearchResult[];
      try {
        results = result.stdout
          .trim()
          .split("\n")
          .filter(Boolean)
          .map((line) => JSON.parse(line) as NixSearchResult);
      } catch (error) {
        const message = error instanceof Error ? error.message : String(error);
        throw new Error(`Could not parse nix-search output: ${message}`);
      }

      const output = formatResults(results);
      const truncation = truncateHead(output, {
        maxLines: DEFAULT_MAX_LINES,
        maxBytes: DEFAULT_MAX_BYTES,
      });
      let text = truncation.content;
      let fullOutputPath: string | undefined;

      if (truncation.truncated) {
        const directory = await mkdtemp(join(tmpdir(), "pi-nix-search-"));
        fullOutputPath = join(directory, "output.txt");
        await writeFile(fullOutputPath, output, "utf8");
        text +=
          `\n\n[Output truncated: showing ${truncation.outputLines} of ${truncation.totalLines} lines ` +
          `(${formatSize(truncation.outputBytes)} of ${formatSize(truncation.totalBytes)}). ` +
          `Full output saved to: ${fullOutputPath}]`;
      }

      return {
        content: [{ type: "text", text }],
        details: {
          exitCode: result.code,
          count: results.length,
          fullOutputPath,
        },
      };
    },
  });
}
