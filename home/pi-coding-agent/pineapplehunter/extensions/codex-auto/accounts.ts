import { createHash, randomUUID } from "node:crypto";
import { readFile, rename, rm, writeFile } from "node:fs/promises";
import type { AuthResult, Model } from "@earendil-works/pi-ai";
import type { ModelRuntime } from "@earendil-works/pi-coding-agent";

export const UPSTREAM = "openai-codex";
export const PROVIDER = "codex-auto";
export const DEFAULT_RESERVE = 15;
export const USAGE_TTL_MS = 5 * 60_000;
export const ACCOUNTS = ["personal", "work"] as const;
export type Account = (typeof ACCOUNTS)[number];

type Window = { minutes: number; remaining: number; resetAt?: number };
type Group = { key: string; blocked: boolean; windows: Window[] };
export type Report = { capturedAt: number; groups: Group[] };
export type AccountState = { report?: Report; error?: string };
type AccountRead = AccountState & { auth?: AuthResult };

function object(value: unknown): Record<string, unknown> | undefined {
  return value && typeof value === "object" && !Array.isArray(value)
    ? value as Record<string, unknown> : undefined;
}

function number(value: unknown): number | undefined {
  const parsed = typeof value === "number" ? value
    : typeof value === "string" && value.trim() ? Number(value) : NaN;
  return Number.isFinite(parsed) ? parsed : undefined;
}

export function parseUsage(payload: unknown): Report {
  const root = object(payload);
  const parseGroup = (raw: unknown, key: string): Group => {
    const group = object(raw);
    if (!group) throw new Error("Missing rate limits");
    const windows: Window[] = [];
    for (const position of ["primary_window", "secondary_window"]) {
      const rawWindow = group[position];
      if (rawWindow == null) continue;
      const window = object(rawWindow);
      const used = number(window?.used_percent);
      const minutes = number(window?.window_minutes)
        ?? (number(window?.limit_window_seconds) ?? NaN) / 60;
      if (used === undefined || used < 0 || !(minutes > 0)) throw new Error("Invalid usage window");
      const reset = window?.reset_at ?? window?.resets_at;
      const numericReset = number(reset);
      const resetAt = numericReset === undefined
        ? (typeof reset === "string" ? Date.parse(reset) : NaN)
        : numericReset < 1e12 ? numericReset * 1000 : numericReset;
      windows.push({ minutes, remaining: Math.max(0, 100 - used),
        ...(Number.isFinite(resetAt) ? { resetAt } : {}) });
    }
    return { key, windows, blocked: group.allowed === false || group.limit_reached === true };
  };
  const groups = [parseGroup(root?.rate_limit, "codex")];
  if (Array.isArray(root?.additional_rate_limits)) {
    for (const raw of root.additional_rate_limits) {
      const item = object(raw);
      const key = item?.metered_feature ?? item?.limit_name;
      if (typeof key === "string") groups.push(parseGroup(item?.rate_limit, key));
    }
  }
  return { capturedAt: Date.now(), groups };
}

const normalize = (value: string) => value.toLowerCase().replace(/[^a-z0-9]/g, "");
export function applicableGroups(report: Report, model?: Pick<Model<any>, "id" | "name">): Group[] {
  const keys = model ? [normalize(model.id), normalize(model.name)] : [];
  const exact = report.groups.slice(1).filter((group) => keys.includes(normalize(group.key)));
  if (exact.length || !model) return [report.groups[0], ...exact];
  // pi-usage also recognizes a unique Codex model-variant limit by token.
  const variants = [model.id, model.name].map((value) => value.toLowerCase().match(/codex[-\s]+([a-z0-9]+)/)?.[1]).filter(Boolean);
  const matched = report.groups.slice(1).filter((group) => variants.some((variant) =>
    group.key.toLowerCase().split(/[^a-z0-9]+/).includes(variant!)));
  return [report.groups[0], ...(matched.length === 1 ? matched : [])];
}

export function personalReason(report: Report | undefined, reserve: number, model?: Model<any>): string | undefined {
  if (!report) return "personal usage unavailable";
  const groups = applicableGroups(report, model);
  if (groups.some((group) => group.blocked || group.windows.some((window) => window.remaining <= 0))) {
    return "personal quota exhausted";
  }
  const fiveHour = groups.flatMap((group) => group.windows).filter((window) => window.minutes === 300);
  if (!fiveHour.length) return "personal 5h quota unavailable";
  if (fiveHour.some((window) => window.remaining <= reserve)) return `personal 5h reserve (${reserve}%) reached`;
  return undefined;
}

