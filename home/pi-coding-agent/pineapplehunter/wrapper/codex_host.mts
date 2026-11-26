// Host-only Codex transport. No agent session, extensions, or tool execution.
import { createHash, randomUUID } from "node:crypto";
import { once } from "node:events";
import { readFile } from "node:fs/promises";
import { createServer, type IncomingMessage, type ServerResponse } from "node:http";
import { join } from "node:path";
import { ModelRuntime, VERSION } from "@PI_RUNTIME@";
import { isRetryableAssistantError } from "@PI_AI_RETRY@";
import type {
  Api,
  AssistantMessage,
  Message,
  Model,
  ModelsApiStreamOptions,
  SimpleStreamOptions,
} from "@earendil-works/pi-ai";
import { createImageHandler, IMAGE_BODY_LIMIT, imageAuth } from "./codex_image_host.mts";
import {
  codexSearch,
  searchModel,
  searchParameters,
  SearchError,
  SEARCH_BODY_LIMIT,
} from "./codex_search.mts";
import {
  ACCOUNTS,
  hasCode,
  isAccount,
  isRoute,
  list,
  record,
  type Account,
  type Route,
} from "./codex_protocol.mts";

const UPSTREAM = "openai-codex";
const MAX_BODY = 32 * 1024 * 1024;
const EFFORTS = ["minimal", "low", "medium", "high", "xhigh", "max"] as const;
type Reasoning = "off" | (typeof EFFORTS)[number];
const oneOf = <T extends string>(v: unknown, choices: readonly T[]): v is T =>
  choices.some((c) => c === v);
const boundedInt = (v: unknown, max: number) =>
  typeof v === "number" && Number.isSafeInteger(v) && v >= 0 && v <= max ? v : undefined;
const reasoningLevels = new Set<unknown>(["off", ...EFFORTS]);
const isReasoning = (value: unknown): value is Reasoning => reasoningLevels.has(value);
const roles = new Set<unknown>(["system", "user", "assistant", "toolResult"]);
type ChatModel = Model<Api>;
type Runtime = Pick<
  ModelRuntime,
  "checkAuth" | "getAuth" | "getModel" | "getModels" | "refresh" | "stream" | "streamSimple"
>;

function json(res: ServerResponse, status: number, data: unknown) {
  res.writeHead(status, { "Content-Type": "application/json" }).end(JSON.stringify(data));
}

async function requestBody(req: IncomingMessage, limit = MAX_BODY): Promise<unknown> {
  const n = Number(req.headers["content-length"]);
  if (!Number.isSafeInteger(n) || n < 1 || n > limit) return;
  const chunks: Uint8Array[] = [];
  for await (const chunk of req) chunks.push(chunk);
  try {
    return JSON.parse(Buffer.concat(chunks).toString("utf8"));
  } catch {
    return undefined;
  }
}

const USAGE_LIMIT = /usage.limit|rate.limit|quota|\b429\b/i;

export function quotaState(payload: unknown, model: Pick<ChatModel, "id" | "name">) {
  const report = record(payload);
  const normalize = (value: string) => value.toLowerCase().replace(/[^a-z0-9]/g, "");
  const keys = [normalize(model.id), normalize(model.name)];
  const variants = [model.id, model.name]
    .map((value) => value.toLowerCase().match(/codex[-\s]+([a-z0-9]+)/)?.[1])
    .filter((value) => value !== undefined);
  const extras = list(report?.additional_rate_limits).flatMap((value) => {
    const item = record(value);
    const key = item?.metered_feature ?? item?.limit_name;
    return typeof key === "string" ? [{ key, limits: item?.rate_limit }] : [];
  });
  const exact = extras.filter(({ key }) => keys.includes(normalize(key)));
  const matched = extras.filter(({ key }) =>
    variants.some((variant) =>
      key
        .toLowerCase()
        .split(/[^a-z0-9]+/)
        .includes(variant),
    ),
  );
  const groups = [
    report?.rate_limit,
    ...(exact.length ? exact : matched.length === 1 ? matched : []).map(({ limits }) => limits),
  ].map(record);
  if (!groups.every((group) => group !== undefined)) return;
  // Fail closed for Personal when the five-hour window or its usage is unknown.
  const windows = groups
    .flatMap((group) => [group.primary_window, group.secondary_window])
    .map(record)
    .filter((window) => window !== undefined);
  const used = (window: Record<string, unknown>) => {
    const value = numeric(window.used_percent);
    return value >= 0 ? value : NaN;
  };
  const fiveHour = windows.filter(
    (window) => numeric(window.window_minutes ?? numeric(window.limit_window_seconds) / 60) === 300,
  );
  const remaining = Math.min(...fiveHour.map((window) => Math.max(0, 100 - used(window))));
  return {
    blocked:
      groups.some((group) => group.allowed === false || group.limit_reached === true) ||
      windows.some((window) => used(window) >= 100),
    remaining: Number.isFinite(remaining) ? remaining : undefined,
  };
}

