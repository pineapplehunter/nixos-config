// Run by codex-host.nix against the packaged native SDK. No real account or network.
import assert from 'node:assert/strict';
import { once } from 'node:events';
import { zstdDecompressSync } from 'node:zlib';
import { request } from 'node:http';
import { test } from 'node:test';
import { broker } from './codex_host.mts';
import { stream, streamSimple, closeOpenAICodexWebSocketSessions } from '@PI_CODEX_API@';

const model = { id: 'fixture', name: 'fixture', provider: 'openai-codex', api: 'openai-codex-responses',
  baseUrl: 'https://chatgpt.com/backend-api', reasoning: true, input: ['text'], maxTokens: 128, contextWindow: 10000,
  cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 } };
const account = 'fixture-account';
const apiKey = `x.${Buffer.from(JSON.stringify({ 'https://api.openai.com/auth': { chatgpt_account_id: account } })).toString('base64')}.x`;
const runtime = { getModel: () => model, checkAuth: async () => ({ type: 'oauth' }),
  stream: (m, c, o) => stream(m, c, { ...o, apiKey }),
  streamSimple: (m, c, o) => streamSimple(m, c, { ...o, apiKey }) };
const sse = (...events) => () => new Response(events.map(e => `data: ${JSON.stringify(e)}\n\n`).join(''),
  { headers: { 'Content-Type': 'text/event-stream' } });
const http = (status, body) => () => Response.json(body, { status });
const incomplete = reason => sse({ type: 'response.incomplete', response: { status: 'incomplete', incomplete_details: { reason } } });
const item = { type: 'message', id: 'a', content: [] };
const refusal = 'Fixture refusal';

function chat(socketPath, options = {}, signal) {
  const body = JSON.stringify({ model: model.id, route: 'work', messages: [], ...options });
  return new Promise((resolve, reject) => {
    const req = request({ socketPath, signal, method: 'POST', path: '/v1/chat', headers: { 'X-Pi-Codex-Status-Events': '1', 'Content-Length': Buffer.byteLength(body) } }, async res => {
      try {
        const chunks = [];
        for await (const chunk of res) chunks.push(chunk);
        resolve(Buffer.concat(chunks).toString().trim().split('\n').map(line => JSON.parse(line)));
      } catch (err) { reject(err); }
    });
    req.on('error', reject).end(body);
  });
}