// Match pi-usage's rounded-up countdown and compact day/hour/minute format.
export function resetCountdown(resetAt: number | undefined, now = Date.now()): string | undefined {
  if (resetAt === undefined || !Number.isFinite(resetAt)) return undefined;
  const totalMinutes = Math.max(0, Math.ceil((resetAt - now) / 60_000));
  const days = Math.floor(totalMinutes / 1440);
  const hours = Math.floor((totalMinutes % 1440) / 60);
  const minutes = totalMinutes % 60;
  if (days) return `${days}d${hours ? `${hours}h` : minutes ? `${minutes}m` : ""}`;
  if (hours) return `${hours}h${minutes ? `${minutes}m` : ""}`;
  return `${minutes}m`;
}

export function formatAccount(account: Account, state: AccountState, model?: Model<any>, now = Date.now()): string {
  if (!state.report || now - state.report.capturedAt >= USAGE_TTL_MS) return `[${account} ?]`;
  const groups = applicableGroups(state.report, model);
  const windows = groups.at(-1)?.windows ?? [];
  const label = (minutes: number) => minutes === 10080 ? "wk"
    : minutes % 1440 === 0 ? `${minutes / 1440}d`
    : minutes % 60 === 0 ? `${minutes / 60}h` : `${minutes}m`;
  const parts = windows.map((window) => {
    const reset = resetCountdown(window.resetAt, now);
    return `${label(window.minutes)}:${window.remaining.toFixed(0)}%${reset === undefined ? "" : ` ↻ ${reset}`}`;
  });
  return `[${account} ${parts.length ? parts.join(" · ") : "?"}]`;
}

export async function readReserve(path: string): Promise<number> {
  let text: string;
  try { text = await readFile(path, "utf8"); }
  catch (error) { if ((error as NodeJS.ErrnoException).code === "ENOENT") return DEFAULT_RESERVE; throw error; }
  try {
    const value = JSON.parse(text).reservePercent;
    if (typeof value === "number" && Number.isFinite(value) && value >= 0 && value <= 100) return value;
  } catch { /* Report a fixed diagnostic, never the file contents. */ }
  throw new Error("Invalid codex-auto.json; use /codex-auto-usage reserve <0-100> to repair it.");
}

export async function saveReserve(path: string, reservePercent: number): Promise<void> {
  if (!Number.isFinite(reservePercent) || reservePercent < 0 || reservePercent > 100) {
    throw new Error("Reserve must be between 0 and 100.");
  }
  const temporary = `${path}.${randomUUID()}.tmp`;
  try {
    await writeFile(temporary, `${JSON.stringify({ reservePercent }, null, 2)}\n`, { mode: 0o600, flag: "wx" });
    await rename(temporary, path);
  } finally { await rm(temporary, { force: true }); }
}

export function officialOrigin(url: string): boolean {
  try { return new URL(url).origin === "https://chatgpt.com"; } catch { return false; }
}

/** Owns no credential copies: Pi refreshes each original auth.json under its file lock. */
export class CodexAccounts {
  readonly states: Record<Account, AccountState> = { personal: {}, work: {} };
  active?: Account;
  reason = "No request routed yet";
  reserve = DEFAULT_RESERVE;
  // Prevent a slower footer probe from overwriting a newer request's usage.
  private generations = { personal: 0, work: 0 };
  private identities: Partial<Record<Account, string>> = {};
  private personalBlockedUntil = 0;

  readonly runtimes: Record<Account, ModelRuntime>;
  readonly settingsPath: string;
  private changed: () => void;
  private fetchUsage: typeof fetch;

  constructor(runtimes: Record<Account, ModelRuntime>, settingsPath: string,
    changed: () => void, fetchUsage: typeof fetch = globalThis.fetch) {
    this.runtimes = runtimes;
    this.settingsPath = settingsPath;
    this.changed = changed;
    this.fetchUsage = fetchUsage;
  }

  async configured(signal: AbortSignal): Promise<boolean> {
    const checks = await Promise.all(ACCOUNTS.map((account) => this.runtimes[account].checkAuth(UPSTREAM, { signal })));
    return checks.some((check) => check?.type === "oauth");
  }