const WHAM = "https://chatgpt.com/backend-api/wham";
const RESET = `${WHAM}/rate-limit-reset-credits`;

async function accountAuth(runtime: Runtime, signal: AbortSignal) {
  const token = (await runtime.getAuth(UPSTREAM, { signal }))?.auth.apiKey;
  if (!token) return;
  const encoded = token.split(".")[1];
  if (!encoded) return;
  const claims = record(JSON.parse(Buffer.from(encoded, "base64url").toString("utf8")));
  const account = record(claims?.["https://api.openai.com/auth"]);
  const accountId = account?.chatgpt_account_id;
  if (typeof accountId !== "string" || !accountId) return;
  const subject =
    account?.chatgpt_user_id ?? claims?.sub ?? createHash("sha256").update(token).digest("hex");
  return {
    identity: JSON.stringify([accountId, subject]),
    headers: {
      Authorization: `Bearer ${token}`,
      "ChatGPT-Account-Id": accountId,
      Accept: "application/json",
    },
  };
}

type UsageResult = { payload?: unknown; denied?: boolean; limited?: boolean };

async function usage(runtime: Runtime, signal: AbortSignal): Promise<UsageResult | undefined> {
  try {
    const auth = await accountAuth(runtime, signal);
    if (!auth) return;
    const response = await fetch(`${WHAM}/usage`, {
      headers: auth.headers,
      redirect: "error",
      signal,
    });
    if (response.ok) return { payload: await response.json() };
    await response.body?.cancel();
    if (response.status === 401 || response.status === 403) return { denied: true };
    if (response.status === 429) return { limited: true };
  } catch {
    /* Missing quota data must not spend the personal reserve. */
  }
  return undefined;
}

const display = (value: unknown, fallback?: string) =>
  typeof value === "string"
    ? value
        .replace(/[\p{Cc}\p{Cf}]/gu, " ")
        .trim()
        .slice(0, 160) || fallback
    : fallback;
const numeric = (value: unknown) =>
  typeof value === "number" || (typeof value === "string" && value.trim()) ? Number(value) : NaN;

function usageView(payload: Record<string, unknown>) {
  const groups = [
    { label: "Codex", group: record(payload.rate_limit) },
    ...list(payload.additional_rate_limits)
      .slice(0, 16)
      .map((value) => {
        const item = record(value);
        return {
          label: display(item?.limit_name ?? item?.metered_feature) ?? "Additional",
          group: record(item?.rate_limit),
        };
      }),
  ];
  const windows = groups.flatMap(({ label, group }) =>
    [group?.primary_window, group?.secondary_window].flatMap((value) => {
      const window = record(value);
      const used = numeric(window?.used_percent);
      if (!window || !Number.isFinite(used)) return [];
      const expires = numeric(window.reset_at);
      const minutes = numeric(window.window_minutes ?? numeric(window.limit_window_seconds) / 60);
      return [
        {
          label,
          remaining: 100 - Math.min(100, Math.max(0, used)),
          minutes: Number.isFinite(minutes) && minutes > 0 ? Math.round(minutes) : undefined,
          resetsAt: Number.isFinite(expires) && expires > 0 ? expires * 1_000 : undefined,
        },
      ];
    }),
  );
  const resetCount = numeric(record(payload.rate_limit_reset_credits)?.available_count);
  const credits = record(payload.credits);
  const balance = numeric(credits?.balance);
  return {
    windows,
    plan: display(payload.plan_type),
    resetCount: Number.isSafeInteger(resetCount) && resetCount >= 0 ? resetCount : undefined,
    credits:
      credits?.unlimited === true
        ? "unlimited"
        : credits?.has_credits === false
          ? "none"
          : Number.isFinite(balance)
            ? balance
            : undefined,
  };
}

const CODEX_DIRECTORY = `https://chatgpt.com/backend-api/codex/models?client_version=${encodeURIComponent(VERSION)}`;
const CODEX_RESPONSES = "https://chatgpt.com/backend-api/codex/responses";
const fastFingerprint = (authorization: string | null) =>
  createHash("sha256")
    .update(authorization ?? "")
    .digest("hex");

// Keep tier discovery separate from the public/catalog snapshot. Only the
// verified account's authenticated directory may enable priority for a model.
type Capability = "unknown" | "unsupported" | "supported";
type FastCheck =
  { capability: "unknown" | "unsupported" } | { capability: "supported"; fingerprint: string };
type FastSupport = Extract<FastCheck, { capability: "supported" }>;

