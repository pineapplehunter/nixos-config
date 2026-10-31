import { homedir } from "node:os";
import { join } from "node:path";
import {
  lazyStream,
  type Api,
  type Model,
  type Provider,
  type SimpleStreamOptions,
  type TranscriptContext,
} from "@earendil-works/pi-ai";
import { ModelRuntime, type ExtensionAPI, type ExtensionContext } from "@earendil-works/pi-coding-agent";
import {
  ACCOUNTS, CodexAccounts, DEFAULT_RESERVE, formatAccount, officialOrigin, PROVIDER,
  readReserve, saveReserve, UPSTREAM, USAGE_TTL_MS, type Account,
} from "./accounts.js";
import { withProviderIdentity } from "./stream.js";

const STATUS = "codex-auto";
const COUNTDOWN_REFRESH_MS = 60_000;
const LIMIT_ERROR = /usage.limit|rate.limit|quota.exceeded|hit your ChatGPT usage limit/i;

export default async function (pi: ExtensionAPI): Promise<void> {
  if (process.env.PI_WRAPPER_PROFILE !== "auto") return;
  const root = join(homedir(), ".pi");
  const [personal, work] = await Promise.all([
    ModelRuntime.create({ authPath: join(root, "agent", "auth.json"), modelsPath: join(root, "agent", "models.json") }),
    ModelRuntime.create({ authPath: join(root, "agent-work", "auth.json"), modelsPath: join(root, "agent-work", "models.json") }),
  ]);
  let session: ExtensionContext | undefined;
  let timer: ReturnType<typeof setInterval> | undefined;
  let countdownTimer: ReturnType<typeof setInterval> | undefined;
  let controller: AbortController | undefined;
  let lastWarning = "";

  const updateStatus = () => {
    const ctx = session;
    if (!ctx || ctx.model?.provider !== PROVIDER || ctx.mode !== "tui") return;
    try {
      const parts = ACCOUNTS.map((account) => {
        const text = formatAccount(account, accounts.states[account], ctx.model);
        return account === accounts.active ? ctx.ui.theme.fg("accent", text) : text;
      });
      ctx.ui.setStatus(STATUS, parts.join(" "));
    } catch { /* Session may have been replaced while a request was finishing. */ }
  };
  const accounts = new CodexAccounts({ personal, work }, join(root, "agent", "codex-auto.json"), updateStatus);
  const original = personal.getProvider(UPSTREAM);
  if (!original) throw new Error("codex-auto: Pi's Codex provider is unavailable");

  // Own the catalog: agent-auto's upstream provider has no default credentials
  // and cannot perform its own authenticated refresh. Never enumerate its registry.
  let models = personal.getModels(UPSTREAM).map((model) => ({ ...model, provider: PROVIDER }));

  const run = (model: Model<Api>, context: TranscriptContext, options?: SimpleStreamOptions) =>
    lazyStream(model, async () => {
      const signal = options?.signal ?? new AbortController().signal;
      if (!officialOrigin(model.baseUrl)) throw new Error("codex-auto: refusing a non-ChatGPT Codex endpoint.");
      const selected = await accounts.select(model, signal);
      const warning = selected.account === "work" && accounts.reason.includes("unavailable") ? accounts.reason : "";
      if (warning && warning !== lastWarning && session?.hasUI) {
        session.ui.notify(`Codex Auto: ${warning}; using work.`, "warning");
      }
      lastWarning = warning;
      const send = (account: Account, auth: typeof selected.auth) => {
        const upstream = accounts.runtimes[account].getProvider(UPSTREAM);
        if (!upstream) throw new Error("codex-auto: Codex transport unavailable");
        // Normalize prior auto messages to Codex for Pi's tool-call and reasoning
        // replay rules. Published responses retain the selected auto identity
        // so session restoration does not try the unauthenticated upstream.
        const transcript = {
          ...context,
          messages: context.messages.map((message) => message.role === "assistant" && message.provider === PROVIDER
            ? { ...message, provider: UPSTREAM } : message),
        };
        return withProviderIdentity(upstream.streamSimple({ ...model, provider: UPSTREAM }, transcript, {
          ...options,
          apiKey: auth.auth.apiKey,
          headers: { ...options?.headers, ...auth.auth.headers },
          env: { ...options?.env, ...auth.env },
          // Pi partitions Codex WebSocket sessions by account ID and closes all
          // of them under the original Pi session ID on shutdown.
          onPayload: options?.onPayload ? (payload) => options.onPayload!(payload, model) : undefined,
          onResponse: options?.onResponse ? (response) => options.onResponse!(response, model) : undefined,
          onProviderStreamEvent: options?.onProviderStreamEvent
            ? (event) => options.onProviderStreamEvent!(event, model) : undefined,
        }), PROVIDER);
      };
      // Only retry a personal quota error before any output was published. Never
      // replay a partial response or a tool call, which could duplicate work.
      return (async function* () {
        let started = false;
        for await (const event of send(selected.account, selected.auth)) {
          if (event.type === "start") started = true;
          if (selected.account === "personal" && !started && event.type === "error"
            && LIMIT_ERROR.test(event.error.errorMessage ?? "") && !signal.aborted) {
            accounts.blockPersonal(model);
            try {
              const fallback = await accounts.work(model, signal, "personal request hit a quota limit");
              yield* send(fallback.account, fallback.auth);
            } catch {
              event.error.errorMessage = "codex-auto: personal quota reached and work account unavailable.";
              yield event;
            }
            return;
          }
          yield event;
        }
      })();
    });

  const provider: Provider = {
    id: PROVIDER,
    name: "Codex Auto",
    baseUrl: original.baseUrl,
    auth: { apiKey: {
      name: "Codex Auto accounts",
      check: async ({ signal }) => await accounts.configured(signal) ? { type: "api_key", source: "Codex accounts" } : undefined,
      resolve: async ({ signal }) => await accounts.configured(signal)
        ? { auth: { apiKey: "codex-auto" }, source: "Codex accounts" } : undefined,
    } },
    getModels: () => models,
    async refreshModels(context) {
      const result = await personal.refresh({
        providers: [UPSTREAM],
        allowNetwork: context.allowNetwork,
        force: context.force,
        signal: context.signal,
      });
      if (result.aborted || context.signal.aborted) return;
      const error = result.errors.get(UPSTREAM);
      if (error) throw error;
      const refreshed = personal.getModels(UPSTREAM).map((model) => ({ ...model, provider: PROVIDER }));
      await context.publish({ update: () => { models = refreshed; } });
    },
    stream: (model, context, options) => run(model, context, options),
    streamSimple: run,
  };
  pi.registerProvider(provider);

  const startStatus = (ctx: ExtensionContext) => {
    session = ctx;
    if (timer) clearInterval(timer);
    if (countdownTimer) clearInterval(countdownTimer);
    controller?.abort();
    controller = new AbortController();
    if (ctx.model?.provider !== PROVIDER || ctx.mode !== "tui") {
      ctx.ui.setStatus(STATUS, undefined);
      return;
    }
    updateStatus();
    const signal = controller.signal;
    const refresh = () => void accounts.refresh(signal).then(updateStatus).catch(() => updateStatus());
    refresh();
    timer = setInterval(refresh, USAGE_TTL_MS);
    timer.unref?.();
    countdownTimer = setInterval(updateStatus, COUNTDOWN_REFRESH_MS);
    countdownTimer.unref?.();
  };

  pi.on("session_start", (_event, ctx) => startStatus(ctx));
  pi.on("model_select", (_event, ctx) => startStatus(ctx));
  pi.on("session_shutdown", (_event, ctx) => {
    controller?.abort();
    if (timer) clearInterval(timer);
    if (countdownTimer) clearInterval(countdownTimer);
    timer = undefined;
    countdownTimer = undefined;
    ctx.ui.setStatus(STATUS, undefined);
    session = undefined;
  });

  pi.registerCommand("codex-auto-usage", {
    description: "Show Codex Auto accounts or set reserve: /codex-auto-usage reserve <0-100>",
    handler: async (args, ctx) => {
      const input = args.trim();
      const match = /^reserve\s+(\d+(?:\.\d+)?)%?$/i.exec(input);
      try {
        if (match) {
          await saveReserve(accounts.settingsPath, Number(match[1]));
          accounts.reserve = await readReserve(accounts.settingsPath);
        } else if (input && input !== "refresh") {
          ctx.ui.notify("Usage: /codex-auto-usage [refresh | reserve <0-100>]", "warning");
          return;
        }
        const signal = AbortSignal.timeout(15_000);
        await accounts.refresh(signal);
        const lines = ACCOUNTS.map((account) => {
          const state = accounts.states[account];
          const base = formatAccount(account, state, ctx.model?.provider === PROVIDER ? ctx.model : undefined);
          const resets = state.report?.groups[0]?.windows.filter((window) => window.resetAt)
            .map((window) => `${window.minutes === 300 ? "5h" : window.minutes === 10080 ? "wk" : `${window.minutes}m`} resets ${new Date(window.resetAt!).toLocaleString()}`) ?? [];
          return `${base}${state.error ? ` — ${state.error}` : ""}${resets.length ? ` — ${resets.join(", ")}` : ""}`;
        });
        ctx.ui.notify(`${lines.join("\n")}\nActive: ${accounts.active ?? "none yet"} — ${accounts.reason}\nPersonal reserve: ${accounts.reserve}% (default ${DEFAULT_RESERVE}%)`, "info");
        updateStatus();
      } catch (error) {
        ctx.ui.notify(error instanceof Error ? error.message : "Codex Auto usage unavailable", "error");
      }
    },
  });
}
