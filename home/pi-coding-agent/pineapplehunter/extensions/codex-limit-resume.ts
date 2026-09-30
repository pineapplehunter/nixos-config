// Resume flow adapted from https://github.com/Haichiu/pi-limit-resume; Codex payload parsing follows
// https://github.com/narumiruna/pi-extensions/tree/main/packages/pi-usage/src/providers/codex.ts.
import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";

const PROVIDER = "openai-codex";
const GRACE_MS = 60_000;
const MAX_WAIT_MS = 5 * 60 * 60_000 + 15 * 60_000;
const PROBE_TIMEOUT_MS = 10_000;
const RESUME_TEXT = "continue";

type Message = {
	role?: unknown;
	provider?: unknown;
	model?: unknown;
	stopReason?: unknown;
	errorMessage?: unknown;
};

function latestMessage(ctx: ExtensionContext): { id?: string; message: Message } | undefined {
	const branch = ctx.sessionManager.getBranch();
	for (let i = branch.length - 1; i >= 0; i--) {
		const entry = branch[i]!;
		if (entry.type !== "message") continue;
		const id = (entry as { id?: unknown }).id;
		return { id: typeof id === "string" ? id : undefined, message: entry.message as Message };
	}
}

function codexLimit(text: string): boolean {
	return /Codex error: The usage limit has been reached|Codex usage limit reached|hit your ChatGPT usage limit|usage_limit_reached/i.test(text);
}

function resetFromMessage(text: string, now: number): { at: number; uncertainty: number } | undefined {
	const match = text.match(/(?:Resets in|Try again in)\s+(~?)([0-9.]+)\s*(days?|d|hours?|hrs?|hr|h|minutes?|mins?|min|m)/i);
	if (!match) return;
	const amount = Number(match[2]);
	const unit = match[3]!.toLowerCase();
	const multiplier = unit.startsWith("d") ? 86_400_000 : unit.startsWith("h") ? 3_600_000 : 60_000;
	const approximate = match[1] === "~";
	const uncertainty = !approximate ? 1_000 : unit.startsWith("h") && !String(match[2]).includes(".") ? 30 * 60_000 : 30_000;
	return { at: now + amount * multiplier, uncertainty };
}

function accountId(token: string): string | undefined {
	try {
		const encoded = token.split(".")[1];
		if (!encoded) return;
		const base64 = encoded.replaceAll("-", "+").replaceAll("_", "/").padEnd(Math.ceil(encoded.length / 4) * 4, "=");
		const payload = JSON.parse(atob(base64)) as Record<string, unknown>;
		const auth = payload["https://api.openai.com/auth"] as Record<string, unknown> | undefined;
		return typeof auth?.chatgpt_account_id === "string" ? auth.chatgpt_account_id : undefined;
	} catch {
		return;
	}
}

async function probeReset(ctx: ExtensionContext, signal: AbortSignal): Promise<number | undefined> {
	try {
		const auth = await ctx.modelRegistry.getProviderAuth(PROVIDER);
		const model = ctx.model?.provider === PROVIDER ? ctx.model : undefined;
		const token = auth?.auth.apiKey ?? await ctx.modelRegistry.getApiKeyForProvider(PROVIDER);
		const baseUrls = [auth?.auth.baseUrl, model?.baseUrl].filter((value): value is string => Boolean(value));
		const id = token && accountId(token);
		if (!token || !id || signal.aborted) return;
		if (baseUrls.some((value) => {
			try { return new URL(value).origin !== "https://chatgpt.com"; } catch { return true; }
		})) return;

		const url = "https://chatgpt.com/backend-api/wham/usage";
		const controller = new AbortController();
		const abort = () => controller.abort();
		signal.addEventListener("abort", abort, { once: true });
		const timeout = setTimeout(abort, PROBE_TIMEOUT_MS);
		try {
			const response = await fetch(url, {
				method: "GET",
				headers: {
					authorization: `Bearer ${token}`,
					"chatgpt-account-id": id,
					accept: "application/json",
				},
				signal: controller.signal,
				redirect: "error",
			});
			if (!response.ok) return;
			const payload = await response.json() as {
				rate_limit?: { primary_window?: UsageWindow; secondary_window?: UsageWindow };
				additional_rate_limits?: { rate_limit?: { primary_window?: UsageWindow; secondary_window?: UsageWindow } }[];
			};
			const reports = [payload.rate_limit, ...(payload.additional_rate_limits ?? []).map((item) => item.rate_limit)];
			const windows = reports.flatMap((rate) => rate ? [rate.primary_window, rate.secondary_window] : []);
			const isExhausted = (window: UsageWindow | undefined) => {
				const used = number(window?.used_percent);
				return used !== undefined && used >= 100;
			};
			if (windows.some((window) => windowMinutes(window) === 10_080 && isExhausted(window))) return;
			const exhausted = windows.filter((window) => windowMinutes(window) === 300 && isExhausted(window));
			if (!exhausted.length) return;
			const resets = exhausted.map((window) => epoch(window?.resets_at) ?? epoch(window?.reset_at));
			return resets.every((reset): reset is number => reset !== undefined) ? Math.max(...resets) : undefined;
		} finally {
			clearTimeout(timeout);
			signal.removeEventListener("abort", abort);
		}
	} catch {
		return;
	}
}

interface UsageWindow {
	window_minutes?: number;
	limit_window_seconds?: number;
	used_percent?: number | string;
	resets_at?: number | string;
	reset_at?: number | string;
}

function number(value: unknown): number | undefined {
	const parsed = typeof value === "number" ? value : typeof value === "string" && value.trim() ? Number(value) : NaN;
	return Number.isFinite(parsed) ? parsed : undefined;
}

