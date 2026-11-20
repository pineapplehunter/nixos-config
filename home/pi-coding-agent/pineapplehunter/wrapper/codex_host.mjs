// Host-only Codex transport. No agent session, extensions, or tool execution.
import { createHash, randomUUID } from "node:crypto";
import { once } from "node:events";
import { readFile } from "node:fs/promises";
import { createServer } from "node:http";
import { join } from "node:path";
import { ModelRuntime, VERSION } from "@PI_RUNTIME@";
import { createImageHandler, IMAGE_BODY_LIMIT, imageAuth } from "@IMAGE_HOST@";
import { codexSearch, searchModel, searchParameters, SearchError, SEARCH_BODY_LIMIT } from "@SEARCH_HOST@";

const UPSTREAM = "openai-codex";
const MAX_BODY = 32 * 1024 * 1024;
const REASONING = new Set(["off", "minimal", "low", "medium", "high", "xhigh", "max"]);
const roles = new Set(["system", "user", "assistant", "toolResult"]);

function json(res, status, data) {
  res.writeHead(status, { "Content-Type": "application/json" }).end(JSON.stringify(data));
}

async function requestBody(req, limit = MAX_BODY) {
  const n = Number(req.headers["content-length"]);
  if (!Number.isSafeInteger(n) || n < 1 || n > limit) return;
  const chunks = [];
  for await (const chunk of req) chunks.push(chunk);
  try { return JSON.parse(Buffer.concat(chunks).toString("utf8")); }
  catch { return undefined; }
}

const ACCOUNTS = ["personal", "work"];
const USAGE_LIMIT = /usage.limit|rate.limit|quota|\b429\b/i;

export function quotaState(report, model) {
  const normalize = (value) => value.toLowerCase().replace(/[^a-z0-9]/g, "");
  const keys = [normalize(model.id), normalize(model.name)];
  const variants = [model.id, model.name].map((value) => value.toLowerCase().match(/codex[-\s]+([a-z0-9]+)/)?.[1]).filter(Boolean);
  const extras = (Array.isArray(report?.additional_rate_limits) ? report.additional_rate_limits : [])
    .map((item) => ({ key: item?.metered_feature ?? item?.limit_name, limits: item?.rate_limit }))
    .filter((item) => typeof item.key === "string");
  const exact = extras.filter(({ key }) => keys.includes(normalize(key)));
  const matched = extras.filter(({ key }) => variants.some((variant) => key.toLowerCase().split(/[^a-z0-9]+/).includes(variant)));
  const groups = [report?.rate_limit, ...(exact.length ? exact : matched.length === 1 ? matched : []).map(({ limits }) => limits)];
  if (groups.some((group) => !group || typeof group !== "object")) return;
  // Fail closed for Personal when the five-hour window or its usage is unknown.
  const windows = groups.flatMap((group) => [group.primary_window, group.secondary_window]).filter((window) => window != null);
  const used = (window) => {
    const value = window.used_percent;
    return (typeof value === "number" || (typeof value === "string" && value.trim())) && Number(value) >= 0
      ? Number(value) : NaN;
  };
  const fiveHour = windows.filter((window) => Number(window.window_minutes ?? Number(window.limit_window_seconds) / 60) === 300);
  const remaining = Math.min(...fiveHour.map((window) => Math.max(0, 100 - used(window))));
  return {
    blocked: groups.some((group) => group.allowed === false || group.limit_reached === true) || windows.some((window) => used(window) >= 100),
    remaining: Number.isFinite(remaining) ? remaining : undefined,
  };
}

const WHAM = "https://chatgpt.com/backend-api/wham";
const RESET = `${WHAM}/rate-limit-reset-credits`;

async function accountAuth(runtime, signal) {
  const token = (await runtime.getAuth(UPSTREAM, { signal }))?.auth.apiKey;
  if (!token) return;
  const claims = JSON.parse(Buffer.from(token.split(".")[1], "base64url").toString("utf8"));
  const account = claims["https://api.openai.com/auth"];
  const accountId = account?.chatgpt_account_id;
  if (typeof accountId !== "string" || !accountId) return;
  const subject = account?.chatgpt_user_id ?? claims.sub ?? createHash("sha256").update(token).digest("hex");
  return {
    identity: JSON.stringify([accountId, subject]),
    headers: { Authorization: `Bearer ${token}`, "ChatGPT-Account-Id": accountId, Accept: "application/json" },
  };
}

