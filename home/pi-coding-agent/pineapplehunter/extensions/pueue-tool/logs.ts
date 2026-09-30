import { spawn, type ChildProcess } from "node:child_process";
import type { ExtensionAPI, Theme } from "@earendil-works/pi-coding-agent";
import { matchesKey, Text, truncateToWidth, visibleWidth, type TUI } from "@earendil-works/pi-tui";

export interface Task {
  id: number;
  command: string;
  original_command?: string;
  label?: string | null;
  group: string;
  status: string | { Done?: { start?: string; end: string; result: unknown } };
}

export function taskStatus(task: Task): string {
  if (typeof task.status === "string") return task.status;
  if (task.status.Done) {
    const result = task.status.Done.result;
    return typeof result === "string" ? result : JSON.stringify(result);
  }
  return Object.keys(task.status)[0];
}

const MAX_LINES = 5_000;
const MAX_LINE_LENGTH = 16_384;

function taskName(task: Task): string {
  return (task.label?.replace(/^subagent:[^:]+:/, "") || task.original_command || task.command).replace(/\s+/g, " ");
}

function statusLabel(task: Task): string {
  const result = typeof task.status === "object" ? task.status.Done?.result : undefined;
  if (result && typeof result === "object") {
    const [name, detail] = Object.entries(result)[0];
    return name === "Failed" ? `Failed (${detail})` : name;
  }
  return taskStatus(task);
}

function statusColor(task: Task): Parameters<Theme["fg"]>[0] {
  const status = taskStatus(task);
  if (status === "Success") return "success";
  if (status === "Running") return "warning";
  if (typeof task.status === "object" && task.status.Done) return status === "Killed" ? "muted" : "error";
  return "muted";
}

function contentText(content: any): string {
  if (typeof content === "string") return content;
  return Array.isArray(content) ? content.map((part) => part.type === "text" ? part.text : `[${part.type}]`).join("\n") : "";
}

// Parse only observable RPC activity, not hidden reasoning or model context.
export class ActivityParser {
  private streamed = false;

  parse(line: string): string {
    let event: any;
    try { event = JSON.parse(line); } catch { return line + "\n"; }
    if (!event || typeof event !== "object") return line + "\n";
    switch (event.type) {
      case "agent_start": return "[Agent started]\n";
      case "message_start":
        if (event.message?.role === "assistant") { this.streamed = false; return "\n[Assistant]\n"; }
        return "";
      case "message_update":
        if (event.assistantMessageEvent?.type === "text_delta") {
          this.streamed = true;
          return event.assistantMessageEvent.delta;
        }
        return "";
      case "message_end":
        if (event.message?.role === "assistant") {
          const text = this.streamed ? "" : contentText(event.message.content);
          return text + (event.message.errorMessage ? `\n[Error] ${event.message.errorMessage}` : "") + "\n";
        }
        if (event.message?.role === "custom" && event.message.customType === "pueue-completion") {
          return `\n[Task completion]\n${event.message.details?.summary ?? contentText(event.message.content)}\n`;
        }
        return "";
      case "tool_execution_start": return `\n[Tool] ${event.toolName} ${JSON.stringify(event.args)}\n`;
      case "tool_execution_end": return `\n[${event.isError ? "Tool error" : "Result"}] ${event.toolName}\n${contentText(event.result?.content)}\n`;
      case "agent_end": return "\n[Agent run ended]\n";
      case "extension_error": return `[Error] ${event.error}\n`;
      case "response": return event.success === false ? `[Error] ${event.error}\n` : "";
      case "extension_ui_request": return event.method === "notify" ? `[Notice] ${event.message}\n` : "";
      case "entry_appended":
        if (event.entry?.customType === "pueue-subagent-exit") {
          return event.entry.data?.success ? "[Subagent finished]\n" : `[Subagent failed] ${event.entry.data?.error}\n`;
        }
        return "";
      default: return "";
    }
  }
}

export class LogViewer {
  private tasks: Task[];
  private selected = 0;
  private opened: number | undefined;
  private lines: string[] = [];
  private partial = "";
  private text = new Text("", 0, 0);
  private offset = 0;
  private follow = true;
  private raw = false;
  private source = "";
  private process: ChildProcess | undefined;
  private timer: ReturnType<typeof setInterval>;
  private disposed = false;
  private refreshing = false;
  private error = "";

