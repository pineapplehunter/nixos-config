import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { spawn, type ChildProcessByStdio } from "node:child_process";
import type { Readable } from "node:stream";
import { Type } from "typebox";

type PueueChild = ChildProcessByStdio<null, Readable, Readable>;

const MAX_TAIL_BYTES = 4096;
const MAX_TAIL_LINES = 20;
const KILL_GRACE_MS = 250;

interface PueueWaitResult {
  taskId: number;
  outcome: "success" | "stale";
  text: string;
  retainedBytes: number;
}

class TailBuffer {
  private value = Buffer.alloc(0);

  append(chunk: Buffer | string): void {
    let incoming = typeof chunk === "string" ? Buffer.from(chunk) : chunk;
    if (incoming.length > MAX_TAIL_BYTES) {
      incoming = incoming.subarray(incoming.length - MAX_TAIL_BYTES);
    }

    this.value = Buffer.concat([this.value, incoming]);
    if (this.value.length > MAX_TAIL_BYTES) {
      this.value = this.value.subarray(this.value.length - MAX_TAIL_BYTES);
    }

    while (this.lineCount() > MAX_TAIL_LINES) {
      const newline = this.value.indexOf(0x0a);
      if (newline === -1) break;
      this.value = this.value.subarray(newline + 1);
    }
  }

  private lineCount(): number {
    if (this.value.length === 0) return 0;
    let lines = this.value[this.value.length - 1] === 0x0a ? 0 : 1;
    for (const byte of this.value) {
      if (byte === 0x0a) lines++;
    }
    return lines;
  }

  get byteLength(): number {
    return this.value.length;
  }

  toString(): string {
    return this.value.toString("utf8");
  }
}

function abortError(): Error {
  const error = new Error("Waiting for the Pueue task was cancelled.");
  error.name = "AbortError";
  return error;
}

function waitForClose(child: PueueChild, milliseconds: number): Promise<void> {
  if (child.exitCode !== null || child.signalCode !== null) return Promise.resolve();
  return new Promise((resolve) => {
    const timer = setTimeout(resolve, milliseconds);
    child.once("close", () => {
      clearTimeout(timer);
      resolve();
    });
  });
}

async function terminateChild(child: PueueChild): Promise<void> {
  if (child.exitCode !== null || child.signalCode !== null) return;
  child.kill("SIGTERM");
  await waitForClose(child, KILL_GRACE_MS);
  if (child.exitCode === null && child.signalCode === null) {
    child.kill("SIGKILL");
    await waitForClose(child, KILL_GRACE_MS);
  }
}

interface CommandResult {
  code: number | null;
  stdout: Buffer;
  stderr: Buffer;
}

async function runCommand(
  executable: string,
  args: string[],
  signal: AbortSignal | undefined,
): Promise<CommandResult> {
  if (signal?.aborted) throw abortError();

  let child: PueueChild;
  try {
    child = spawn(executable, args, {
      stdio: ["ignore", "pipe", "pipe"],
    });
  } catch (error) {
    throw new Error(`Cannot start Pueue: ${error instanceof Error ? error.message : String(error)}`);
  }

  const stdout: Buffer[] = [];
  const stderr: Buffer[] = [];
  child.stdout.on("data", (chunk: Buffer) => stdout.push(chunk));
  child.stderr.on("data", (chunk: Buffer) => stderr.push(chunk));

  let cancelled = false;
  const onAbort = () => {
    if (cancelled) return;
    cancelled = true;
    void terminateChild(child);
  };
  signal?.addEventListener("abort", onAbort, { once: true });
  if (signal?.aborted) onAbort();

  try {
    const result = await new Promise<CommandResult>((resolve, reject) => {
      child.once("error", (error) => reject(new Error(`Cannot start Pueue: ${error.message}`)));
      child.once("close", (code) => {
        resolve({ code, stdout: Buffer.concat(stdout), stderr: Buffer.concat(stderr) });
      });
    });
    if (cancelled) throw abortError();
    return result;
  } finally {
    signal?.removeEventListener("abort", onAbort);
    if (cancelled) await terminateChild(child);
  }
}

interface StatusTask {
  id: number;
  running: boolean;
}

function statusName(status: unknown): string | undefined {
  if (typeof status === "string") return status;
  if (status !== null && typeof status === "object" && !Array.isArray(status)) {
    const keys = Object.keys(status);
    if (keys.length === 1) return keys[0];
  }
  return undefined;
}