function fastDirectory() {
  // At most one entry per host runtime; never persisted.
  const cache = new Map<
    Runtime,
    { fingerprint: string; expires: number; tiers: Map<string, Capability> }
  >();
  return async (runtime: Runtime, model: ChatModel, signal: AbortSignal): Promise<FastCheck> => {
    const bounded = AbortSignal.any([signal, AbortSignal.timeout(5_000)]);
    try {
      const auth = await accountAuth(runtime, bounded);
      bounded.throwIfAborted();
      if (!auth) return { capability: "unknown" };
      const fingerprint = fastFingerprint(auth.headers.Authorization);
      let entry = cache.get(runtime);
      if (entry?.fingerprint !== fingerprint || entry.expires <= Date.now()) {
        const response = await fetch(CODEX_DIRECTORY, {
          headers: auth.headers,
          signal: bounded,
          redirect: "error",
        });
        if (!response.ok) {
          await response.body?.cancel();
          return { capability: "unknown" };
        }
        if (!response.body) return { capability: "unknown" };
        let size = 0;
        let body = "";
        const decoder = new TextDecoder();
        for await (const chunk of response.body) {
          size += chunk.byteLength;
          if (size > 8 * 1024 * 1024) return { capability: "unknown" };
          body += decoder.decode(chunk, { stream: true });
        }
        const models = record(JSON.parse(body + decoder.decode()))?.models;
        if (!Array.isArray(models)) return { capability: "unknown" };
        const tiers = new Map<string, Capability>();
        for (const value of list(models)) {
          const entry = record(value);
          const id = entry?.slug;
          if (typeof id !== "string" || !id.trim() || tiers.has(id))
            return { capability: "unknown" };
          const modern = entry?.service_tiers;
          const legacy = entry?.additional_speed_tiers;
          const valid = (value: unknown, predicate: (item: unknown) => boolean) =>
            value === undefined || (Array.isArray(value) && list(value).every(predicate));
          const advertised =
            (modern !== undefined || legacy !== undefined) &&
            valid(modern, (tier) => typeof record(tier)?.id === "string") &&
            valid(legacy, (tier) => typeof tier === "string");
          const priority =
            advertised &&
            (list(modern).some((tier) => record(tier)?.id === "priority") ||
              list(legacy).includes("fast"));
          const capability = !advertised ? "unknown" : priority ? "supported" : "unsupported";
          tiers.set(id, capability);
        }
        bounded.throwIfAborted();
        entry = { fingerprint, expires: Date.now() + 5 * 60_000, tiers };
        cache.set(runtime, entry);
      }
      const capability = entry.tiers.get(model.id) ?? "unknown";
      return capability === "supported" ? { capability, fingerprint } : { capability };
    } catch {
      return { capability: "unknown" };
    }
  };
}

const fastUnavailable = (account: Account, capability: Capability, model: ChatModel) =>
  capability === "unsupported"
    ? `Codex ${account} does not advertise Fast for ${model.id}. Use /fast to turn it off or choose another route.`
    : `Could not verify Codex Fast for ${model.id} on ${account}. Use /fast to turn it off or try again.`;

function priorityReasoning(model: ChatModel, level: Reasoning | undefined) {
  if (!model.reasoning || !level || level === "off") return undefined;
  // Match Pi's simple stream: of the allowed hint levels, prefer clamping up, then down.
  const index = EFFORTS.indexOf(level);
  return [...EFFORTS.slice(index), ...EFFORTS.slice(0, index).reverse()].find((candidate) => {
    const mapped = model.thinkingLevelMap?.[candidate];
    return (
      mapped !== null && (mapped !== undefined || (candidate !== "xhigh" && candidate !== "max"))
    );
  });
}

function displayFields(code: unknown, message: unknown): string | undefined {
  return [code, message].filter((s) => typeof s === "string" && s.trim()).join(": ") || undefined;
}

// Only extract provider-authored display fields. SDK exception strings may contain
// serialized events, HTTP bodies or local diagnostics and aren't safe to forward.
function providerFailure(data: unknown): string | undefined {
  const event = record(data);
  const response = record(event?.response);
  if (response?.status === "incomplete" &&
      (event?.type === "response.incomplete" || event?.type === "response.done" || event?.type === "response.completed")) {
    const reason = record(response.incomplete_details)?.reason;
    return typeof reason === "string" && reason ? `Response incomplete: ${reason}` : "Response incomplete without a provider reason";
  }
  const failed = event?.type === "response.failed";
  if (!failed && event?.type !== "error") return;
  const error = record(failed ? response?.error : event?.error);
  const message = (!failed && typeof event?.message === "string") ? event.message : error?.message;
  const code = (!failed && typeof event?.code === "string") ? event.code : error?.code;
  const detail = displayFields(code, message);
  if (!detail) return;
  return failed ? detail : `Codex error: ${detail}`;
}

// The SDK consumes the original response. Inspect only a bounded copy of failed
// responses, and never treat a raw HTTP body as a user-facing error.
async function httpFailure(response: Response): Promise<string | undefined> {
  const reader = response.clone().body?.getReader();
  if (!reader) return;
  const chunks: Uint8Array[] = [];
  let size = 0;
  try {
    while (true) {
      const { value, done } = await reader.read();
      if (done) break;
      size += value.length;
      if (size > 64 * 1024) return;
      chunks.push(value);
    }
    const error = record(record(JSON.parse(Buffer.concat(chunks).toString("utf8")))?.error);
    return displayFields(error?.code ?? error?.type, error?.message);
  } catch {
    // Malformed or non-JSON error responses use the broker's classified fallback.
  } finally {
    void reader.cancel().catch(() => {});
  }
  return undefined;
}

