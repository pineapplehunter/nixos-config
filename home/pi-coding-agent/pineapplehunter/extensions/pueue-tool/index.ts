import { execFile } from "node:child_process";
import { mkdirSync, readdirSync, unlinkSync, watch, type FSWatcher } from "node:fs";
import { join } from "node:path";
import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";
import { registerLogViewer, type Task } from "./logs.js";

const MESSAGE_TYPE = "pueue-completion";
const PROCESSED_TYPE = "pueue-completions-processed";
const RECONCILE_MS = 10_000;
const STATUS_KEY = "usage-pueue";

function taskKey(task: Task): string | undefined {
  if (typeof task.status !== "object" || !task.status.Done) return undefined;
  return JSON.stringify([task.id, task.status.Done.start, task.status.Done.end]);
}

function runningStatus(tasks: Task[]): string | undefined {
  const counts = new Map<string, number>();
  for (const task of tasks) {
    const status = typeof task.status === "string" ? task.status : Object.keys(task.status)[0];
    if (status === "Running") counts.set(task.group, (counts.get(task.group) ?? 0) + 1);
  }
  if (!counts.size) return undefined;
  if (counts.size === 1 && counts.has("default")) return `pueue: ${counts.get("default")}`;
  const groups = [...counts.entries()].sort(([left], [right]) => {
    if (left === "default") return -1;
    if (right === "default") return 1;
    return left.localeCompare(right);
  });
  return `pueue: ${groups.map(([group, count]) => `${count}(${group})`).join(" ")}`;
}

function queryTasks(): Promise<Task[]> {
  return new Promise((resolve, reject) => {
    execFile("pueue", ["status", "--json"], { encoding: "utf8", timeout: 5_000, maxBuffer: 8 * 1024 * 1024 }, (error, stdout) => {
      if (error) return reject(error);
      try {
        const status = JSON.parse(stdout) as { tasks: Record<string, Task> };
        resolve(Object.values(status.tasks));
      } catch (error) {
        reject(error);
      }
    });
  });
}