function parseStatus(output: Buffer | string): StatusTask[] {
  let parsed: unknown;
  try {
    parsed = JSON.parse(typeof output === "string" ? output : output.toString("utf8"));
  } catch {
    throw new Error("Pueue returned malformed status JSON.");
  }

  if (parsed === null || typeof parsed !== "object" || Array.isArray(parsed)) {
    throw new Error("Pueue returned unusable status output: expected an object.");
  }
  const tasks = (parsed as { tasks?: unknown }).tasks;
  if (tasks === null || typeof tasks !== "object" || Array.isArray(tasks)) {
    throw new Error("Pueue returned unusable status output: missing task map.");
  }

  return Object.entries(tasks).map(([key, value]) => {
    if (value === null || typeof value !== "object" || Array.isArray(value)) {
      throw new Error(`Pueue returned unusable status output for task ${key}.`);
    }
    const task = value as { id?: unknown; status?: unknown };
    const keyId = Number(key);
    const id = typeof task.id === "number" ? task.id : keyId;
    const name = statusName(task.status);
    if (!Number.isSafeInteger(id) || id < 0 || name === undefined) {
      throw new Error(`Pueue returned unusable status output for task ${key}.`);
    }
    return { id, running: name === "Running" };
  });
}

function selectTask(tasks: StatusTask[], requestedId: number | undefined): number {
  if (requestedId !== undefined) {
    if (!Number.isSafeInteger(requestedId) || requestedId < 0) {
      throw new Error("task_id must be a non-negative integer.");
    }
    const task = tasks.find(({ id }) => id === requestedId);
    if (!task) throw new Error(`Pueue task ${requestedId} does not exist.`);
    if (!task.running) throw new Error(`Pueue task ${requestedId} is not currently running.`);
    return requestedId;
  }

  const running = tasks.filter((task) => task.running).map((task) => task.id).sort((a, b) => a - b);
  if (running.length === 0) throw new Error("Cannot wait for a Pueue task: no tasks are currently running.");
  if (running.length > 1) {
    throw new Error(
      `Cannot determine which Pueue task to wait for: multiple tasks are running: ${running.join(", ")}. Pass task_id explicitly.`,
    );
  }
  return running[0];
}

function withSummary(tail: string, summary: string): string {
  return tail.length === 0 ? summary : `${tail}\n\n${summary}`;
}

interface PueueWaitProgress {
  taskId: number;
  elapsedSeconds: number;
  timeoutRemainingSeconds: number;
}