function streamError(message: AssistantMessage, account: Account, status: number | undefined) {
  // Preserve Pi's retry signal without forwarding upstream text, headers or diagnostics.
  const error = message.errorMessage ?? "";
  if (/context.length|context window|too many tokens/i.test(error))
    return "context_length_exceeded";
  if (status === 429 || USAGE_LIMIT.test(error)) return "Codex usage limit reached.";
  if (status === 403) return `Codex ${account} request forbidden (HTTP 403).`;
  if (status === 401 || /\b401\b|unauthoriz|authentication/i.test(error)) {
    return `Codex ${account} authentication failed. Run pi-codex-auth login ${account} on the host.`;
  }
  if (status === 408) return `Codex ${account}: upstream request timed out (HTTP 408).`;
  if (status !== undefined && status >= 500)
    return `Codex ${account}: upstream server error (HTTP ${status}).`;
  if (status !== undefined && status >= 400)
    return `Codex ${account} request rejected (HTTP ${status}).`;
  if (isRetryableAssistantError(message))
    return `Codex ${account}: upstream server or connection error.`;
  return `Codex ${account} request failed.`;
}

type BrokerOptions = {
  readReserve?: () => Promise<number>;
  readUsage?: typeof usage;
  state?: string;
};
type ResetTicket = { account: Account; identity: string; creditId?: string; until: number };

