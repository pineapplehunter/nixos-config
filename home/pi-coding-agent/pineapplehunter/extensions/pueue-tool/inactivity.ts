import { statSync } from "node:fs";
import { join } from "node:path";
import type { Task } from "./logs.js";

export function parseInactivityTimeout(value: string): number | undefined {
  if (value === "off") return 0;
  const match = /^(\d+(?:\.\d+)?)(s|m|h)$/.exec(value);
  if (!match) return undefined;
  const ms = Number(match[1]) * ({ s: 1000, m: 60_000, h: 3_600_000 }[match[2]]!);
  return Number.isSafeInteger(ms) && ms > 0 ? ms : undefined;
}

// Observe file metadata, never read potentially huge task logs. Starting or
// reconfiguring the monitor gives existing tasks a fresh observation window.
export class InactivityMonitor {
  private observed = new Map<number, { attempt: string; output: string; activeAt: number; alertedAt: number }>();

  private directory: string;

  constructor(directory: string) { this.directory = directory; }

  reset(): void { this.observed.clear(); }

  check(tasks: Task[], timeout: number, now = Date.now()): { task: Task; idleMs: number }[] {
    const running = tasks.filter((task) => (typeof task.status === "object" && "Running" in task.status) || task.status === "Running");
    const ids = new Set(running.map((task) => task.id));
    for (const id of this.observed.keys()) if (!ids.has(id)) this.observed.delete(id);
    if (!timeout) { this.reset(); return []; }

    const overdue: { task: Task; idleMs: number }[] = [];
    for (const task of running) {
      let output = "missing";
      try {
        const stat = statSync(join(this.directory, "task_logs", `${task.id}.log`));
        output = `${stat.ino}:${stat.size}:${stat.mtimeMs}`;
      } catch (error) {
        if ((error as NodeJS.ErrnoException).code !== "ENOENT") throw error;
      }
      const attempt = JSON.stringify(task.status);
      let state = this.observed.get(task.id);
      if (!state || state.attempt !== attempt || state.output !== output) {
        state = { attempt, output, activeAt: now, alertedAt: now };
        this.observed.set(task.id, state);
      }
      if (now - Math.max(state.activeAt, state.alertedAt) >= timeout) {
        overdue.push({ task, idleMs: now - state.activeAt });
        state.alertedAt = now;
      }
    }
    return overdue;
  }
}
