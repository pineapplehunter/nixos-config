import assert from "node:assert/strict";
import { once } from "node:events";
import { mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { request } from "node:http";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { pathToFileURL } from "node:url";
import { SEARCH_BODY_LIMIT } from "./codex_search.mts";

const model = (id) => ({ id, api: "openai-codex-responses", name: id });
const token = (account) =>
  `fixture.${Buffer.from(
    JSON.stringify({
      "https://api.openai.com/auth": {
        chatgpt_account_id: `fixture-${account}`,
      },
    }),
  ).toString("base64url")}.invalid-signature`;
const sse = (...events) =>
  new Response(
    events
      .map((event) => `event: ${event.type}\r\ndata: ${JSON.stringify(event)}\r\n\r\n`)
      .join(""),
    { headers: { "Content-Type": "text/event-stream" } },
  );

function fixtureResponse(account) {
  const citation = (url, title) => ({
    type: "url_citation",
    url,
    title,
    start_index: 0,
    end_index: 10,
  });
  return sse({
    type: "response.completed",
    response: {
      status: "completed",
      output: [
        {
          type: "web_search_call",
          status: "completed",
          action: {
            type: "search",
            sources: [
              { type: "url", url: "https://example.org/source" },
              { type: "url", url: "https://example.org/other" },
            ],
          },
        },
        {
          type: "message",
          role: "assistant",
          content: [
            {
              type: "output_text",
              text: `Cited answer. ${token(account)}`,
              annotations: [
                citation("https://example.org/source?utm_source=openai", "Example"),
                citation("https://banned.example.org/not-allowed", "Blocked"),
                citation("file:///secret", "Not a web URL"),
                citation("https://unrelated.example.net", "Not in the allowed list"),
              ],
            },
          ],
        },
      ],
    },
  });
}

async function unixFixture(t) {
  const dir = await mkdtemp(join(tmpdir(), "pi-codex-search-"));
  t.after(() => rm(dir, { recursive: true, force: true }));
  // Mirror Nix import substitution with stubs; never create ModelRuntime or image clients.
  const content = (await readFile(new URL("./codex_host.mts", import.meta.url), "utf8"))
    .replace(
      "@PI_RUNTIME@",
      "data:text/javascript,export%20const%20ModelRuntime%3Dnull%2CVERSION%3D%271.5.2%27",
    )
    .replace(
      "./codex_image_host.mts",
      "data:text/javascript,export%20const%20createImageHandler%3Dnull%2CIMAGE_BODY_LIMIT%3D0%2CimageAuth%3Dnull",
    )
    .replace("./codex_search.mts", new URL("./codex_search.mts", import.meta.url).href)
    .replace("./codex_protocol.mts", new URL("./codex_protocol.mts", import.meta.url).href);
  const script = join(dir, "broker.mts");
  await writeFile(script, content);
  const { broker } = await import(pathToFileURL(script).href);
  const settings = { personal: 10, work: 20, workReady: true, response: fixtureResponse };
  const runtimes = Object.fromEntries(
    ["personal", "work"].map((account) => [
      account,
      {
        account,
        getModels: () => [model("gpt-6.1"), model("gpt-6-luna")],
        checkAuth: async () =>
          account === "work" && !settings.workReady ? undefined : { type: "oauth" },
        getAuth: async () => ({ auth: { apiKey: token(account) } }),
      },
    ]),
  );
  const upstreamCalls = [];
  t.mock.method(globalThis, "fetch", async (url, init) => {
    // Do not make a real request even if the destination is wrong.
    assert.equal(url, "https://chatgpt.com/backend-api/codex/responses");
    assert.equal(init.redirect, "error");
    assert.equal(init.headers.has("X-Untrusted-Header"), false);
    const account = init.headers.get("ChatGPT-Account-Id").slice("fixture-".length);
    assert.equal(init.headers.get("Authorization"), `Bearer ${token(account)}`);
    const body = JSON.parse(init.body);
    assert.equal(body.stream, true);
    assert.equal(body.store, false);
    assert.equal(body.tools[0].type, "web_search");
    upstreamCalls.push({ account, body });
    return settings.response(account, init);
  });
  const readUsage = async ({ account }) => ({
    payload: {
      rate_limit: {
        primary_window: {
          limit_window_seconds: account === "personal" ? 18_000 : 604_800,
          used_percent: settings[account],
        },
      },
    },
  });
  const socketPath = join(dir, "broker.sock");
  const server = broker(runtimes, { readUsage }).listen(socketPath);
  await once(server, "listening");
  t.after(() => new Promise((resolve) => server.close(resolve)));
  const send = (params, signal) =>
    new Promise((resolve, reject) => {
      const body = JSON.stringify({ route: "auto", query: "Example query", ...params });
      const req = request(
        {
          socketPath,
          path: "/v1/search",
          method: "POST",
          signal,
          headers: {
            "Content-Length": Buffer.byteLength(body),
            "X-Untrusted-Header": "must not be forwarded",
          },
        },
        async (res) => {
          try {
            const chunks = [];
            for await (const chunk of res) chunks.push(chunk);
            resolve([res.statusCode, JSON.parse(Buffer.concat(chunks))]);
          } catch (error) {
            reject(error);
          }
        },
      );
      req.on("error", reject);
      req.end(body);
    });
  return { settings, send, upstreamCalls };
}

test("search uses catalog model, structured filters, and normalized public SSE citations", async (t) => {
  const { send, upstreamCalls } = await unixFixture(t);
  const [status, result] = await send({
    numResults: 2,
    recencyFilter: "day",
    domainFilter: ["example.org", "-banned.example.org"],
  });
  assert.equal(status, 200);
  assert.equal(result.account, "personal");
  assert.equal(result.answer, "Cited answer. [redacted]");
  assert.deepEqual(result.results, [
    {
      title: "Example",
      url: "https://example.org/source",
      snippet: "Cited answer. [redacted]",
      snippetSource: "generated",
    },
    { title: "https://example.org/other", url: "https://example.org/other", snippet: "" },
  ]);
  const { body } = upstreamCalls[0];
  assert.equal(body.model, "gpt-6-luna");
  assert.deepEqual(body.tools[0].filters, { allowed_domains: ["example.org"] });
  assert.match(body.instructions, /past 24 hours/);
  assert.deepEqual(body.input[0].content, [{ type: "input_text", text: "Example query" }]);
});

test("Auto protects the reserve and only fails over to Work on Personal quota rejection", async (t) => {
  const { send, settings, upstreamCalls } = await unixFixture(t);
  settings.personal = 85;
  assert.equal((await send({ model: "gpt-6.1" }))[1].account, "work");
  assert.equal(upstreamCalls[0].body.model, "gpt-6.1");
  settings.workReady = false;
  assert.equal((await send())[0], 429);
  assert.equal(upstreamCalls.length, 1);
  assert.equal((await send({ route: "personal" }))[1].account, "personal");
  settings.workReady = true;
  settings.personal = 10;
  settings.response = (account) =>
    account === "personal"
      ? sse({
          type: "response.failed",
          response: { error: { code: "usage_limit_reached", message: "hidden upstream detail" } },
        })
      : fixtureResponse(account);
  assert.equal((await send())[1].account, "work");
  assert.deepEqual(
    upstreamCalls.map(({ account }) => account),
    ["work", "personal", "personal", "work"],
  );
  assert.equal((await send({ route: "personal" }))[0], 429);
  assert.equal(upstreamCalls.at(-1).account, "personal");
});

test("rejects arbitrary transport, extra fields, model, and body before contacting upstream", async (t) => {
  const { send, upstreamCalls } = await unixFixture(t);
  for (const fields of [
    { baseUrl: "https://example.org" },
    { headers: {} },
    { account: "work" },
    { tools: [] },
    { domainFilter: ["https://example.org"] },
    { numResults: 21 },
    { query: "x".repeat(SEARCH_BODY_LIMIT) },
    { model: "non-catalog-model" },
    { route: "unrecognized" },
  ]) {
    assert.equal((await send(fields))[0], 400);
  }
  assert.deepEqual(upstreamCalls, []);
});

test("Auto does not retry a quota error after upstream output", async (t) => {
  const { send, settings, upstreamCalls } = await unixFixture(t);
  settings.response = () =>
    sse(
      { type: "response.output_text.delta", delta: "Partial answer" },
      { type: "response.failed", response: { error: { code: "usage_limit_reached" } } },
    );
  assert.deepEqual(await send(), [429, { error: "Codex usage limit reached." }]);
  assert.deepEqual(
    upstreamCalls.map(({ account }) => account),
    ["personal"],
  );
});

test("no fallback on malformed streams or authorization errors, and upstream bodies are hidden", async (t) => {
  const { send, settings, upstreamCalls } = await unixFixture(t);
  settings.response = () =>
    sse({
      type: "response.output_item.done",
      item: { type: "web_search_call", status: "completed" },
    });
  assert.equal((await send())[0], 502);
  settings.response = () => new Response("sensitive error body", { status: 403 });
  assert.deepEqual(await send(), [403, { error: "Host Codex search authorization failed." }]);
  assert.deepEqual(
    upstreamCalls.map(({ account }) => account),
    ["personal", "personal"],
  );
});

test("disconnect aborts the upstream search", { timeout: 2_000 }, async (t) => {
  const { send, settings } = await unixFixture(t);
  const controller = new AbortController();
  const { promise: aborted, resolve } = Promise.withResolvers();
  settings.response = (_account, { signal }) =>
    new Promise((_done, reject) => {
      signal.addEventListener(
        "abort",
        () => {
          resolve();
          reject(signal.reason);
        },
        { once: true },
      );
      controller.abort();
    });
  await assert.rejects(send({ route: "work" }, controller.signal), { name: "AbortError" });
  await aborted;
});