export function broker(
  runtimes: Record<Account, Runtime>,
  { readReserve = async () => 15, readUsage = usage, state }: BrokerOptions = {},
) {
  const runtime = runtimes.work; // Catalog metadata is public and shared across accounts.
  const authReady = async (account: Account, signal?: AbortSignal) => {
    try {
      return (await runtimes[account].checkAuth(UPSTREAM, { signal }))?.type === "oauth";
    } catch {
      return false;
    }
  };
  const routes = async (signal: AbortSignal): Promise<Route[]> => {
    const ready = await Promise.all(ACCOUNTS.map((account) => authReady(account, signal)));
    const configured = ACCOUNTS.filter((_, index) => ready[index]);
    return configured.length === 2 ? [...configured, "auto"] : configured;
  };
  const quota = async (account: Account, model: ChatModel, signal: AbortSignal) => {
    const result = await readUsage(
      runtimes[account],
      AbortSignal.any([signal, AbortSignal.timeout(5_000)]),
    );
    signal.throwIfAborted();
    return {
      ...quotaState(result?.payload, model),
      denied: result?.denied,
      limited: result?.limited,
    };
  };
  let personalBlockedUntil = 0;
  async function workAvailable(model: ChatModel, signal: AbortSignal) {
    if (!(await authReady("work", signal))) return false;
    const { blocked, denied, limited } = await quota("work", model, signal);
    return !blocked && !denied && !limited;
  }
  let refreshing: ReturnType<Runtime["refresh"]> | undefined;
  const refreshCatalog = (force: boolean) => {
    if (!refreshing) {
      refreshing = authReady("work")
        .then((ready) =>
          (ready ? runtime : runtimes.personal).refresh({
            providers: [UPSTREAM],
            allowNetwork: true,
            force,
            signal: AbortSignal.timeout(10_000),
          }),
        )
        .finally(() => {
          refreshing = undefined;
        });
    }
    return refreshing;
  };
  const readFast = fastDirectory();
  const tickets = new Map<string, ResetTicket>();
  const image =
    state &&
    createImageHandler(
      state,
      (id) => runtime.getModel(UPSTREAM, id) ?? runtimes.personal.getModel(UPSTREAM, id),
    );
  return createServer({ requestTimeout: 15_000 }, async (req, res) => {
    const abort = new AbortController();
    res.once("close", () => abort.abort());
    const signal = AbortSignal.any([abort.signal, AbortSignal.timeout(15 * 60_000)]);
    try {
      if (
        req.method === "GET" &&
        ["/v1/catalog", "/v1/catalog?refresh=1", "/v1/catalog?force=1"].includes(req.url ?? "")
      ) {
        let warning;
        if (req.url !== "/v1/catalog") {
          try {
            const result = await refreshCatalog(req.url === "/v1/catalog?force=1");
            if (result.aborted || result.errors.has(UPSTREAM))
              warning = "Codex catalog refresh failed; using the last available catalog.";
          } catch {
            warning = "Codex catalog refresh failed; using the last available catalog.";
          }
        }
        const available = await routes(signal);
        // No provider URLs, configuration, or auth values cross the socket.
        const catalog = available.includes("work") ? runtime : runtimes.personal;
        const models = catalog
          .getModels(UPSTREAM)
          .map(({ headers, baseUrl, compat, ...model }) => model);
        return json(res, 200, { ready: available.length > 0, routes: available, models, warning });
      }
      if (req.method !== "POST") return json(res, 404, { error: "Unknown operation." });
      if (req.url === "/v1/search") {
        const options = searchParameters(await requestBody(req, SEARCH_BODY_LIMIT));
        if (!options) return json(res, 400, { error: "Invalid Codex search parameters." });
        const bounded = AbortSignal.any([signal, AbortSignal.timeout(60_000)]);
        const model = searchModel(
          [...runtime.getModels(UPSTREAM), ...runtimes.personal.getModels(UPSTREAM)],
          options.model,
        );
        if (!model)
          return json(res, 400, { error: "No matching Codex search model in the host catalog." });
        let account = options.route;
        if (account === "auto") {
          const reserve = await readReserve();
          const personal =
            Date.now() >= personalBlockedUntil && (await authReady("personal", bounded))
              ? await quota("personal", model, bounded)
              : undefined;
          if (
            personal?.remaining !== undefined &&
            personal.remaining > reserve &&
            !personal.blocked &&
            !personal.denied &&
            !personal.limited
          )
            account = "personal";
          else if (await workAvailable(model, bounded)) account = "work";
          else
            return json(res, 429, {
              error: "Codex Auto: Work unavailable; the Personal reserve is protected.",
            });
        }
        const runSearch = async (selected: Account) => {
          bounded.throwIfAborted();
          if (!(await authReady(selected, bounded)))
            throw new SearchError(401, "Host Codex login unavailable.");
          const auth = await accountAuth(runtimes[selected], bounded);
          if (!auth) throw new SearchError(401, "Host Codex login unavailable.");
          return codexSearch(model, options, auth, bounded);
        };
        try {
          let result;
          try {
            result = await runSearch(account);
          } catch (error) {
            if (
              !(error instanceof SearchError) ||
              !error.retryableQuota ||
              options.route !== "auto" ||
              account !== "personal"
            )
              throw error;
            personalBlockedUntil = Date.now() + 60_000;
            if (!(await workAvailable(model, bounded))) throw error;
            account = "work";
            result = await runSearch(account);
          }
          return json(res, 200, { ...result, account });
        } catch (error) {
          if (error instanceof SearchError)
            return json(res, error.status, { error: error.message });
          if (bounded.reason?.name === "TimeoutError" && !res.destroyed)
            return json(res, 504, { error: "Codex hosted web search timed out." });
          throw error;
        }
      }
      if (req.url === "/v1/image" && image) {
        if (Number(req.headers["content-length"]) > IMAGE_BODY_LIMIT) {
          return json(res, 413, { error: "Image request exceeded the input limit." });
        }
        const [status, payload] = await image(
          () => requestBody(req, IMAGE_BODY_LIMIT),
          AbortSignal.any([signal, AbortSignal.timeout(300_000)]),
        );
        return json(res, status, payload);
      }
      if (["/v1/usage", "/v1/reset-options", "/v1/reset"].includes(req.url ?? "")) {
        const data = record(await requestBody(req));
        const account = data?.account;
        if (!isAccount(account)) return json(res, 400, { error: "Select Personal or Work." });
        const bounded = AbortSignal.any([signal, AbortSignal.timeout(10_000)]);
        if (!(await authReady(account, bounded)))
          return json(res, 401, { error: "Host login unavailable." });
        if (req.url === "/v1/usage") {
          const result = await readUsage(runtimes[account], bounded);
          const payload = record(result?.payload);
          if (!payload) return json(res, 502, { error: "Codex usage is unavailable." });
          return json(res, 200, usageView(payload));
        }
        for (const [key, ticket] of tickets) if (ticket.until <= Date.now()) tickets.delete(key);
        const auth = await accountAuth(runtimes[account], bounded);
        if (!auth) return json(res, 401, { error: "Host login unavailable." });
        if (req.url === "/v1/reset-options") {
          const response = await fetch(RESET, {
            headers: auth.headers,
            redirect: "error",
            signal: bounded,
          });
          if (!response.ok) {
            await response.body?.cancel();
            return json(res, 502, { error: "Codex reset credits are unavailable." });
          }
          const payload = record(await response.json());
          const count = numeric(payload?.available_count);
          if (!Number.isSafeInteger(count) || count < 0)
            return json(res, 502, { error: "Invalid reset credit response." });
          const entries = payload?.credits;
          const credits = list(entries)
            .map(record)
            .filter(
              (credit): credit is Record<string, unknown> =>
                credit?.status === "available" &&
                credit.reset_type === "codex_rate_limits" &&
                typeof credit.id === "string" &&
                credit.id.length > 0 &&
                credit.id.length <= 1024,
            )
            .slice(0, Math.min(count, 32));
          if (
            count > 0 &&
            credits.length === 0 &&
            (entries == null || (Array.isArray(entries) && entries.length === 0))
          )
            credits.push({});
          const options = credits.map((credit) => {
            const key = randomUUID();
            const expiresAt =
              typeof credit.expires_at === "string" ? Date.parse(credit.expires_at) : NaN;
            const creditId = typeof credit.id === "string" ? credit.id : undefined;
            tickets.set(key, {
              account,
              identity: auth.identity,
              creditId,
              until: Math.min(
                Date.now() + 120_000,
                Number.isFinite(expiresAt) ? expiresAt : Infinity,
              ),
            });
            return {
              key,
              title: display(credit.title, "Full reset"),
              description: display(credit.description),
              expiresAt: Number.isFinite(expiresAt) ? expiresAt : undefined,
            };
          });
          while (tickets.size > 256) {
            const oldest = tickets.keys().next();
            if (oldest.done) break;
            tickets.delete(oldest.value);
          }
          return json(res, 200, { count, options });
        }
        const key = data?.key;
        const ticket = typeof key === "string" ? tickets.get(key) : undefined;
        if (
          typeof key !== "string" ||
          !ticket ||
          ticket.account !== account ||
          ticket.identity !== auth.identity ||
          ticket.until <= Date.now()
        ) {
          return json(res, 409, {
            error: "Reset selection expired or the account changed. Open /usage again.",
          });
        }
        // Consume the ticket before making the request. Never resend after an uncertain outcome.
        tickets.delete(key);
        try {
          const response = await fetch(`${RESET}/consume`, {
            method: "POST",
            redirect: "error",
            signal: bounded,
            headers: { ...auth.headers, "Content-Type": "application/json" },
            body: JSON.stringify({ redeem_request_id: key, credit_id: ticket.creditId }),
          });
          if (response.ok) {
            const code = record(await response.json())?.code;
            if (
              typeof code === "string" &&
              ["reset", "nothing_to_reset", "no_credit", "already_redeemed"].includes(code)
            ) {
              return json(res, 200, { code });
            }
          } else await response.body?.cancel();
        } catch {
          /* Do not retry a possibly completed redemption. */
        }
        return json(res, 502, {
          error: "Reset outcome unknown. Refresh usage before trying again.",
        });
      }
      const checkFast = req.url === "/v1/fast";
      if (req.url !== "/v1/chat" && !checkFast)
        return json(res, 404, { error: "Unknown operation." });
      const data = record(await requestBody(req, checkFast ? 4_096 : MAX_BODY));
      const model =
        typeof data?.model === "string" &&
        (runtime.getModel(UPSTREAM, data.model) ??
          runtimes.personal.getModel(UPSTREAM, data.model));
      if (
        !data ||
        !model ||
        !isRoute(data.route) ||
        (checkFast
          ? Object.keys(data).some((key) => key !== "model" && key !== "route")
          : !Array.isArray(data.messages) ||
            list(data.messages).some((message) => !roles.has(record(message)?.role)) ||
            (data.reasoning !== undefined && !isReasoning(data.reasoning)) ||
            (data.fast !== undefined && typeof data.fast !== "boolean"))
      ) {
        return json(res, 400, {
          error: checkFast
            ? "Invalid Codex Fast capability request."
            : "Invalid Codex chat request.",
        });
      }
      const wantsFast = data.fast === true;
      if ((checkFast || wantsFast) && model.api !== "openai-codex-responses") {
        return json(res, 400, { error: "This model does not support Codex Fast requests." });
      }
      let account = data.route;
      if (account === "auto") {
        const reserve = await readReserve();
        const personal =
          Date.now() >= personalBlockedUntil && (await authReady("personal", signal))
            ? await quota("personal", model, signal)
            : undefined;
        if (
          personal?.remaining !== undefined &&
          personal.remaining > reserve &&
          !personal.blocked &&
          !personal.denied &&
          !personal.limited
        ) {
          account = "personal";
        } else if (await workAvailable(model, signal)) {
          account = "work";
        } else {
          return json(res, 429, {
            error: "Codex Auto: Work unavailable; the Personal reserve is protected.",
          });
        }
      } else if (!(await authReady(account, signal))) {
        return json(res, 401, { error: `Run pi-codex-auth login ${account} on the host.` });
      }
      signal.throwIfAborted();
      const fast =
        checkFast || wantsFast ? await readFast(runtimes[account], model, signal) : undefined;
      signal.throwIfAborted();
      if (checkFast) return json(res, 200, { account, capability: fast?.capability ?? "unknown" });
      if (fast && fast.capability !== "supported") {
        return json(res, 409, { error: fastUnavailable(account, fast.capability, model) });
      }
      // Only model IDs, transcript data and explicitly supported scalar options
      // come from Pi. Never accept client networking code, API keys, URLs, or headers.
      // Preserve replay for the selected route; let Pi convert messages
      // from a different provider when the user switches routes.
      // The broker checks roles above; the SDK owns the transcript payload format.
      const messages = (data.messages as Message[]).map((message) =>
        message.role === "assistant" && message.provider === "codex-host"
          ? { ...message, provider: UPSTREAM }
          : message,
      );
      const reasoning =
        isReasoning(data.reasoning) && data.reasoning !== "off" ? data.reasoning : undefined;
      const streamFor = async (
        account: Account,
        fast: FastSupport | undefined,
        onStatus: (status: number) => Promise<void>,
        onFailure: (detail: string | undefined) => void,
        secrets: string[],
      ) => {
        const displayFailure = (detail: string | undefined) => {
          if (!detail) return;
          for (const secret of secrets) detail = detail.replaceAll(secret, "[redacted]");
          onFailure(detail.replace(/[\u0000-\u001f\u007f-\u009f]/g, " ").slice(0, 4096));
        };
        const options = {
          signal,
          onResponse: ({ status }) => onStatus(status),
          onProviderStreamEvent: (event) => displayFailure(providerFailure(event)),
          cacheRetention: oneOf(data.cacheRetention, ["none", "short", "long"] as const) ? data.cacheRetention : undefined,
          temperature: typeof data.temperature === "number" && Number.isFinite(data.temperature) ? data.temperature : undefined,
          timeoutMs: boundedInt(data.timeoutMs, 900_000),
          maxRetries: boundedInt(data.maxRetries, 5),
          maxRetryDelayMs: boundedInt(data.maxRetryDelayMs, 900_000),
          sessionId:
            typeof data.sessionId === "string" && /^[\w-]{1,128}$/.test(data.sessionId)
              ? `${account}:${data.sessionId}`
              : undefined,
          maxTokens:
            typeof data.maxTokens === "number" &&
            Number.isSafeInteger(data.maxTokens) &&
            data.maxTokens > 0
              ? Math.min(data.maxTokens, model.maxTokens)
              : undefined,
          transport: oneOf(data.transport, ["auto", "websocket", "websocket-cached"] as const) ? data.transport : "sse",
          websocketConnectTimeoutMs: boundedInt(data.websocketConnectTimeoutMs, 900_000),
          fetch: async (url, init) => {
            if (url !== CODEX_RESPONSES) throw new Error("Unexpected Codex endpoint");
            if (
              fast &&
              fastFingerprint(new Headers(init?.headers).get("Authorization")) !== fast.fingerprint
            ) {
              throw new Error("Codex login changed after Fast capability verification.");
            }
            const headers = new Headers(init?.headers);
            secrets.splice(0, secrets.length, ...[headers.get("authorization")?.replace(/^Bearer /i, ""), headers.get("chatgpt-account-id")]
              .filter((s): s is string => !!s));
            onFailure(undefined); // Don't reuse a previous attempt's detail on an SDK retry.
            const response = await fetch(url, { ...init, redirect: "error" });
            if (!response.ok) displayFailure(await httpFailure(response));
            return response;
          },
        } satisfies ModelsApiStreamOptions<"openai-codex-responses">;
        const auth = options.transport !== "sse" && model.api === "openai-codex-responses"
          ? await accountAuth(runtimes[account], signal).catch(() => undefined) : undefined;
        const allowSocket = auth && (!fast || fastFingerprint(auth.headers.Authorization) === fast.fingerprint);
        const token = auth?.headers.Authorization.slice("Bearer ".length);
        const socket = allowSocket && token ? (await import("./codex_chat_ws.mts")).socketClient(
          model, messages, token, data.disableContinuation === true || options.cacheRetention === "none" ? undefined : options.sessionId,
        ) : undefined;
        if (socket && auth && token) secrets.push(token, auth.headers["ChatGPT-Account-Id"]);
        else options.transport = "sse"; // All runtime-managed requests must use the guarded fetch.
        const dispatch = socket ?? {
          stream: (o: ModelsApiStreamOptions<"openai-codex-responses">) => runtimes[account].stream(model, { messages }, o),
          streamSimple: (o: SimpleStreamOptions) => runtimes[account].streamSimple(model, { messages }, o),
        };
        // Pi's simple adapter drops serviceTier. Use the full Codex SDK
        // stream for priority so its request builder AND cost logic see the tier.
        const full = data.full === true;
        return fast || full
          ? dispatch.stream({
                ...options,
                serviceTier: fast ? "priority" : full && oneOf(data.serviceTier, ["auto", "default", "flex", "scale"] as const)
                  ? data.serviceTier : undefined,
                toolChoice: oneOf(data.toolChoice, ["auto", "none", "required"] as const) ? data.toolChoice : undefined,
                textVerbosity: full && oneOf(data.textVerbosity, ["low", "medium", "high"] as const) ? data.textVerbosity : undefined,
                reasoningSummary: full && (data.reasoningSummary === null ||
                  oneOf(data.reasoningSummary, ["auto", "concise", "detailed", "off", "on"] as const)) ? data.reasoningSummary : undefined,
                reasoningEffort: full
                  ? (oneOf(data.reasoningEffort, ["none", ...EFFORTS] as const) ? data.reasoningEffort : undefined)
                  : priorityReasoning(model, reasoning) ?? (model.reasoning ? "none" : undefined),
              },
            )
          : dispatch.streamSimple({
                ...options,
                reasoning,
                toolChoice: oneOf(data.toolChoice, ["auto", "none"] as const) ? data.toolChoice : undefined,
              },
            );
      };
      const statusEvents = req.headers["x-pi-codex-status-events"] === "1";
      res.writeHead(200, { "Content-Type": "application/x-ndjson",
        ...(statusEvents ? { "X-Pi-Codex-Status-Events": "1" } : {}),
      });
      res.flushHeaders();
      let workFast: FastSupport | undefined;
      const send = async (selected: Account, capability: FastSupport | undefined) => {
        let started = false;
        let upstreamStatus: number | undefined;
        let providerDetail: string | undefined;
        const secrets: string[] = [];
        for await (const event of await streamFor(selected, capability, async (status) => {
          upstreamStatus = status;
          if (statusEvents && !signal.aborted && !res.destroyed &&
              !res.write(JSON.stringify({ type: "codex-status", status }) + "\n")) {
            await once(res, "drain", { signal });
          }
        }, (detail) => { providerDetail = detail; }, secrets)) {
          if (signal.aborted || res.destroyed) break;
          let fastError;
          if (
            data.route === "auto" &&
            selected === "personal" &&
            !started &&
            event.type === "error" &&
            (upstreamStatus === 429 || USAGE_LIMIT.test(event.error.errorMessage ?? ""))
          ) {
            personalBlockedUntil = Date.now() + 60_000;
            if (await workAvailable(model, signal)) {
              const verified = wantsFast ? await readFast(runtimes.work, model, signal) : undefined;
              if (signal.aborted || res.destroyed) break;
              if (!verified || verified.capability === "supported") {
                workFast = verified;
                return true;
              }
              fastError = fastUnavailable("work", verified.capability, model);
            }
          }
          if (!started && req.headers["x-pi-codex-route-events"] === "1") {
            if (!res.write(JSON.stringify({ type: "codex-account", account: selected }) + "\n")) {
              await once(res, "drain", { signal });
            }
          }
          const field =
            event.type === "done" ? "message" : event.type === "error" ? "error" : "partial";
          const original =
            event.type === "done"
              ? event.message
              : event.type === "error"
                ? event.error
                : event.partial;
          const { diagnostics, errorMessage: _errorMessage, ...message } = original;
          // Pi also copies incomplete_details.reason into rawStopReason.
          if (message.rawStopReason) {
            for (const secret of secrets) message.rawStopReason = message.rawStopReason.replaceAll(secret, "[redacted]");
            message.rawStopReason = message.rawStopReason.slice(0, 4096);
          }
          const errorMessage =
            event.type === "error" ? fastError ?? streamError(event.error, selected, upstreamStatus) : undefined;
          if (errorMessage) {
            console.warn("Codex chat failure:", JSON.stringify({
              account: selected,
              model: model.id,
              fast: !!capability,
              upstreamStatus: upstreamStatus ?? null,
              streamStarted: started,
              errorMessage,
            }));
          }
          // The SDK synthesizes this quota notice (including the reset time) from
          // HTTP metadata. Preserve its known format, not arbitrary SDK exception text.
          const usageNotice = original.errorMessage?.match(
            /^You have hit your ChatGPT usage limit(?: \((?:free|plus|pro|team|business|enterprise|edu) plan\))?\.(?: Try again in ~\d+ min\.)?$/,
          )?.[0];
          const result = errorMessage
            ? { ...message, errorMessage: fastError ?? usageNotice ?? providerDetail ?? errorMessage }
            : message;
          started = true;
          if (!res.write(JSON.stringify({ ...event, [field]: result }) + "\n")) {
            await once(res, "drain", { signal });
          }
        }
        return false;
      };
      if (await send(account, fast)) await send("work", workFast);
      res.end();
    } catch {
      if (res.destroyed) return;
      if (res.headersSent) res.destroy();
      else json(res, 502, { error: "Codex broker request failed." });
    }
  });
}