  async read(account: Account, signal: AbortSignal, refresh = false): Promise<AccountRead> {
    let generation: number | undefined;
    const bounded = AbortSignal.any([signal, AbortSignal.timeout(10_000)]);
    let auth: AuthResult | undefined;
    let result: AccountRead;
    try {
      const runtime = this.runtimes[account];
      if ((await runtime.checkAuth(UPSTREAM, { signal: bounded }))?.type !== "oauth") throw new Error();
      auth = await runtime.getAuth(UPSTREAM, { signal: bounded });
      if (!auth?.auth.apiKey || (auth.auth.baseUrl && !officialOrigin(auth.auth.baseUrl))) throw new Error();
      // Usage must be queried with precisely this account's access token and workspace.
      const payload = JSON.parse(Buffer.from(auth.auth.apiKey.split(".")[1], "base64url").toString("utf8"));
      const accountId = payload["https://api.openai.com/auth"]?.chatgpt_account_id;
      if (typeof accountId !== "string" || !accountId) throw new Error();
      const identity = createHash("sha256").update(auth.auth.apiKey).digest("hex");
      const cached = this.states[account].report;
      if (!refresh && cached && this.identities[account] === identity &&
        Date.now() - cached.capturedAt < USAGE_TTL_MS &&
        !cached.groups.some((group) => group.windows.some((window) => window.resetAt !== undefined && window.resetAt <= Date.now()))) {
        return { auth, report: cached };
      }
      generation = ++this.generations[account];
      const response = await this.fetchUsage("https://chatgpt.com/backend-api/wham/usage", {
        headers: { Authorization: `Bearer ${auth.auth.apiKey}`, "ChatGPT-Account-Id": accountId, Accept: "application/json" },
        signal: bounded, redirect: "error",
      });
      if (!response.ok) {
        // Do not send inference with credentials the usage endpoint rejected.
        if (response.status === 401 || response.status === 403) auth = undefined;
        throw new Error();
      }
      result = { auth, report: parseUsage(await response.json()) };
      if (generation === this.generations[account]) this.identities[account] = identity;
    } catch {
      signal.throwIfAborted();
      generation ??= ++this.generations[account];
      result = { auth, error: auth ? "usage unavailable" : "Codex OAuth unavailable; log in with pi or pi-work" };
    }
    signal.throwIfAborted();
    if (generation === this.generations[account]) {
      this.states[account] = { report: result.report, error: result.error };
      this.changed();
    }
    return result;
  }

  async refresh(signal: AbortSignal): Promise<void> {
    this.reserve = await readReserve(this.settingsPath);
    await Promise.all(ACCOUNTS.map((account) => this.read(account, signal, true)));
  }

  async work(model: Model<any>, signal: AbortSignal, reason: string) {
    const result = await this.read("work", signal);
    if (!result.auth) throw new Error("codex-auto: work authentication unavailable. Run pi-work and /login openai-codex.");
    if (result.report && applicableGroups(result.report, model).some((group) =>
      group.blocked || group.windows.some((window) => window.remaining <= 0))) {
      throw new Error("codex-auto: work quota exhausted; personal reserve will not be consumed.");
    }
    this.active = "work";
    this.reason = `${reason}${result.error ? "; work usage unavailable" : ""}`;
    this.changed();
    return { account: "work" as Account, auth: result.auth };
  }

  async select(model: Model<any>, signal: AbortSignal) {
    this.reserve = await readReserve(this.settingsPath);
    const result = await this.read("personal", signal);
    const reason = Date.now() < this.personalBlockedUntil ? "personal request hit a quota limit"
      : personalReason(result.report, this.reserve, model);
    if (!reason && result.auth) {
      this.active = "personal";
      this.reason = `personal 5h remaining above ${this.reserve}%`;
      this.changed();
      return { account: "personal" as Account, auth: result.auth };
    }
    return this.work(model, signal, reason ?? "personal authentication unavailable");
  }

  blockPersonal(model: Model<any>): void {
    const report = this.states.personal.report;
    const resets = report ? applicableGroups(report, model).flatMap((group) => group.windows)
      .map((window) => window.resetAt ?? 0).filter((reset) => reset > Date.now()) : [];
    // Brief backoff if the provider's usage data has not caught up to the error.
    this.personalBlockedUntil = Math.min(...resets, Date.now() + 60_000);
  }
}
