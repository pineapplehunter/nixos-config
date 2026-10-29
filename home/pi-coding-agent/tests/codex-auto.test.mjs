import assert from "node:assert/strict";
import { mkdtemp, readFile, rm, stat, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { CodexAccounts, formatAccount, parseUsage, personalReason, readReserve, resetCountdown, saveReserve } from "../pineapplehunter/extensions/codex-auto/accounts.ts";

const window = (seconds, used) => ({ limit_window_seconds: seconds, used_percent: used, reset_at: Math.floor(Date.now() / 1000) + 600 });
const usage = (used, weekly = 20) => ({ rate_limit: { primary_window: window(18000, used), secondary_window: window(604800, weekly) } });
const model = { id: "gpt-6.1-sol", name: "GPT 6.1 Sol" };
const token = (account) => `header.${Buffer.from(JSON.stringify({ "https://api.openai.com/auth": { chatgpt_account_id: account } })).toString("base64url")}.signature`;
const runtime = (account) => ({
  async checkAuth() { return { type: "oauth" }; },
  async getAuth() { return { auth: { apiKey: token(account) }, source: "OAuth" }; },
});

async function fixture(callback) {
  const dir = await mkdtemp(join(tmpdir(), "codex-auto-test-"));
  try { await callback(join(dir, "settings.json")); } finally { await rm(dir, { recursive: true, force: true }); }
}

test("reserve is persisted privately and shared across instances", async () => fixture(async (path) => {
  assert.equal(await readReserve(path), 15);
  await saveReserve(path, 20);
  assert.equal(await readReserve(path), 20);
  assert.equal((await stat(path)).mode & 0o777, 0o600);
  await assert.rejects(saveReserve(path, 101));
  await writeFile(path, "not-json");
  await assert.rejects(readReserve(path), /Invalid codex-auto/);
}));

test("detects 5h by duration and displays work's weekly-only window", () => {
  const report = parseUsage({ rate_limit: { primary_window: window(604800, 20), secondary_window: window(18000, 85) } });
  assert.match(personalReason(report, 15, model), /reserve/);
  assert.equal(personalReason(parseUsage(usage(84)), 15, model), undefined);
  assert.match(personalReason(parseUsage(usage(10, 100)), 15, model), /exhausted/);
  const work = parseUsage({ rate_limit: { primary_window: window(604800, 34) } });
  assert.match(formatAccount("work", { report: work }, model), /^\[work wk:66% ↻ 10m\]$/);
  assert.match(personalReason(work, 15, model), /unavailable/);
});

test("routes personal, work at threshold, and personal after reset", async () => fixture(async (path) => {
  let personalUsed = 70;
  const calls = [];
  const fetcher = async (_url, options) => {
    const id = options.headers["ChatGPT-Account-Id"];
    calls.push(id);
    return Response.json(id === "personal" ? usage(personalUsed) : { rate_limit: { primary_window: window(604800, 34) } });
  };
  const accounts = new CodexAccounts({ personal: runtime("personal"), work: runtime("work") }, path, () => {}, fetcher);
  const signal = new AbortController().signal;
  assert.equal((await accounts.select(model, signal)).account, "personal");
  personalUsed = 85;
  assert.equal((await accounts.select(model, signal)).account, "personal");
  assert.deepEqual(calls, ["personal"]); // No new request within the five-minute cache.
  await accounts.read("personal", signal, true); // Scheduled refresh sees the threshold.
  assert.equal((await accounts.select(model, signal)).account, "work");
  assert.deepEqual(calls, ["personal", "personal", "work"]);
  personalUsed = 0;
  await accounts.read("personal", signal, true);
  assert.equal((await accounts.select(model, signal)).account, "personal");
  assert.match(formatAccount("personal", accounts.states.personal, model), /^\[personal 5h:100% ↻ 10m · wk:80% ↻ 10m\]$/);
}));

test("a passed reset or changed credential invalidates the routing sample", async () => fixture(async (path) => {
  let identity = "personal";
  let calls = 0;
  const personal = { ...runtime("personal"), async getAuth() { return { auth: { apiKey: token(identity) } }; } };
  const accounts = new CodexAccounts({ personal, work: runtime("work") }, path, () => {}, async () => {
    calls++;
    return Response.json(usage(10));
  });
  const signal = new AbortController().signal;
  await accounts.select(model, signal);
  await accounts.select(model, signal);
  assert.equal(calls, 1);
  accounts.states.personal.report.groups[0].windows[0].resetAt = Date.now() - 1;
  await accounts.select(model, signal);
  assert.equal(calls, 2);
  identity = "new-personal";
  await accounts.select(model, signal);
  assert.equal(calls, 3);
}));

test("unknown personal usage fails over; missing work never spends reserve", async () => fixture(async (path) => {
  const failPersonal = async (_url, options) => options.headers["ChatGPT-Account-Id"] === "personal"
    ? new Response("unavailable", { status: 503 }) : Response.json({ rate_limit: { primary_window: window(604800, 34) } });
  const accounts = new CodexAccounts({ personal: runtime("personal"), work: runtime("work") }, path, () => {}, failPersonal);
  assert.equal((await accounts.select(model, new AbortController().signal)).account, "work");
  assert.match(accounts.reason, /personal usage unavailable/);
  accounts.runtimes.work = { async checkAuth() { return undefined; } };
  await assert.rejects(accounts.select(model, new AbortController().signal), /work authentication unavailable/);
}));

test("reset countdown matches pi-usage rounding and omits missing reset times", () => {
  const now = Date.now();
  assert.equal(resetCountdown(now + 60_001, now), "2m");
  assert.equal(resetCountdown(now + (2 * 60 + 30) * 60_000, now), "2h30m");
  assert.equal(resetCountdown(now + (3 * 1440 + 4 * 60 + 20) * 60_000, now), "3d4h");
  assert.equal(resetCountdown(now - 1000, now), "0m");
  assert.equal(resetCountdown(undefined, now), undefined);
  const report = parseUsage({ rate_limit: { primary_window: { limit_window_seconds: 18000, used_percent: 28 } } });
  assert.equal(formatAccount("personal", { report }, model), "[personal 5h:72%]");
});

test("invalid and expired data are not shown as available", () => {
  assert.throws(() => parseUsage({ rate_limit: { primary_window: window(18000, "invalid") } }));
  const report = parseUsage(usage(40));
  report.capturedAt -= 5 * 60_000;
  assert.equal(formatAccount("personal", { report }), "[personal ?]");
});
