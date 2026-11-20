// Host-only hosted search. The client cannot supply any upstream transport options.
const ENDPOINT = "https://chatgpt.com/backend-api/codex/responses";
export const SEARCH_BODY_LIMIT = 48 * 1024;
const KEYS = new Set(["route", "query", "model", "numResults", "recencyFilter", "domainFilter"]);
const RECENCY = { day: "24 hours", week: "week", month: "month", year: "year" };
const DOMAIN = /^-?(?=.{1,253}$)(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$/i;

export function searchParameters(data) {
  if (!data || typeof data !== "object" || Array.isArray(data) || Object.keys(data).some((key) => !KEYS.has(key)) ||
      !["personal", "work", "auto"].includes(data.route) ||
      typeof data.query !== "string" || !data.query.trim() || data.query.length > 4_000 ||
      (data.model !== undefined && (typeof data.model !== "string" || !/^[\w.-]{1,128}$/.test(data.model))) ||
      (data.numResults !== undefined && (!Number.isInteger(data.numResults) || data.numResults < 1 || data.numResults > 20)) ||
      (data.recencyFilter !== undefined && (typeof data.recencyFilter !== "string" || !Object.hasOwn(RECENCY, data.recencyFilter))) ||
      (data.domainFilter !== undefined && (!Array.isArray(data.domainFilter) || data.domainFilter.length > 100 ||
        data.domainFilter.some((value) => typeof value !== "string" || !DOMAIN.test(value))))) return;
  const domains = [...new Set((data.domainFilter ?? []).map((domain) => domain.toLowerCase()))];
  return { ...data, numResults: data.numResults ?? 5,
    allowed: domains.filter((domain) => !domain.startsWith("-")),
    blocked: domains.filter((domain) => domain.startsWith("-")).map((domain) => domain.slice(1)) };
}

export function searchModel(models, requested) {
  const eligible = models.filter(({ id, api }) => api === "openai-codex-responses" && /^gpt-\d/i.test(id));
  if (requested !== undefined) return eligible.find(({ id }) => id === requested);
  const candidates = eligible.filter(({ id }) => !/(?:^|-)(?:pro|ultra)(?:-|$)/.test(id))
    .sort((a, b) => b.id.localeCompare(a.id, "en", { numeric: true }));
  return candidates.find(({ id }) => id.split("-").includes("luna")) ??
    candidates.find(({ id }) => /^gpt-\d+(?:\.\d+)?$/.test(id)) ?? candidates[0];
}

export class SearchError extends Error {
  constructor(status, message, retryableQuota = false) {
    super(message);
    this.status = status;
    this.retryableQuota = retryableQuota;
  }
}
const invalidOutput = () => new SearchError(502, "Codex returned no valid hosted web search result.");

function checkedOutput(payload, items = [], searchSeen = false) {
  if (!payload || typeof payload !== "object" || payload.error || (payload.status && payload.status !== "completed")) {
    throw upstreamFailure(payload?.error, searchSeen || items.length > 0 || payload?.output?.length > 0);
  }
  const output = Array.isArray(payload.output) && payload.output.length ? payload.output : items;
  if (!searchSeen && !output.some((item) => item?.type === "web_search_call" && !["failed", "incomplete"].includes(item.status))) {
    throw invalidOutput();
  }
  return output;
}

function upstreamFailure(error, started) {
  const marker = error && [error.code, error.type].find((value) => typeof value === "string" && /usage.limit|rate.limit|quota/i.test(value));
  return marker ? new SearchError(429, "Codex usage limit reached.", !started) : invalidOutput();
}

async function responseOutput(response) {
  const chunks = [];
  let size = 0;
  if (!response.body) throw invalidOutput();
  for await (const chunk of response.body) {
    size += chunk.byteLength;
    if (size > 4 * 1024 * 1024) throw invalidOutput();
    chunks.push(chunk);
  }
  const text = Buffer.concat(chunks).toString("utf8").trim();
  if (text.startsWith("{")) return checkedOutput(JSON.parse(text));

  const items = [];
  let completed;
  let started = false;
  let searchSeen = false;
  for (const frame of text.split(/\r?\n\r?\n/)) {
    const data = frame.split(/\r?\n/).filter((line) => line.startsWith("data:")).map((line) => line.slice(5).trimStart()).join("\n");
    if (!data || data === "[DONE]") continue;
    const event = JSON.parse(data);
    switch (event.type) {
      case "error": throw upstreamFailure(event.error ?? event, started);
      case "response.failed":
      case "response.incomplete": throw upstreamFailure(event.response?.error, started || event.response?.output?.length > 0);
      case "response.output_text.delta":
      case "response.output_item.added": started = true; break;
      case "response.web_search_call.completed": started = searchSeen = true; break;
      case "response.output_item.done":
        started = true;
        items.push(event.item);
        if (event.item?.type === "web_search_call" && event.item.status === "completed") searchSeen = true;
        break;
      case "response.done":
      case "response.completed": completed = event.response; break;
    }
  }
  return checkedOutput(completed, items, searchSeen);
}

function resultView(output, options, token) {
  const answers = [];
  const urls = new Set();
  const results = [];
  const redact = (value) => typeof value === "string" ? value.replaceAll(token, "[redacted]") : "";
  const matches = (host, domains) => domains.some((domain) => host === domain || host.endsWith(`.${domain}`));
  function add(rawUrl, title, snippet) {
    if (typeof rawUrl !== "string" || rawUrl.includes(token) || rawUrl.length > 4_096) return;
    const url = URL.parse(rawUrl);
    if (!url || !["http:", "https:"].includes(url.protocol) || url.username || url.password) return;
    const host = url.hostname.replace(/\.$/, "");
    if ((options.allowed.length && !matches(host, options.allowed)) || matches(host, options.blocked)) return;
    if (url.searchParams.get("utm_source") === "openai") url.searchParams.delete("utm_source");
    if (urls.has(url.href) || results.length >= options.numResults) return;
    urls.add(url.href);
    results.push({ url: url.href, title: redact(title).trim().slice(0, 300) || url.href,
      snippet: snippet ?? "", ...(snippet ? { snippetSource: "generated" } : {}) });
  }
  for (const item of output) {
    if (item?.type !== "message" || item.role !== "assistant" || !Array.isArray(item.content)) continue;
    for (const part of item.content) {
      if (part?.type !== "output_text") continue;
      // Redact before slicing, so a citation span cannot expose a partial token.
      const text = redact(part.text);
      answers.push(text);
      for (const citation of Array.isArray(part.annotations) ? part.annotations : []) {
        if (citation?.type !== "url_citation") continue;
        const [start, end] = [citation.start_index, citation.end_index];
        const snippet = Number.isInteger(start) && Number.isInteger(end) && start >= 0 && end >= start
          ? text.slice(Math.max(0, start - 100), end + 100).trim().slice(0, 300) : "";
        add(citation.url, citation.title, snippet);
      }
    }
  }
  for (const item of output) {
    if (item?.type !== "web_search_call") continue;
    for (const group of [item.action?.sources, item.sources, item.results]) {
      for (const source of Array.isArray(group) ? group : []) add(source?.url ?? source?.source_website_url, source?.title ?? source?.caption);
    }
  }
  const answer = answers.join("\n").trim().slice(0, 24_000);
  if (!answer && !results.length) throw invalidOutput();
  return { answer, results };
}

export async function codexSearch(model, options, auth, signal) {
  const headers = new Headers(auth.headers);
  const token = headers.get("authorization")?.slice("Bearer ".length);
  if (!token) throw new SearchError(401, "Host Codex login unavailable.");
  headers.set("Accept", "text/event-stream");
  headers.set("Content-Type", "application/json");
  headers.set("OpenAI-Beta", "responses=experimental");
  headers.set("Originator", "pi");
  const instructions = [
    "Search the web and return a concise answer grounded in the web results, with source citations.",
    `Prefer around ${options.numResults} distinct sources.`,
    options.recencyFilter && `Prefer sources from the past ${RECENCY[options.recencyFilter]}.`,
    options.allowed.length && `Only cite sources from: ${options.allowed.join(", ")}.`,
    options.blocked.length && `Do not cite sources from: ${options.blocked.join(", ")}.`,
  ].filter(Boolean).join(" ");
  try {
    const response = await fetch(ENDPOINT, { method: "POST", headers, redirect: "error", signal,
      body: JSON.stringify({ model: model.id, instructions,
        input: [{ role: "user", content: [{ type: "input_text", text: options.query }] }],
        tools: [{ type: "web_search", ...(options.allowed.length ? { filters: { allowed_domains: options.allowed } } : {}) }],
        include: ["web_search_call.action.sources"], store: false, stream: true, tool_choice: "required", parallel_tool_calls: true }) });
    if (!response.ok) {
      await response.body?.cancel();
      if (response.status === 429) throw new SearchError(429, "Codex usage limit reached.", true);
      if ([401, 403].includes(response.status)) throw new SearchError(response.status, "Host Codex search authorization failed.");
      throw new SearchError(502, "Codex hosted web search request failed.");
    }
    return resultView(await responseOutput(response), options, token);
  } catch (error) {
    signal.throwIfAborted();
    if (error instanceof SearchError) throw error;
    throw new SearchError(502, "Codex hosted web search response could not be read.");
  }
}