function windowMinutes(window: UsageWindow | undefined): number | undefined {
	const minutes = number(window?.window_minutes);
	if (minutes !== undefined) return minutes;
	const seconds = number(window?.limit_window_seconds);
	return seconds === undefined ? undefined : Math.ceil(seconds / 60);
}

function epoch(value: unknown): number | undefined {
	const numeric = number(value);
	if (numeric !== undefined) return numeric < 1e12 ? numeric * 1000 : numeric;
	if (typeof value === "string") {
		const parsed = Date.parse(value);
		return Number.isFinite(parsed) ? parsed : undefined;
	}
}

export default function codexLimitResume(pi: ExtensionAPI): void {
	let timer: ReturnType<typeof setTimeout> | undefined;
	let pending: AbortController | undefined;
	let target: { sessionId: string | undefined; entryId: string; model: string } | undefined;
	let resumed = false;
	let ownAgentStart = false;

	function cancel(ctx: ExtensionContext, message?: string): void {
		const active = timer !== undefined || pending !== undefined || target !== undefined;
		if (timer) clearTimeout(timer);
		timer = undefined;
		pending?.abort();
		pending = undefined;
		target = undefined;
		if (active && message && ctx.hasUI) ctx.ui.notify(message, "info");
	}

	async function settled(ctx: ExtensionContext): Promise<void> {
		if (!ctx.hasUI) return;
		const latest = latestMessage(ctx);
		const message = latest?.message;
		if (message?.role === "assistant" && message.stopReason !== "error") {
			resumed = false;
			return;
		}
		if (message?.role !== "assistant" || message.stopReason !== "error") return;
		const isLimit = typeof message.errorMessage === "string" && codexLimit(message.errorMessage);
		if (resumed) {
			resumed = false;
			if (isLimit) ctx.ui.notify("Codex limit hit again after auto-continue; stopping.", "warning");
			return;
		}
		if (!isLimit || typeof message.errorMessage !== "string" || !latest?.id || ctx.model?.provider !== PROVIDER || ctx.model.id !== message.model) return;
		if (/weekly\s+100%|weekly.{0,40}(?:exhausted|limit reached)|7.day/i.test(message.errorMessage)) {
			ctx.ui.notify("Codex weekly limit detected; not auto-continuing.", "warning");
			return;
		}

		target = { sessionId: ctx.sessionManager.getSessionId(), entryId: latest.id, model: message.model as string };
		const detectedAt = Date.now();
		const messageReset = resetFromMessage(message.errorMessage, detectedAt);
		let resetAt = messageReset?.at;
		const uncertainty = messageReset?.uncertainty ?? 0;
		if (resetAt === undefined) {
			const probe = new AbortController();
			pending = probe;
			resetAt = await probeReset(ctx, probe.signal);
			if (pending !== probe || probe.signal.aborted) return;
			pending = undefined;
		}
		if (resetAt === undefined) {
			target = undefined;
			ctx.ui.notify("Codex limit detected, but its reset time is unavailable; not auto-continuing.", "warning");
			return;
		}

		const resumeAt = Math.max(resetAt, Date.now()) + uncertainty + GRACE_MS;
		if (resumeAt - Date.now() > MAX_WAIT_MS) {
			target = undefined;
			ctx.ui.notify("Codex reset is too far away; not auto-continuing.", "warning");
			return;
		}
		ctx.ui.notify(`Codex usage limit detected. Waiting until ${new Date(resumeAt).toLocaleTimeString()} before sending continue.`, "info");
		timer = setTimeout(() => {
			timer = undefined;
			try {
				const latestNow = latestMessage(ctx);
				if (!target || ctx.sessionManager.getSessionId() !== target.sessionId || latestNow?.id !== target.entryId ||
					ctx.model?.provider !== PROVIDER || ctx.model.id !== target.model || !ctx.isIdle() || ctx.hasPendingMessages()) {
					cancel(ctx, "Codex auto-continue cancelled: session, conversation, model, or activity changed.");
					return;
				}
				target = undefined;
				resumed = true;
				ownAgentStart = true;
				pi.sendUserMessage(RESUME_TEXT);
			} catch {
				cancel(ctx);
			}
		}, Math.max(0, resumeAt - Date.now()));
	}

	pi.registerCommand("codex-limit-resume", {
		description: "Show or cancel the pending Codex usage-limit continuation",
		handler: async (args, ctx) => {
			if (args.trim().toLowerCase() === "cancel") {
				if (timer || pending) cancel(ctx, "Codex auto-continue cancelled.");
				else ctx.ui.notify("No Codex auto-continue is pending.", "info");
			} else {
				ctx.ui.notify(timer || pending ? "Waiting for the Codex usage reset." : "No Codex auto-continue is pending.", "info");
			}
		},
	});

	pi.on("agent_settled", (_event, ctx) => settled(ctx));
	pi.on("input", (event, ctx) => {
		if (event.source !== "extension") cancel(ctx, "Codex auto-continue cancelled by new input.");
	});
	pi.on("model_select", (event, ctx) => {
		const model = event.model as { provider?: string; id?: string } | undefined;
		if (target && (model?.provider !== PROVIDER || model.id !== target.model)) cancel(ctx, "Codex auto-continue cancelled: model changed.");
	});
	pi.on("session_tree", (event, ctx) => {
		if (event.newLeafId !== event.oldLeafId) cancel(ctx, "Codex auto-continue cancelled: conversation branch changed.");
	});
	pi.on("agent_start", (event, ctx) => {
		if (ownAgentStart) ownAgentStart = false;
		else cancel(ctx, "Codex auto-continue cancelled because another run started.");
	});
	pi.on("session_shutdown", (_event, ctx) => cancel(ctx));
}