async function usage(runtime, signal) {
  try {
    const auth = await accountAuth(runtime, signal);
    if (!auth) return;
    const response = await fetch(`${WHAM}/usage`, { headers: auth.headers, redirect: "error", signal });
    if (response.ok) return { payload: await response.json() };
    await response.body?.cancel();
    if (response.status === 401 || response.status === 403) return { denied: true };
    if (response.status === 429) return { limited: true };
  } catch { /* Missing quota data must not spend the personal reserve. */ }
}

const display = (value, fallback) => typeof value === "string"
  ? value.replace(/[\p{Cc}\p{Cf}]/gu, " ").trim().slice(0, 160) || fallback : fallback;
const numeric = (value) => typeof value === "number" || (typeof value === "string" && value.trim())
  ? Number(value) : NaN;

function usageView(payload) {
  const groups = [["Codex", payload.rate_limit], ...(Array.isArray(payload.additional_rate_limits)
    ? payload.additional_rate_limits.slice(0, 16).map((item) => [display(item?.limit_name ?? item?.metered_feature, "Additional"), item?.rate_limit]) : [])];
  const windows = groups.flatMap(([label, group]) => [group?.primary_window, group?.secondary_window].flatMap((window) => {
    const used = numeric(window?.used_percent);
    if (!Number.isFinite(used)) return [];
    const expires = numeric(window.reset_at);
    const minutes = numeric(window.window_minutes ?? numeric(window.limit_window_seconds) / 60);
    return [{ label, remaining: 100 - Math.min(100, Math.max(0, used)),
      minutes: Number.isFinite(minutes) && minutes > 0 ? Math.round(minutes) : undefined,
      resetsAt: Number.isFinite(expires) && expires > 0 ? expires * 1_000 : undefined }];
  }));
  const resetCount = numeric(payload.rate_limit_reset_credits?.available_count);
  const balance = numeric(payload.credits?.balance);
  return { windows, plan: display(payload.plan_type),
    resetCount: Number.isSafeInteger(resetCount) && resetCount >= 0 ? resetCount : undefined,
    credits: payload.credits?.unlimited === true ? "unlimited" : payload.credits?.has_credits === false ? "none"
      : Number.isFinite(balance) ? balance : undefined };
}

const CODEX_DIRECTORY = `https://chatgpt.com/backend-api/codex/models?client_version=${encodeURIComponent(VERSION)}`;
const CODEX_RESPONSES = "https://chatgpt.com/backend-api/codex/responses";
const fastFingerprint = (authorization) => createHash("sha256").update(authorization ?? "").digest("hex");

// Keep tier discovery separate from the public/catalog snapshot. Only the
// verified account's authenticated directory may enable priority for a model.
function fastDirectory() {
  const cache = new Map(); // At most one entry per host runtime; never persisted.
  return async (runtime, model, signal) => {
    const bounded = AbortSignal.any([signal, AbortSignal.timeout(5_000)]);
    try {
      const auth = await accountAuth(runtime, bounded);
      bounded.throwIfAborted();
      if (!auth) return { capability: "unknown" };
      const fingerprint = fastFingerprint(auth.headers.Authorization);
      let entry = cache.get(runtime);
      if (entry?.fingerprint !== fingerprint || entry.expires <= Date.now()) {
        const response = await fetch(CODEX_DIRECTORY, { headers: auth.headers, signal: bounded, redirect: "error" });
        if (!response.ok) {
          await response.body?.cancel();
          return { capability: "unknown" };
        }
        let size = 0;
        let body = "";
        const decoder = new TextDecoder();
        for await (const chunk of response.body) {
          size += chunk.byteLength;
          if (size > 8 * 1024 * 1024) return { capability: "unknown" };
          body += decoder.decode(chunk, { stream: true });
        }
        const { models } = JSON.parse(body + decoder.decode());
        if (!Array.isArray(models)) return { capability: "unknown" };
        const tiers = new Map();
        for (const record of models) {
          const id = record?.slug;
          if (typeof id !== "string" || !id.trim() || tiers.has(id)) return { capability: "unknown" };
          const modern = record.service_tiers;
          const legacy = record.additional_speed_tiers;
          const valid = (list, predicate) => list === undefined || (Array.isArray(list) && list.every(predicate));
          const advertised = (modern !== undefined || legacy !== undefined) &&
            valid(modern, (tier) => typeof tier?.id === "string") && valid(legacy, (tier) => typeof tier === "string");
          const priority = advertised && (modern?.some((tier) => tier.id === "priority") || legacy?.includes("fast"));
          const capability = !advertised ? "unknown" : priority ? "supported" : "unsupported";
          tiers.set(id, capability);
        }
        bounded.throwIfAborted();
        entry = { fingerprint, expires: Date.now() + 5 * 60_000, tiers };
        cache.set(runtime, entry);
      }
      return { capability: entry.tiers.get(model.id) ?? "unknown", fingerprint };
    } catch {
      return { capability: "unknown" };
    }
  };
}

