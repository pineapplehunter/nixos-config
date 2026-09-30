import { execFile } from "node:child_process";
import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";

const STATUS_KEY = "usage-pueue";
const REFRESH_MS = 10_000;

interface PueueTask {
  group?: unknown;
  status?: unknown;
}

function statusName(status: unknown): string | undefined {
  if (typeof status === "string") return status;
  if (status && typeof status === "object" && !Array.isArray(status)) {
    return Object.keys(status)[0];
  }
  return undefined;
}

function formatStatus(output: string): string | undefined {
  const parsed = JSON.parse(output) as { tasks?: Record<string, PueueTask> };
  const counts = new Map<string, number>();
  for (const task of Object.values(parsed.tasks ?? {})) {
    if (statusName(task.status) !== "Running" || typeof task.group !== "string") continue;
    counts.set(task.group, (counts.get(task.group) ?? 0) + 1);
  }
  if (counts.size === 0) return undefined;
  if (counts.size === 1 && counts.has("default")) return `pueue: ${counts.get("default")}`;

  const groups = [...counts.entries()].sort(([left], [right]) => {
    if (left === "default") return -1;
    if (right === "default") return 1;
    return left.localeCompare(right);
  });
  return `pueue: ${groups.map(([group, count]) => `${count}(${group})`).join(" ")}`;
}

function queryStatus(): Promise<string | undefined> {
  return new Promise((resolve) => {
    execFile("pueue", ["status", "--json", "status=running"], { encoding: "utf8", timeout: 1_000 }, (error, stdout) => {
      if (error) {
        resolve(undefined);
        return;
      }
      try {
        resolve(formatStatus(stdout));
      } catch {
        resolve(undefined);
      }
    });
  });
}

function setStatus(ctx: ExtensionContext, value: string | undefined): void {
  try {
    ctx.ui.setStatus(STATUS_KEY, value);
  } catch {
    // Ignore stale contexts during reload and shutdown.
  }
}

export default function (pi: ExtensionAPI) {
  if (process.env.PI_SUBAGENT_ROLE === "child") return;

  pi.on("session_start", (_event, ctx) => {
    const refresh = async () => setStatus(ctx, await queryStatus());
    void refresh();
    const timer = setInterval(() => void refresh(), REFRESH_MS);
    timer.unref?.();
  });
}