test('brokered chat versus native Pi: requests, streams, status, redaction, retries and cancellation', async t => {
  const socket = `./chat-${process.pid}.sock`;
  const server = broker({ work: runtime, personal: runtime }).listen(socket);
  await once(server, 'listening');
  t.after(() => new Promise(resolve => server.close(resolve)));
  const journal = t.mock.method(console, 'warn', () => {});
  let reply;
  t.mock.method(globalThis, 'fetch', async url => {
    assert.equal(String(url), 'https://chatgpt.com/backend-api/codex/responses');
    return reply();
  });
  for (const [name, fixture, expected] of [
    ['refusal', sse({type:'response.output_item.added',output_index:0,item},
      {type:'response.refusal.delta',output_index:0,delta:refusal},
      {type:'response.output_item.done',output_index:0,item:{...item,content:[{type:'refusal',refusal}]}},
      {type:'response.completed',response:{status:'completed'}})],
    ['incomplete: filter', incomplete('content_filter')],
    ['incomplete: redact raw reason too', incomplete(apiKey), 'Response incomplete: [redacted]'],
    ['incomplete: unspecified', incomplete()],
    ['incomplete: length', incomplete('max_output_tokens')],
    ['partial text then error', sse({type:'response.output_item.added',output_index:0,item},
      {type:'response.output_text.delta',output_index:0,delta:'Fixture partial'},
      {type:'error',error:{message:'Fixture rejection'}})],
    ['reasoning, tool call and usage', sse(
      {type:'response.created',response:{id:'resp_demo'}},
      {type:'response.output_item.added',output_index:0,item:{id:'r',type:'reasoning',summary:[]}},
      {type:'response.reasoning_summary_text.delta',output_index:0,delta:'Thinking'},
      {type:'response.output_item.done',output_index:0,item:{id:'r',type:'reasoning',summary:[{text:'Thinking'}]}},
      {type:'response.output_item.added',output_index:1,item:{type:'function_call',id:'f',call_id:'c',name:'echo',arguments:''}},
      {type:'response.function_call_arguments.delta',output_index:1,delta:'{"value":1}'},
      {type:'response.output_item.done',output_index:1,item:{type:'function_call',id:'f',call_id:'c',name:'echo',arguments:'{"value":1}'}},
      {type:'response.completed',response:{status:'completed',usage:{input_tokens:10,output_tokens:5,total_tokens:15,input_tokens_details:{cached_tokens:3}}}})],
    ['failed', sse({type:'response.failed',response:{error:{message:'Fixture rejection'}}})],
    ['HTTP rejection', http(403, {error:{message:'Fixture rejection'}})],
    ['HTTP quota', http(429, {error:{code:'usage_limit_reached',plan_type:'plus'}})],
    ['include provider code', http(400, {error:{code:'policy',message:'Fixture rejection'}}), 'policy: Fixture rejection'],
    ['redact credentials', sse({type:'error',message:`Fixture ${apiKey} ${account}`}), 'Codex error: Fixture [redacted] [redacted]'],
    ['hide unstructured event', sse({type:'error',diagnostics:'private-diagnostic'}), 'Codex work request failed.'],
    ['hide raw HTTP body', () => new Response('private-diagnostic',{status:400}), 'Codex work request rejected (HTTP 400).'],
  ]) {
    reply = fixture;
    const direct = runtime.streamSimple(model, {messages:[]}, {transport:'sse'});
    const nativeEvents = [];
    for await (const e of direct) nativeEvents.push([e.type, e.delta]);
    const native = await direct.result();
    const events = await chat(socket);
    assert.deepEqual(events.filter(e=>e.type!=='codex-status').map(e=>[e.type,e.delta]), nativeEvents, name);
    const last = events.at(-1);
    const actual = last.error ?? last.message;
    assert.equal(actual.stopReason, native.stopReason, name);
    assert.equal(actual.errorMessage, expected ?? native.errorMessage, name);
    assert.deepEqual(actual.content, native.content, name);
    assert.deepEqual(actual.usage, native.usage, name);
    assert.deepEqual(events.filter(e => e.type === 'codex-status').map(e => e.status), [fixture().status]);
    if (name === 'refusal') assert.ok(events.some(e=>e.type==='text_delta' && e.delta===refusal));
    assert.doesNotMatch(JSON.stringify(events), /private-diagnostic|fixture-account/);
    assert.ok(!JSON.stringify(events).includes(apiKey));
  }
  const bodies = [];
  let upstreamSignal;
  let onRequest;
  t.mock.method(globalThis, 'fetch', async (url, init) => {
    assert.equal(String(url), 'https://chatgpt.com/backend-api/codex/responses');
    const body = new Headers(init.headers).get('content-encoding') === 'zstd'
      ? zstdDecompressSync(init.body).toString() : init.body;
    bodies.push(JSON.parse(body));
    upstreamSignal = init.signal;
    onRequest?.();
    return reply();
  });
  const context = {messages:[{role:'user', content:'Hello',timestamp:0}]};
  for (const full of [false, true]) {
    reply = sse({type:'response.completed',response:{status:'completed'}});
    const options = {temperature:0.4, cacheRetention:'none', toolChoice:full?'required':'none', sessionId:'fixture',
      ...(full ? {textVerbosity:'low',reasoningSummary:'concise',reasoningEffort:'low',serviceTier:'default'} : {})};
    await runtime[full ? 'stream' : 'streamSimple'](model,context,{transport:'sse',...options}).result();
    await chat(socket,{full,...options,...context});
    assert.equal(bodies.length, full ? 4 : 2);
    assert.deepEqual(bodies.at(-1), bodies.at(-2), 'upstream request body');
  }
  let attempts = 0;
  reply = () => ++attempts === 1
    ? new Response('unavailable',{status:503,headers:{'retry-after-ms':'1'}})
    : sse({type:'response.completed',response:{status:'completed'}})();
  const retried = await chat(socket,{maxRetries:1});
  assert.deepEqual(retried.filter(e=>e.type==='codex-status').map(e=>e.status), [503,200]);
  assert.equal(retried.at(-1).type, 'done');

  const controller = new AbortController();
  const started = new Promise(resolve => { onRequest = resolve; });
  reply = () => new Promise((_, reject) => upstreamSignal.addEventListener('abort', () => reject(upstreamSignal.reason), {once:true}));
  const cancelled = chat(socket,{},controller.signal);
  await started;
  const aborted = once(upstreamSignal, 'abort', {signal:AbortSignal.timeout(2000)});
  controller.abort();
  await Promise.all([assert.rejects(cancelled, {name:'AbortError'}), aborted]);
  assert.doesNotMatch(JSON.stringify(journal.mock.calls.map(c=>c.arguments)), /private-diagnostic|Fixture|content_filter|fixture-account/);
});