const fastUnavailable = (account, capability, model) => capability === "unsupported"
  ? `Codex ${account} does not advertise Fast for ${model.id}. Use /fast to turn it off or choose another route.`
  : `Could not verify Codex Fast for ${model.id} on ${account}. Use /fast to turn it off or try again.`;

function priorityReasoning(model, level) {
  if (!model.reasoning || !level || level === "off") return undefined;
  // Match Pi's simple stream: of the allowed hint levels, prefer clamping up, then down.
  const levels = [...REASONING];
  const index = levels.indexOf(level);
  return [...levels.slice(index), ...levels.slice(1, index).reverse()].find((candidate) => {
    const mapped = model.thinkingLevelMap?.[candidate];
    return mapped !== null && (mapped !== undefined || (candidate !== "xhigh" && candidate !== "max"));
  });
}

function streamError(error, account) {
  // Do not forward arbitrary upstream error bodies, headers, or diagnostics.
  if (/context.length|context window|too many tokens/i.test(error ?? "")) return "context_length_exceeded";
  if (USAGE_LIMIT.test(error ?? "")) return "Codex usage limit reached.";
  if (/\b401\b|\b403\b|unauthoriz|authentication/i.test(error ?? "")) {
    return `Codex ${account} authentication failed. Run pi-codex-auth login ${account} on the host.`;
  }
  return `Codex ${account} request failed.`;
}