  constructor(
    private tui: TUI,
    private theme: Theme,
    private done: () => void,
    private queryTasks: () => Promise<Task[]>,
    tasks: Task[],
    taskId?: number,
  ) {
    this.tasks = tasks.sort((a, b) => b.id - a.id);
    this.opened = taskId;
    this.timer = setInterval(() => void this.refresh(), 1_000);
    this.timer.unref?.();
    void this.refresh();
  }

  private async refresh(): Promise<void> {
    if (this.disposed || this.refreshing) return;
    this.refreshing = true;
    try {
      const tasks = await this.queryTasks();
      if (this.disposed) return;
      const selectedId = this.tasks[this.selected]?.id;
      this.tasks = tasks.sort((a, b) => b.id - a.id);
      this.selected = Math.max(0, this.tasks.findIndex((task) => task.id === selectedId));
      this.error = "";
      const task = this.tasks.find((task) => task.id === this.opened);
      if (task) {
        const activity = task.group === "subagent" && task.label?.startsWith("subagent:") && !this.raw;
        const running = taskStatus(task) === "Running";
        const source = `${task.id}:${JSON.stringify(task.status)}:${this.raw}`;
        if (source !== this.source) {
          this.stopSource();
          this.source = source;
          this.lines = [];
          this.partial = "";
          this.text.setText("");
          this.offset = 0;
          const parser = new ActivityParser();
          let pending = "";
          this.process = spawn("pueue", running ? ["follow", "--lines", String(MAX_LINES), String(task.id)] : ["log", "--full", String(task.id)]);
          const append = (text: string) => {
            if (this.disposed || this.source !== source) return;
            this.append(text);
            this.tui.requestRender();
          };
          this.process.stdout?.setEncoding("utf8");
          this.process.stdout?.on("data", (chunk: string) => {
            if (!activity) return append(chunk);
            pending += chunk;
            let newline: number;
            while ((newline = pending.indexOf("\n")) !== -1) {
              append(parser.parse(pending.slice(0, newline)));
              pending = pending.slice(newline + 1);
            }
          });
          this.process.stderr?.setEncoding("utf8");
          this.process.stderr?.on("data", append);
          this.process.on("error", (error) => append(`[Viewer error] ${error.message}\n`));
          this.process.on("close", () => {
            if (pending) append(parser.parse(pending));
          });
        }
      } else if (this.opened !== undefined) {
        this.stopSource();
        this.error = "Task no longer exists (it may have been cleaned). Esc returns to the list.";
      }
    } catch (error) {
      if (!this.disposed) this.error = `Cannot read Pueue tasks: ${String(error)}`;
    } finally {
      this.refreshing = false;
      if (!this.disposed) this.tui.requestRender();
    }
  }

  private append(text: string): void {
    const parts = (this.partial + text).split("\n");
    this.partial = parts.pop()!.slice(-MAX_LINE_LENGTH);
    this.lines.push(...parts.map((line) => line.slice(0, MAX_LINE_LENGTH)));
    if (this.lines.length > MAX_LINES) {
      const removed = this.lines.length - MAX_LINES;
      this.lines.splice(0, removed);
      this.offset = Math.max(0, this.offset - removed);
    }
    this.text.setText([...this.lines, this.partial].join("\n"));
  }

  private stopSource(): void {
    this.source = "";
    this.process?.kill(); // Only pueue log/follow, never the underlying task.
    this.process = undefined;
  }

  private height(): number {
    const chrome = this.tui.terminal.rows < 16 ? 5 : 8;
    return Math.max(1, Math.min(18, Math.floor(this.tui.terminal.rows * 0.9) - chrome));
  }