test('native WebSocket continuation, replay, credential isolation and guarded SSE fallback', async t => {
  let login = apiKey;
  const rt = {...runtime, getAuth: async () => ({auth: {apiKey:login}})};
  const socket = `./ws-${process.pid}.sock`;
  const server = broker({work:rt,personal:rt}).listen(socket);
  await once(server,'listening');
  t.after(() => new Promise(resolve => server.close(resolve)));
  t.after(() => closeOpenAICodexWebSocketSessions());
  const sockets = [], requests = [];
  let failHandshake = false;
  let incompleteReason;
  class FixtureSocket extends EventTarget {
    readyState = 0;
    constructor(url, {headers}) {
      super();
      assert.equal(url,'wss://chatgpt.com/backend-api/codex/responses');
      assert.equal(new Headers(headers).get('authorization'), 'Bearer '+login);
      sockets.push(this);
      setImmediate(() => {
        this.readyState = failHandshake ? 3 : 1;
        this.dispatchEvent(new Event(failHandshake ? 'error' : 'open'));
      });
    }
    close() { this.readyState = 3; this.dispatchEvent(new Event('close')); }
    send(raw) {
      requests.push(JSON.parse(raw));
      const response = {id:'resp_'+requests.length,status:incompleteReason?'incomplete':'completed',
        ...(incompleteReason ? {incomplete_details:{reason:incompleteReason}} : {})};
      setImmediate(() => {
        for (const type of ['response.created','response.'+response.status]) this.dispatchEvent(
          new MessageEvent('message',{data:JSON.stringify({type,response})}));
      });
    }
  }
  const saved = globalThis.WebSocket;
  globalThis.WebSocket = FixtureSocket;
  t.after(() => { globalThis.WebSocket = saved; });
  const fetches = t.mock.method(globalThis,'fetch', async (url, init) => {
    assert.equal(url,'https://chatgpt.com/backend-api/codex/responses');
    assert.equal(init.redirect,'error');
    return sse({type:'response.completed',response:{status:'completed'}})();
  });
  const user = content => ({role:'user',content,timestamp:0});
  const opts = {sessionId:'fixture_ws',transport:'auto',timeoutMs:1500,websocketConnectTimeoutMs:500};
  const first = (await chat(socket,{...opts,messages:[user('one')]})).at(-1);
  assert.equal(first.type,'done');
  const messages = [user('one'),first.message,user('two')];
  assert.equal((await chat(socket,{...opts,transport:'websocket-cached',messages})).at(-1).type,'done');
  assert.equal(sockets.length,1);
  assert.equal(requests[1].previous_response_id,'resp_1');
  assert.equal(requests[1].input.length,1);
  await chat(socket,{...opts,messages,disableContinuation:true});
  assert.equal(sockets.length,2);
  assert.equal(requests[2].previous_response_id,undefined);
  login += 'refreshed';
  await chat(socket,{...opts,messages});
  assert.equal(sockets.length,3);
  assert.equal(requests[3].previous_response_id,undefined);
  assert.equal(fetches.mock.callCount(),0);

  incompleteReason = login;
  const denied = await chat(socket,{...opts,transport:'websocket',messages});
  assert.equal(requests.at(-1).previous_response_id,undefined);
  assert.equal(denied.at(-1).error.errorMessage,'Response incomplete: [redacted]');
  assert.ok(!JSON.stringify(denied).includes(login));
  assert.equal(fetches.mock.callCount(),0);
  incompleteReason = undefined;
  failHandshake = true;
  const fallback = await chat(socket,{...opts,sessionId:'other',messages});
  assert.equal(fetches.mock.callCount(),1);
  assert.equal(fallback.at(-1).type,'done');
  assert.deepEqual(fallback.filter(e=>e.type==='codex-status').map(e=>e.status),[200]);
  assert.ok(!JSON.stringify(fallback).includes(login));
});
