import assert from "node:assert/strict";
import { mkdtempSync, mkdirSync, readFileSync, writeFileSync, rmSync } from "node:fs";
import childProcess from "node:child_process";
import { stripTypeScriptTypes, syncBuiltinESMExports } from "node:module";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { InactivityMonitor, parseInactivityTimeout } from "../pineapplehunter/extensions/pueue-tool/inactivity.ts";

const running = (start = "first") => ({ id: 1, command: "build", group: "default", status: { Running: { start } } });

test("timeout command accepts units and off, rejecting invalid durations", () => {
  assert.equal(parseInactivityTimeout("30m"), 1_800_000);
  assert.equal(parseInactivityTimeout("2h"), 7_200_000);
  assert.equal(parseInactivityTimeout("0.5s"), 500);
  assert.equal(parseInactivityTimeout("off"), 0);
  for (const invalid of ["0m", "-1s", "NaN", "30", "1d", "999999999999999999h"]) {
    assert.equal(parseInactivityTimeout(invalid), undefined);
  }
});

test("default 30m wakes the agent at settlement; commands configure and restore the timeout", async (t) => {
  const directory = mkdtempSync(join(tmpdir(), "pueue-extension-"));
  const previous = process.env.PI_PUEUE_NOTIFY_DIR;
  process.env.PI_PUEUE_NOTIFY_DIR = directory;
  const handlers = new Map();
  const commands = new Map();
  const entries = [];
  const notices = [];
  const pi = {
    on: (name, handler) => handlers.set(name, handler),
    registerCommand: (name, command) => commands.set(name, command),
    appendEntry: (customType, data) => entries.push({ type: "custom", customType, data }),
  };
  const ctx = {
    mode: "rpc", ui: { setStatus() {}, notify: (...args) => notices.push(args) },
    sessionManager: { getBranch: () => entries },
  };
  let now = 0;
  t.mock.method(Date, "now", () => now);
  t.mock.method(childProcess, "execFile", (_command, _args, _options, callback) => {
    callback(null, JSON.stringify({ tasks: { 1: running() } }));
  });
  syncBuiltinESMExports();
  try {
    // Stub only the unrelated TUI viewer; execute the actual extension handlers.
    const url = new URL("../pineapplehunter/extensions/pueue-tool/index.ts", import.meta.url);
    const source = readFileSync(url, "utf8")
      .replace(/import \{ registerLogViewer, type Task \} from "\.\/logs.js";/, "const registerLogViewer = () => {};")
      .replace('"./inactivity.js"', JSON.stringify(new URL("./inactivity.ts", url).href));
    const { default: extension } = await import(`data:text/javascript;base64,${Buffer.from(stripTypeScriptTypes(source)).toString("base64")}`);
    extension(pi);
    handlers.get("session_start")({}, ctx);
    const settle = () => handlers.get("agent_before_settle")({ outcome: "completed" }, ctx);
    await settle();
    now = 30 * 60_000 - 1;
    assert.equal((await settle())?.continue, undefined);
    now++;
    const reminder = await settle();
    assert.equal(reminder.continue, true);
    assert.equal(reminder.entries[0].customType, "pueue-inactivity");
    assert.match(reminder.entries[0].content, /Inspect their logs and process state/);
    assert.equal((await settle())?.continue, undefined);
    const command = commands.get("pueue-inactivity").handler;
    await command("off", ctx);
    now += 60 * 60_000;
    assert.equal((await settle())?.continue, undefined);
    await command("invalid", ctx);
    assert.equal(notices.at(-1)[1], "warning");
    await command("10m", ctx);
    await settle();
    handlers.get("session_shutdown")();
    handlers.get("session_start")({}, ctx);
    await command("", ctx);
    assert.match(notices.at(-1)[0], /10 minutes/);
    await settle();
    now += 10 * 60_000;
    assert.equal((await settle()).continue, true);
  } finally {
    handlers.get("session_shutdown")?.();
    if (previous === undefined) delete process.env.PI_PUEUE_NOTIFY_DIR;
    else process.env.PI_PUEUE_NOTIFY_DIR = previous;
    t.mock.restoreAll();
    syncBuiltinESMExports();
    rmSync(directory, { recursive: true, force: true });
  }
});

test("quiet running tasks remind periodically; output, restarts, and removal reset the window", () => {
  const dir = mkdtempSync(join(tmpdir(), "pueue-inactivity-"));
  try {
    mkdirSync(join(dir, "task_logs"));
    const monitor = new InactivityMonitor(dir);
    const task = running();
    const check = (now, tasks = [task], timeout = 1000) => monitor.check(tasks, timeout, now);
    assert.deepEqual(check(0), []); // Missing log also permits a silent task.
    assert.deepEqual(check(999), []);
    assert.deepEqual(check(1000), [{ task, idleMs: 1000 }]);
    assert.deepEqual(check(1500), []);
    assert.deepEqual(check(2000), [{ task, idleMs: 2000 }]);
    writeFileSync(join(dir, "task_logs/1.log"), "progress");
    assert.deepEqual(check(2500), []);
    assert.deepEqual(check(3499), []);
    assert.deepEqual(check(3500), [{ task, idleMs: 1000 }]);
    writeFileSync(join(dir, "task_logs/1.log"), "more progress");
    assert.deepEqual(check(4000), []);
    assert.deepEqual(check(4500, [running("second")]), []);
    assert.deepEqual(check(5000, [{ ...task, status: "Paused" }]), []);
    assert.deepEqual(check(6000), []);
    assert.equal(check(7000).length, 1);
    assert.deepEqual(check(8000, [], 1000), []);
    assert.deepEqual(check(9000), []);
    assert.deepEqual(check(10_000, [task], 0), []);
    assert.deepEqual(check(11_000), []);
    monitor.reset();
    assert.deepEqual(check(12_000), []);
  } finally { rmSync(dir, { recursive: true, force: true }); }
});