function inlineCode(text: string): string {
  const ticks = "`".repeat(Math.max(0, ...(text.match(/`+/g) ?? []).map((run) => run.length)) + 1);
  return `${ticks} ${text} ${ticks}`;
}

function completionMessage(tasks: Task[]) {
  const summaries: string[] = [];
  const blocks = tasks.map((task) => {
    const done = typeof task.status === "object" ? task.status.Done : undefined;
    const label = task.label ? ` ${JSON.stringify(task.label)}` : "";
    const group = task.group !== "default" ? ` (${task.group})` : "";
    const summary = `Task ${task.id}${label}${group}: ${JSON.stringify(done?.result)}.  \n${inlineCode(task.original_command ?? task.command)}`;
    summaries.push(summary);
    return `${summary}  \nInspect output with ${inlineCode(`pueue log ${task.id}`)}.`;
  });
  return {
    customType: MESSAGE_TYPE,
    content: `${blocks.join("\n\n")} Process these results and continue the original task.`,
    display: true,
    details: { keys: tasks.map(taskKey), summary: summaries.join("\n\n") },
  };
}

export default function (pi: ExtensionAPI) {
  const directory = process.env.PI_PUEUE_NOTIFY_DIR;
  if (!directory) return; // Never subscribe to the host daemon accidentally.

  registerLogViewer(pi, queryTasks);

  const child = process.env.PI_SUBAGENT_ROLE === "child";
  const inbox = join(directory, "completions");
  let context: ExtensionContext | undefined;
  let watcher: FSWatcher | undefined;
  let timer: ReturnType<typeof setInterval> | undefined;
  let debounce: ReturnType<typeof setTimeout> | undefined;
  let generation = 0;
  let serial: Promise<unknown> = Promise.resolve();
  let processed = new Set<string>();
  let queued = new Set<string>();
  let included = new Set<string>();
  let paused = false;
  let readyToExit = false;
  let failure: string | undefined;

  // Do not hold this queue while awaiting a model run: an idle sendMessage
  // starts one, whose pre-settlement handler also needs to query Pueue.
  function exclusive<T>(action: () => Promise<T>): Promise<T> {
    const next = serial.then(action);
    serial = next.catch(() => undefined);
    return next;
  }

  function cleanup(): void {
    generation++;
    watcher?.close();
    watcher = undefined;
    if (timer) clearInterval(timer);
    if (debounce) clearTimeout(debounce);
    timer = undefined;
    debounce = undefined;
    context?.ui.setStatus(STATUS_KEY, undefined);
    context?.ui.setStatus("pueue-notify", undefined);
    context = undefined;
  }

  async function collect(): Promise<{ tasks: Task[]; fresh: Task[] }> {
    // Snapshot filenames before querying. A hook arriving during the query
    // remains in the inbox for the next scan.
    const events = readdirSync(inbox).filter((name) => name.endsWith(".json"));
    const tasks = await queryTasks();
    if (context?.mode === "tui") context.ui.setStatus(STATUS_KEY, runningStatus(tasks));
    const fresh = tasks.filter((task) => {
      const key = taskKey(task);
      return key && !processed.has(key) && !queued.has(key);
    });
    for (const name of events) unlinkSync(join(inbox, name));
    return { tasks, fresh };
  }

  function enqueue(tasks: Task[]): void {
    readyToExit = false;
    for (const task of tasks) queued.add(taskKey(task)!);
  }

  function exitChild(ctx: ExtensionContext): void {
    pi.appendEntry("pueue-subagent-exit", { success: !failure, error: failure });
    cleanup();
    ctx.shutdown();
  }

  function warn(ctx: ExtensionContext, error: unknown): void {
    ctx.ui.setStatus("pueue-notify", "pueue: notification check failed");
    if (child) {
      failure = `Cannot check Pueue completions: ${String(error)}`;
      if (ctx.isIdle()) exitChild(ctx);
    }
  }

  function schedule(): void {
    if (!context || debounce) return;
    const current = generation;
    debounce = setTimeout(() => {
      debounce = undefined;
      void exclusive(async () => {
        const ctx = context;
        if (!ctx || current !== generation) return;
        try {
          const { fresh } = await collect();
          if (current !== generation || paused) return;
          ctx.ui.setStatus("pueue-notify", undefined);
          if (fresh.length) {
            enqueue(fresh);
            pi.sendMessage(completionMessage(fresh), { triggerTurn: true, deliverAs: "followUp" });
          }
        } catch (error) {
          if (current === generation) warn(ctx, error);
        }
      });
    }, 100);
    debounce.unref?.();
  }

  pi.on("session_start", (_event, ctx) => {
    cleanup();
    // Print/JSON are single-shot. They can reconcile at the run boundary, but
    // cannot receive asynchronous notifications after the invocation exits.
    if (ctx.mode !== "tui" && ctx.mode !== "rpc") return;
    context = ctx;
    processed = new Set<string>();
    queued = new Set<string>();
    included = new Set<string>();
    paused = false;
    failure = undefined;
    readyToExit = false;
    for (const entry of ctx.sessionManager.getBranch()) {
      if (entry.type === "custom" && entry.customType === PROCESSED_TYPE) {
        for (const key of (entry.data as { keys: string[] }).keys) processed.add(key);
      }
    }
    mkdirSync(inbox, { recursive: true, mode: 0o700 });
    watcher = watch(inbox, schedule);
    watcher.on("error", (error) => warn(ctx, error));
    timer = setInterval(schedule, RECONCILE_MS);
    timer.unref?.();
    schedule();
  });

  pi.on("before_agent_start", () => {
    // A new explicit user prompt may resume an aborted interactive agent.
    paused = false;
    readyToExit = false;
    failure = undefined;
  });

  pi.on("context", (event) => {
    for (const message of event.messages) {
      if (message.role === "custom" && message.customType === MESSAGE_TYPE) {
        for (const key of (message.details as { keys: string[] }).keys) {
          if (!processed.has(key)) included.add(key);
        }
      }
    }
  });

  pi.on("agent_before_settle", async (event, ctx) => {
    if (!context) return;
    return exclusive(async () => {
      readyToExit = false;
      if (event.outcome !== "completed") {
        paused = true;
        failure = `Agent run ${event.outcome}; background tasks were not all processed.`;
        return;
      }
      if (included.size) {
        pi.appendEntry(PROCESSED_TYPE, { keys: [...included] });
        for (const key of included) {
          processed.add(key);
          queued.delete(key);
        }
        included.clear();
      }
      if (paused) return;
      try {
        const { tasks, fresh } = await collect();
        ctx.ui.setStatus("pueue-notify", undefined);
        failure = undefined;
        if (fresh.length) {
          enqueue(fresh);
          return { entries: [{ type: "custom_message" as const, ...completionMessage(fresh) }], continue: true };
        }
        readyToExit = tasks.every((task) => {
          const key = taskKey(task);
          return key !== undefined && processed.has(key);
        }) && queued.size === 0;
      } catch (error) {
        warn(ctx, error);
      }
    });
  });

  pi.on("agent_settled", (_event, ctx) => {
    if (child && context && (readyToExit || failure)) {
      // The persistent runner waits for process exit, not intermediate settles.
      exitChild(ctx);
    }
  });

  pi.registerCommand("pueue-notifications", {
    description: "Resume automatic Pueue completion turns, or pause them with 'off'",
    handler: async (args, ctx) => {
      paused = args.trim() === "off";
      ctx.ui.notify(`Pueue completion notifications ${paused ? "paused" : "enabled"}.`, "info");
      if (!paused) schedule();
    },
  });

  pi.on("session_shutdown", cleanup);
}