export function broker(runtimes, { readReserve = async () => 15, readUsage = usage, state } = {}) {
  const runtime = runtimes.work; // Catalog metadata is public and shared across accounts.
  const authReady = async (account, signal) => {
    try { return (await runtimes[account].checkAuth(UPSTREAM, { signal }))?.type === "oauth"; }
    catch { return false; }
  };
  const routes = async (signal) => {
    const ready = await Promise.all(ACCOUNTS.map((account) => authReady(account, signal)));
    const configured = ACCOUNTS.filter((_, index) => ready[index]);
    return configured.length === 2 ? [...configured, "auto"] : configured;
  };
  const quota = async (account, model, signal) => {
    const result = await readUsage(runtimes[account], AbortSignal.any([signal, AbortSignal.timeout(5_000)]));
    signal.throwIfAborted();
    return { ...quotaState(result?.payload, model), denied: result?.denied, limited: result?.limited };
  };
  let personalBlockedUntil = 0;
  async function workAvailable(model, signal) {
    if (!(await authReady("work", signal))) return false;
    const { blocked, denied, limited } = await quota("work", model, signal);
    return !blocked && !denied && !limited;
  }
  let refreshing;
  const refreshCatalog = (force) => {
    if (!refreshing) {
      refreshing = authReady("work").then((ready) => (ready ? runtime : runtimes.personal).refresh({
        providers: [UPSTREAM], allowNetwork: true, force,
        signal: AbortSignal.timeout(10_000),
      })).finally(() => { refreshing = undefined; });
    }
    return refreshing;
  };
  const readFast = fastDirectory();
  const tickets = new Map();
  const image = state && createImageHandler(state, (id) =>
    runtime.getModel(UPSTREAM, id) ?? runtimes.personal.getModel(UPSTREAM, id));
  return createServer({ requestTimeout: 15_000 }, async (req, res) => {
    const abort = new AbortController();
    res.once("close", () => abort.abort());
    const signal = AbortSignal.any([abort.signal, AbortSignal.timeout(15 * 60_000)]);
    try {
      if (req.method === "GET" && ["/v1/catalog", "/v1/catalog?refresh=1", "/v1/catalog?force=1"].includes(req.url)) {
        let warning;
        if (req.url !== "/v1/catalog") {
          try {
            const result = await refreshCatalog(req.url === "/v1/catalog?force=1");
            if (result.aborted || result.errors.has(UPSTREAM)) warning = "Codex catalog refresh failed; using the last available catalog.";
          } catch {
            warning = "Codex catalog refresh failed; using the last available catalog.";
          }
        }
        const available = await routes(signal);
        // No provider URLs, configuration, or auth values cross the socket.
        const catalog = available.includes("work") ? runtime : runtimes.personal;
        const models = catalog.getModels(UPSTREAM).map(({ headers, baseUrl, compat, ...model }) => model);
        return json(res, 200, { ready: available.length > 0, routes: available, models, warning });
      }
      if (req.method !== "POST") return json(res, 404, { error: "Unknown operation." });
      if (req.url === "/v1/search") {
        const options = searchParameters(await requestBody(req, SEARCH_BODY_LIMIT));
        if (!options) return json(res, 400, { error: "Invalid Codex search parameters." });
        const bounded = AbortSignal.any([signal, AbortSignal.timeout(60_000)]);
        const model = searchModel([...runtime.getModels(UPSTREAM), ...runtimes.personal.getModels(UPSTREAM)], options.model);
        if (!model) return json(res, 400, { error: "No matching Codex search model in the host catalog." });
        let account = options.route;
        if (account === "auto") {
          const reserve = await readReserve();
          const personal = Date.now() >= personalBlockedUntil && await authReady("personal", bounded)
            ? await quota("personal", model, bounded) : undefined;
          if (personal?.remaining > reserve && !personal.blocked && !personal.denied && !personal.limited) account = "personal";
          else if (await workAvailable(model, bounded)) account = "work";
          else return json(res, 429, { error: "Codex Auto: Work unavailable; the Personal reserve is protected." });
        }
        const runSearch = async (selected) => {
          bounded.throwIfAborted();
          if (!await authReady(selected, bounded)) throw new SearchError(401, "Host Codex login unavailable.");
          const auth = await accountAuth(runtimes[selected], bounded);
          if (!auth) throw new SearchError(401, "Host Codex login unavailable.");
          return codexSearch(model, options, auth, bounded);
        };
        try {
          let result;
          try { result = await runSearch(account); }
          catch (error) {
            if (!(error instanceof SearchError) || !error.retryableQuota || options.route !== "auto" || account !== "personal") throw error;
            personalBlockedUntil = Date.now() + 60_000;
            if (!await workAvailable(model, bounded)) throw error;
            account = "work";
            result = await runSearch(account);
          }
          return json(res, 200, { ...result, account });
        } catch (error) {
          if (error instanceof SearchError) return json(res, error.status, { error: error.message });
          if (bounded.reason?.name === "TimeoutError" && !res.destroyed) return json(res, 504, { error: "Codex hosted web search timed out." });
          throw error;
        }
      }
      if (req.url === "/v1/image" && image) {
        if (Number(req.headers["content-length"]) > IMAGE_BODY_LIMIT) {
          return json(res, 413, { error: "Image request exceeded the input limit." });
        }
        const [status, payload] = await image(() => requestBody(req, IMAGE_BODY_LIMIT),
          AbortSignal.any([signal, AbortSignal.timeout(300_000)]));
        return json(res, status, payload);
      }
      if (["/v1/usage", "/v1/reset-options", "/v1/reset"].includes(req.url)) {
        const data = await requestBody(req);
        const account = data?.account;
        if (!ACCOUNTS.includes(account)) return json(res, 400, { error: "Select Personal or Work." });
        const bounded = AbortSignal.any([signal, AbortSignal.timeout(10_000)]);
        if (!(await authReady(account, bounded))) return json(res, 401, { error: "Host login unavailable." });
        if (req.url === "/v1/usage") {
          const result = await readUsage(runtimes[account], bounded);
          if (!result?.payload) return json(res, 502, { error: "Codex usage is unavailable." });
          return json(res, 200, usageView(result.payload));
        }
        for (const [key, ticket] of tickets) if (ticket.until <= Date.now()) tickets.delete(key);
        const auth = await accountAuth(runtimes[account], bounded);
        if (!auth) return json(res, 401, { error: "Host login unavailable." });
        if (req.url === "/v1/reset-options") {
          const response = await fetch(RESET, { headers: auth.headers, redirect: "error", signal: bounded });
          if (!response.ok) {
            await response.body?.cancel();
            return json(res, 502, { error: "Codex reset credits are unavailable." });
          }
          const payload = await response.json();
          const count = numeric(payload.available_count);
          if (!Number.isSafeInteger(count) || count < 0) return json(res, 502, { error: "Invalid reset credit response." });
          const credits = (Array.isArray(payload.credits) ? payload.credits : [])
            .filter((credit) => credit?.status === "available" && credit.reset_type === "codex_rate_limits" &&
              typeof credit.id === "string" && credit.id.length > 0 && credit.id.length <= 1024)
            .slice(0, Math.min(count, 32));
          if (count > 0 && credits.length === 0 && (payload.credits == null || payload.credits.length === 0)) credits.push({});
          const options = credits.map((credit) => {
            const key = randomUUID();
            const expiresAt = Date.parse(credit.expires_at);
            tickets.set(key, { account, identity: auth.identity, creditId: credit.id,
              until: Math.min(Date.now() + 120_000, Number.isFinite(expiresAt) ? expiresAt : Infinity) });
            return { key, title: display(credit.title, "Full reset"), description: display(credit.description),
              expiresAt: Number.isFinite(expiresAt) ? expiresAt : undefined };
          });
          while (tickets.size > 256) tickets.delete(tickets.keys().next().value);
          return json(res, 200, { count, options });
        }
        const key = data?.key;
        const ticket = tickets.get(key);
        if (!ticket || ticket.account !== account || ticket.identity !== auth.identity || ticket.until <= Date.now()) {
          return json(res, 409, { error: "Reset selection expired or the account changed. Open /usage again." });
        }
        // Consume the ticket before making the request. Never resend after an uncertain outcome.
        tickets.delete(key);
        try {
          const response = await fetch(`${RESET}/consume`, { method: "POST", redirect: "error", signal: bounded,
            headers: { ...auth.headers, "Content-Type": "application/json" },
            body: JSON.stringify({ redeem_request_id: key, credit_id: ticket.creditId }) });
          if (response.ok) {
            const { code } = await response.json();
            if (["reset", "nothing_to_reset", "no_credit", "already_redeemed"].includes(code)) return json(res, 200, { code });
          } else await response.body?.cancel();
        } catch { /* Do not retry a possibly completed redemption. */ }
        return json(res, 502, { error: "Reset outcome unknown. Refresh usage before trying again." });
      }
      const checkFast = req.url === "/v1/fast";
      if (req.url !== "/v1/chat" && !checkFast) return json(res, 404, { error: "Unknown operation." });
      const data = await requestBody(req, checkFast ? 4_096 : MAX_BODY);
      const model = typeof data?.model === "string" && (runtime.getModel(UPSTREAM, data.model) ?? runtimes.personal.getModel(UPSTREAM, data.model));
      if (!model || ![...ACCOUNTS, "auto"].includes(data.route) || (checkFast
        ? Object.keys(data).some((key) => key !== "model" && key !== "route")
        : !Array.isArray(data.messages) || data.messages.some((message) => !roles.has(message?.role)) ||
          (data.reasoning !== undefined && !REASONING.has(data.reasoning)) ||
          (data.fast !== undefined && typeof data.fast !== "boolean"))) {
        return json(res, 400, { error: checkFast ? "Invalid Codex Fast capability request." : "Invalid Codex chat request." });
      }
      const wantsFast = data.fast === true;
      if ((checkFast || wantsFast) && model.api !== "openai-codex-responses") {
        return json(res, 400, { error: "This model does not support Codex Fast requests." });
      }
      let account = data.route;
      if (account === "auto") {
        const reserve = await readReserve();
        const personal = Date.now() >= personalBlockedUntil && await authReady("personal", signal)
          ? await quota("personal", model, signal) : undefined;
        if (personal?.remaining > reserve && !personal.blocked && !personal.denied && !personal.limited) {
          account = "personal";
        } else if (await workAvailable(model, signal)) {
          account = "work";
        } else {
          return json(res, 429, { error: "Codex Auto: Work unavailable; the Personal reserve is protected." });
        }
      } else if (!(await authReady(account, signal))) {
        return json(res, 401, { error: `Run pi-codex-auth login ${account} on the host.` });
      }
      signal.throwIfAborted();
      const fast = checkFast || wantsFast ? await readFast(runtimes[account], model, signal) : undefined;
      signal.throwIfAborted();
      if (checkFast) return json(res, 200, { account, capability: fast.capability });
      if (fast && fast.capability !== "supported") {
        return json(res, 409, { error: fastUnavailable(account, fast.capability, model) });
      }
      // Only model IDs, transcript data and explicitly supported scalar options
      // come from Pi. Never accept client transport, API key, URL, or headers.
      // Preserve replay for the selected route; let Pi convert messages
      // from a different provider when the user switches routes.
      const messages = data.messages.map((message) =>
        message.role === "assistant" && message.provider === "codex-host"
          ? { ...message, provider: UPSTREAM } : message);
      const streamFor = (account, fast) => {
        const options = {
          signal,
          sessionId: typeof data.sessionId === "string" && /^[\w-]{1,128}$/.test(data.sessionId)
            ? `${account}:${data.sessionId}` : undefined,
          maxTokens: Number.isSafeInteger(data.maxTokens) && data.maxTokens > 0
            ? Math.min(data.maxTokens, model.maxTokens) : undefined,
          transport: "sse",
          fetch: (url, init) => {
            if (url !== CODEX_RESPONSES) throw new Error("Unexpected Codex endpoint");
            if (fast && fastFingerprint(new Headers(init?.headers).get("Authorization")) !== fast.fingerprint) {
              throw new Error("Codex login changed after Fast capability verification.");
            }
            return fetch(url, { ...init, redirect: "error" });
          },
        };
        // Pi 1.5.2's simple adapter drops serviceTier. Use the full Codex SDK
        // stream for priority so its request builder AND cost logic see the tier.
        return fast ? runtimes[account].stream(model, { messages }, {
          ...options, serviceTier: "priority", reasoningEffort: priorityReasoning(model, data.reasoning),
        }) : runtimes[account].streamSimple(model, { messages }, {
          ...options, reasoning: data.reasoning === "off" ? undefined : data.reasoning,
        });
      };
      res.writeHead(200, { "Content-Type": "application/x-ndjson" });
      res.flushHeaders();
      let workFast;
      const send = async (selected, capability) => {
        let started = false;
        for await (const event of streamFor(selected, capability)) {
          if (signal.aborted || res.destroyed) break;
          let fastError;
          if (data.route === "auto" && selected === "personal" && !started &&
              event.type === "error" && USAGE_LIMIT.test(event.error.errorMessage ?? "")) {
            personalBlockedUntil = Date.now() + 60_000;
            if (await workAvailable(model, signal)) {
              workFast = wantsFast ? await readFast(runtimes.work, model, signal) : undefined;
              if (signal.aborted || res.destroyed) break;
              if (!workFast || workFast.capability === "supported") return true;
              fastError = fastUnavailable("work", workFast.capability, model);
            }
          }
          if (!started && req.headers["x-pi-codex-route-events"] === "1") {
            if (!res.write(JSON.stringify({ type: "codex-account", account: selected }) + "\n")) {
              await once(res, "drain", { signal });
            }
          }
          started = true;
          const field = event.type === "done" ? "message" : event.type === "error" ? "error" : "partial";
          const { diagnostics, errorMessage, ...message } = event[field];
          if (event.type === "error") message.errorMessage = fastError ?? streamError(errorMessage, selected);
          if (!res.write(JSON.stringify({ ...event, [field]: message }) + "\n")) {
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
  const runtimes = Object.fromEntries(await Promise.all(ACCOUNTS.map(async (account) => [account, await ModelRuntime.create({
    authPath: join(state, account, "auth.json"),
    modelsPath: null,
    refreshOnCreate: false,
  })])));
  const server = broker(runtimes, { state, readReserve: async () => {
    try {
      const value = (await readFile(join(state, "reserve"), "utf8")).trim();
      return /^(?:100|[0-9]{1,2})(?:\.\d+)?$/.test(value) && Number(value) <= 100 ? Number(value) : 100;
    } catch (error) {
      if (error.code === "ENOENT") return 15;
      return 100;
    }
  } });
  server.listen({ fd: 3 });
  process.once("SIGTERM", () => {
    server.close();
    server.closeAllConnections();
    void Promise.all(Object.values(runtimes).map((runtime) => runtime.settleCredentialWrites()));
  });
}