async function waitForPueueTask(
  timeout: number,
  taskId: number | undefined,
  signal?: AbortSignal,
  onProgress?: (progress: PueueWaitProgress) => void,
): Promise<PueueWaitResult> {
  if (!Number.isSafeInteger(timeout) || timeout <= 0) {
    throw new Error("timeout must be an integer greater than zero.");
  }
  if (taskId !== undefined && (!Number.isSafeInteger(taskId) || taskId < 0)) {
    throw new Error("task_id must be a non-negative integer.");
  }

  const executable = "pueue";
  const status = await runCommand(executable, ["status", "--json"], signal);
  if (status.code !== 0) {
    const reason = status.stderr.toString("utf8").trim();
    throw new Error(reason ? `Cannot query Pueue status: ${reason}` : `Cannot query Pueue status (exit status ${status.code}).`);
  }
  const selectedId = selectTask(parseStatus(status.stdout), taskId);
  if (signal?.aborted) throw abortError();

  let child: PueueChild;
  try {
    child = spawn(executable, ["follow", "--lines", "20", String(selectedId)], {
      stdio: ["ignore", "pipe", "pipe"],
    });
  } catch (error) {
    throw new Error(`Cannot start pueue follow: ${error instanceof Error ? error.message : String(error)}`);
  }

  const tail = new TailBuffer();
  let timer: NodeJS.Timeout | undefined;
  let progressTimer: NodeJS.Timeout | undefined;
  let startedAt = 0;
  let timeoutAt = 0;
  let stale = false;
  let cancelled = false;
  let spawned = false;

  const reportProgress = () => {
    if (!spawned || stale || cancelled) return;
    const now = Date.now();
    onProgress?.({
      taskId: selectedId,
      elapsedSeconds: Math.floor((now - startedAt) / 1000),
      timeoutRemainingSeconds: Math.max(0, Math.ceil((timeoutAt - now) / 1000)),
    });
  };
  const resetTimer = () => {
    if (!spawned || stale || cancelled) return;
    if (timer !== undefined) clearTimeout(timer);
    timeoutAt = Date.now() + timeout * 1000;
    timer = setTimeout(() => {
      stale = true;
      onProgress?.({
        taskId: selectedId,
        elapsedSeconds: Math.floor((Date.now() - startedAt) / 1000),
        timeoutRemainingSeconds: 0,
      });
      void terminateChild(child);
    }, timeout * 1000);
    reportProgress();
  };
  const onData = (chunk: Buffer) => {
    tail.append(chunk);
    resetTimer();
  };
  child.stdout.on("data", onData);
  child.stderr.on("data", onData);
  child.once("spawn", () => {
    spawned = true;
    startedAt = Date.now();
    resetTimer();
    progressTimer = setInterval(reportProgress, 1000);
  });

  const onAbort = () => {
    if (cancelled) return;
    cancelled = true;
    if (timer !== undefined) clearTimeout(timer);
    if (progressTimer !== undefined) clearInterval(progressTimer);
    void terminateChild(child);
  };
  signal?.addEventListener("abort", onAbort, { once: true });
  if (signal?.aborted) onAbort();

  try {
    const code = await new Promise<number | null>((resolve, reject) => {
      child.once("error", (error) => reject(new Error(`Cannot start pueue follow: ${error.message}`)));
      child.once("close", resolve);
    });
    if (timer !== undefined) clearTimeout(timer);
    if (cancelled) throw abortError();

    if (stale) {
      const summary = `Timed out after ${timeout} seconds because Pueue task ${selectedId} produced no output during that period. The task is still running; only pueue follow was stopped.`;
      return {
        taskId: selectedId,
        outcome: "stale",
        text: withSummary(tail.toString(), summary),
        retainedBytes: tail.byteLength,
      };
    }
    if (code === 0) {
      return {
        taskId: selectedId,
        outcome: "success",
        text: withSummary(tail.toString(), `Pueue task ${selectedId} exited successfully.`),
        retainedBytes: tail.byteLength,
      };
    }

    throw new Error(withSummary(tail.toString(), `pueue follow for task ${selectedId} exited with status ${code}.`));
  } finally {
    if (timer !== undefined) clearTimeout(timer);
    if (progressTimer !== undefined) clearInterval(progressTimer);
    signal?.removeEventListener("abort", onAbort);
    await terminateChild(child);
  }
}

function formatElapsed(seconds: number): string {
  const hours = Math.floor(seconds / 3600);
  const minutes = Math.floor((seconds % 3600) / 60);
  const remainingSeconds = seconds % 60;
  return [hours, minutes, remainingSeconds].map((value) => String(value).padStart(2, "0")).join(":");
}

export default function (pi: ExtensionAPI) {
  pi.registerTool({
    name: "pueue-wait",
    label: "Pueue Wait",
    description:
      "Wait for an already-running Pueue task. The inactivity timeout resets whenever pueue follow emits output; a timeout stops only the local follow client and never modifies the task.",
    promptSnippet: "Wait for a running Pueue task until it completes or its output becomes stale",
    promptGuidelines: [
      "Use pueue-wait instead of pueue wait so silent or stuck tasks return control after the requested output-inactivity timeout.",
      "Omit task_id only when exactly one Pueue task is running; specify it when multiple tasks run.",
    ],
    parameters: Type.Object({
      timeout: Type.Integer({
        description: "Maximum seconds with no output from pueue follow; every output byte resets it",
        exclusiveMinimum: 0,
      }),
      task_id: Type.Optional(
        Type.Integer({
          description: "Optional ID of a task that is currently running",
          minimum: 0,
        }),
      ),
    }),
    async execute(_toolCallId, params, signal, onUpdate) {
      const result = await waitForPueueTask(params.timeout, params.task_id, signal, (progress) => {
        onUpdate?.({
          content: [
            {
              type: "text",
              text: `Waiting for Pueue task ${progress.taskId} — elapsed ${formatElapsed(progress.elapsedSeconds)}; inactivity timeout ${progress.timeoutRemainingSeconds}s`,
            },
          ],
          details: progress,
        });
      });
      return {
        content: [{ type: "text", text: result.text }],
        details: {
          taskId: result.taskId,
          outcome: result.outcome,
          retainedBytes: result.retainedBytes,
        },
      };
    },
  });
}