if (process.argv[2] === "image-auth") {
  process.exitCode = await imageAuth(process.argv[3], process.argv[4]);
} else if (process.argv[2] === "serve") {
  if (process.env.LISTEN_PID !== String(process.pid) || process.env.LISTEN_FDS !== "1") {
    throw new Error("Expected one systemd socket.");
  }
  const state = process.argv[3];
  const openRuntime = (account: Account) =>
    ModelRuntime.create({
      authPath: join(state, account, "auth.json"),
      modelsPath: null,
      refreshOnCreate: false,
    });
  const [personal, work] = await Promise.all([openRuntime("personal"), openRuntime("work")]);
  const runtimes = { personal, work };
  const server = broker(runtimes, {
    state,
    readReserve: async () => {
      try {
        const value = (await readFile(join(state, "reserve"), "utf8")).trim();
        return /^(?:100|[0-9]{1,2})(?:\.\d+)?$/.test(value) && Number(value) <= 100
          ? Number(value)
          : 100;
      } catch (error) {
        if (hasCode(error, "ENOENT")) return 15;
        return 100;
      }
    },
  });
  server.listen({ fd: 3 });
  process.once("SIGTERM", () => {
    server.close();
    server.closeAllConnections();
    void Promise.all(Object.values(runtimes).map((runtime) => runtime.settleCredentialWrites()));
  });
}