  handleInput(data: string): void {
    if (matchesKey(data, "ctrl+c")) return this.close();
    if (matchesKey(data, "escape")) {
      if (this.opened === undefined) return this.close();
      this.stopSource();
      this.opened = undefined;
      this.error = "";
    } else if (this.opened === undefined) {
      if (matchesKey(data, "up")) this.selected = Math.max(0, this.selected - 1);
      if (matchesKey(data, "down")) this.selected = Math.max(0, Math.min(this.tasks.length - 1, this.selected + 1));
      if (matchesKey(data, "enter") && this.tasks[this.selected]) {
        this.opened = this.tasks[this.selected].id;
        this.follow = true;
        this.raw = false;
        void this.refresh();
      }
    } else {
      if (matchesKey(data, "up") || matchesKey(data, "pageUp")) {
        this.follow = false;
        this.offset = Math.max(0, this.offset - (matchesKey(data, "pageUp") ? this.height() : 1));
      }
      if (matchesKey(data, "down") || matchesKey(data, "pageDown")) {
        this.follow = false;
        this.offset += matchesKey(data, "pageDown") ? this.height() : 1;
      }
      if (data === "f" || matchesKey(data, "end")) this.follow = !this.follow || matchesKey(data, "end");
      if (matchesKey(data, "home")) { this.follow = false; this.offset = 0; }
      if (data === "v") { this.raw = !this.raw; void this.refresh(); }
    }
    this.tui.requestRender();
  }

  render(width: number): string[] {
    const th = this.theme;
    const inner = Math.max(1, width - 4);
    const compact = this.tui.terminal.rows < 16;
    const pad = (text: string, size = inner) => truncateToWidth(text.replace(/[\r\n\t]/g, " "), size, "…", true);
    const row = (text = "") => th.fg("borderMuted", "│ ") + pad(text) + th.fg("borderMuted", " │");
    const rule = () => th.fg("borderMuted", `├${"─".repeat(Math.max(0, width - 2))}┤`);
    const task = this.tasks.find((task) => task.id === this.opened);
    const selected = this.tasks[this.selected];
    const title = pad(th.fg("accent", th.bold(task ? ` Task ${task.id}  ${taskName(task)} ` : " Pueue tasks ")), Math.max(1, width - 2)).trimEnd();
    const top = th.fg("borderAccent", "╭") + title + th.fg("borderAccent", "─".repeat(Math.max(0, width - 2 - visibleWidth(title))) + "╮");
    const output = [top];
    let body: string[];
    let information: string;
    let help: string;
    let height = this.height();
    if (this.opened === undefined) {
      height = Math.min(height, Math.max(3, this.tasks.length));
      if (!compact) {
        const running = this.tasks.filter((task) => taskStatus(task) === "Running").length;
        const failed = this.tasks.filter((task) => statusColor(task) === "error").length;
        output.push(row(th.fg("muted", `${this.tasks.length} tasks   ${running} running   ${failed} failed`)), rule());
      }
      const narrow = inner < 40;
      const idWidth = Math.min(6, Math.max(3, String(Math.max(0, ...this.tasks.map((task) => task.id))).length));
      const groupWidth = inner >= 70 ? 12 : 0;
      const nameWidth = Math.max(1, inner - 2 - idWidth - (narrow ? 3 : 16) - (groupWidth ? groupWidth + 2 : 0));
      const columns = (cursor: string, id: string, status: string, name: string, group: string) =>
        cursor + pad(id, idWidth) + " " + pad(status, narrow ? 1 : 12) + " " + pad(name, nameWidth) + (groupWidth ? "  " + pad(group, groupWidth) : "");
      output.push(row(th.fg("dim", columns("  ", "ID", narrow ? "" : "Status", "Task", "Group"))));
      const start = Math.max(0, this.selected - height + 1);
      body = this.tasks.slice(start, start + height).map((task, index) => {
        const focused = start + index === this.selected;
        const label = statusLabel(task);
        const glyph = taskStatus(task) === "Running" ? "●" : taskStatus(task) === "Success" ? "✓" : statusColor(task) === "error" ? "✕" : "○";
        const text = columns(
          focused ? th.fg("accent", "› ") : "  ",
          th.fg("muted", String(task.id)),
          th.fg(statusColor(task), narrow ? glyph : label),
          th.fg(focused ? "accent" : "text", taskName(task)),
          th.fg("dim", task.group === "default" ? "—" : task.group),
        );
        return focused ? th.bg("selectedBg", pad(text)) : text;
      });
      if (!body.length) body = [th.fg("muted", "No retained tasks. Queue a command to see its logs.")];
      information = selected
        ? th.fg("dim", "Command  ") + th.fg("toolOutput", (selected.original_command ?? selected.command).replace(/\s+/g, " "))
        : th.fg("dim", "Only this session's Pueue queue is shown.");
      help = inner < 30 ? "↑↓  Enter  Esc" : inner < 40 ? "↑↓ select  Enter logs  Esc close" : "↑↓ Select    Enter Open logs    Esc Close";
    } else {
      const status = task ? th.fg(statusColor(task), statusLabel(task)) : th.fg("error", "Task removed");
      const mode = task?.group === "subagent" && !this.raw ? "Activity" : "Raw output";
      if (!compact) output.push(row(`${status}${task?.group !== "default" && task ? th.fg("muted", `   ${task.group}`) : ""}${th.fg("dim", `   ${mode}`)}`), rule());
      output.push(row(th.fg("dim", "$ ") + (task?.original_command ?? task?.command ?? "")));
      const rows = this.text.render(inner);
      const bottom = Math.max(0, rows.length - height);
      this.offset = this.follow ? bottom : Math.min(this.offset, bottom);
      body = rows.slice(this.offset, this.offset + height).map((line) => th.fg("toolOutput", line));
      if (!this.lines.length && !this.partial) body = [th.fg("muted", "Waiting for output…")];
      information = th.fg("dim", `Lines ${this.offset + 1}–${Math.min(rows.length, this.offset + height)} / ${rows.length}   `)
        + th.fg(this.follow ? "success" : "muted", `follow ${this.follow ? "ON" : "OFF"}`) + th.fg("dim", `   raw ${this.raw ? "ON" : "OFF"}`);
      help = inner < 30 ? "↑↓ f v Esc back" : inner < 60 ? "↑↓ Scroll  f Follow  v Raw  Esc Back" : "↑↓/PgUp/PgDn Scroll    f Follow    v Raw    Esc Tasks    Ctrl+C Close";
    }
    if (this.error) body = [th.fg("error", this.error), ...body].slice(0, height);
    while (body.length < height) body.push("");
    output.push(...body.map((line) => row(line)));
    if (!compact) output.push(rule(), row(information));
    output.push(row(th.fg("dim", help)), th.fg("borderMuted", `╰${"─".repeat(Math.max(0, width - 2))}╯`));
    return output;
  }

