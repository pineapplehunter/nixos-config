import { spawn } from "node:child_process"

const DEFAULT_TIMEOUT = 10 * 1000

interface NixSearchResult {
  type: string
  package_pname: string
  package_attr_name: string
  package_attr_set: string
  package_pversion: string
  package_description: string
  package_programs: string[]
  package_homepage: string[]
  package_license: { fullName: string; url: string }[]
  package_platforms: string[]
}

function formatResults(results: NixSearchResult[]): string {
  if (results.length === 0) return "(no results)"
  return results
    .map((pkg) => {
      const name = pkg.package_attr_name || pkg.package_pname
      const version = pkg.package_pversion
      return version ? `${name} @ ${version}` : name
    })
    .join("\n")
}

interface ToolContext {
  directory: string
}

const nixSearchTool = {
  description: "Search for packages in nixpkgs by name or attribute path using the search.nixos.org index",
  args: {
    query: {
      type: "string",
      description: "Package name or command to search for",
    },
  },
  async execute(args: { query: string }, ctx: ToolContext) {
    return new Promise((resolve) => {
      const proc = spawn("nix-search", ["--json", args.query], {
        cwd: ctx.directory,
        stdio: ["ignore", "pipe", "pipe"],
      })

      let stdout = ""
      let stderr = ""

      proc.stdout?.on("data", (data) => {
        stdout += data.toString()
      })

      proc.stderr?.on("data", (data) => {
        stderr += data.toString()
      })

      const timer = setTimeout(() => {
        proc.kill("SIGTERM")
        setTimeout(() => proc.kill("SIGKILL"), 3000)
      }, DEFAULT_TIMEOUT)

      proc.on("error", (err) => {
        clearTimeout(timer)
        resolve({ output: `nix-search failed: ${err.message}`, metadata: { exitCode: 1 } })
      })

      proc.on("close", (code) => {
        clearTimeout(timer)
        if (stderr) {
          resolve({ output: stderr, metadata: { exitCode: code } })
          return
        }
        const results: NixSearchResult[] = stdout
          .trim()
          .split("\n")
          .filter(Boolean)
          .map((line) => JSON.parse(line))
        resolve({
          output: formatResults(results),
          metadata: { exitCode: code, count: results.length },
        })
      })
    })
  },
}

export default nixSearchTool