  invalidate(): void { this.text.invalidate(); }
  close(): void { if (this.disposed) return; this.dispose(); this.done(); }
  dispose(): void {
    if (this.disposed) return;
    this.disposed = true;
    clearInterval(this.timer);
    this.stopSource();
  }
}

export function registerLogViewer(pi: ExtensionAPI, queryTasks: () => Promise<Task[]>): void {
  let active: LogViewer | undefined;
  pi.registerCommand("pueue-logs", {
    description: "Browse Pueue tasks and live/finished logs, optionally by task ID",
    handler: async (args, ctx) => {
      if (ctx.mode !== "tui") { ctx.ui.notify("Pueue log browsing requires interactive Pi.", "warning"); return; }
      if (args.trim() && !/^\d+$/.test(args.trim())) { ctx.ui.notify("Usage: /pueue-logs [task-id]", "warning"); return; }
      const taskId = args.trim() ? Number(args.trim()) : undefined;
      try {
        const tasks = await queryTasks();
        if (taskId !== undefined && !tasks.some((task) => task.id === taskId)) {
          ctx.ui.notify(`Pueue task ${taskId} does not exist.`, "warning"); return;
        }
        let terminal: TUI | undefined;
        await ctx.ui.custom<void>((tui, theme, _keys, done) => {
          terminal = tui;
          active = new LogViewer(tui, theme, done, queryTasks, tasks, taskId);
          return active;
        }, { overlay: true, overlayOptions: () => ({
          width: Math.min(110, Math.max(1, (terminal?.terminal.columns ?? 80) - 4)),
          maxHeight: "90%", anchor: "center", margin: 1,
        }) });
      } catch (error) { ctx.ui.notify(`Cannot open Pueue logs: ${String(error)}`, "error"); }
      finally { active?.dispose(); active = undefined; }
    },
  });
  pi.on("session_shutdown", () => active?.close());
}
