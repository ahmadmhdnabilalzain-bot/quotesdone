// DRILLS D1, D2, D12 AND THE EMPTY-ANSWER FAULTS AT THE CLIENT: _shared/llm.ts, aiReply and openrouter_down
// (it_engineer, 3 Nov 2026). docs/release/qualification_matrix.md §5.1 listed D1 (OpenRouter down), D2 (model slow)
// and D12 (secret rotation mid-traffic) as GAP. Here ai_gateway is a stub that answers with the envelopes the real
// gateway writes (ai_gateway/index.ts: 502 all_models_failed / gateway_deadline / empty_completion, 503 circuit_open,
// 400 review_needs_counterpart, 200 rate_limited) and the ones the platform writes in front of it (a 503 or 502 with no
// worker behind it, a 429, a refused connection). The real llm.ts, the real aiReply through think.ts defaultDeps and
// the real isOpenRouterDown read them. ai_gateway/drill_provider_faults.test.ts drills the gateway itself.
//
// Asserted for every fault: llm.ts never throws and NAMES the failure; isOpenRouterDown says outage only when no model
// answered (founder_instruction 1339), so a code-written reply is licensed only then; the agent_runs row the it_engineer
// watch reads is written where llm.ts is the one that knows; and the next call, fault gone, is answered (no latch).
//
// THE KNOWN-GOOD CONTROL. 'D1 control' proves a stubbed gateway that answers produces a reply and outage:false, and
// the outage tests prove outage:true is reachable, so neither verdict can come from a stub that is never called or a
// classifier stuck on one answer. Every test also counts the gateway calls it expected.
//   cd /home/user/quotesdone && DENO_NO_PACKAGE_JSON=1 deno test --no-lock --node-modules-dir=auto \
//     --allow-env=SUPABASE_URL,SUPABASE_SERVICE_ROLE_KEY,RESEND_INBOUND_NO_SERVE --allow-net=127.0.0.1 \
//     --allow-read=/home/user/quotesdone supabase/functions/_shared/drill_model_faults.test.ts
import { assert, assertEquals, assertStringIncludes } from 'jsr:@std/assert@1';
import { isOpenRouterDown, modelOrOutage } from './openrouter_down.ts';
import { aiReply, MIN_CALL_MS, PER_CALL_MS } from './ai_reply.ts';
import { defaultDeps } from './think.ts';

Deno.env.set('SUPABASE_URL', 'https://zz-demo.example.invalid');
Deno.env.set('SUPABASE_SERVICE_ROLE_KEY', 'zz-demo-key');
const { makeLlm, makeLlmRich } = await import('./llm.ts');

const J = (o: unknown, status = 200, headers: Record<string, string> = {}) =>
  new Response(JSON.stringify(o), { status, headers: { 'content-type': 'application/json', ...headers } });
const SERVED = { 'x-served-by': 'supabase-edge-runtime' };   // the edge runtime ran the gateway's own code

type Gateway = (body: Record<string, unknown>, signal: AbortSignal | null, n: number) => Response | Promise<Response>;
const state = { cred: 'zz-cred-old-0123456789abcdef0123', bodies: [] as Record<string, unknown>[], runs: [] as Record<string, unknown>[] };
async function withGateway<T>(gateway: Gateway, run: () => Promise<T>): Promise<T> {
  const real = globalThis.fetch;
  state.bodies.length = 0; state.runs.length = 0;
  globalThis.fetch = (async (input: RequestInfo | URL, init?: RequestInit) => {
    const req = input instanceof Request ? input : new Request(String(input), init);
    const u = new URL(req.url);
    if (u.pathname === '/functions/v1/ai_gateway') {
      const body = JSON.parse(await req.clone().text());
      state.bodies.push(body);
      return await gateway(body, init?.signal ?? req.signal, state.bodies.length);
    }
    if (u.pathname === '/rest/v1/app_secrets') {
      const key = (u.searchParams.get('key') || '').replace(/^eq\./, '');
      return J({ value: key.startsWith('cred_fn_') ? state.cred : 'zz-legacy-0123456789abcdef0123' });
    }
    if (u.pathname === '/rest/v1/agent_runs' && req.method === 'POST') { state.runs.push(JSON.parse(await req.clone().text())); return J([], 201); }
    return J([]);   // agent_runs reads (llm.ts's 30-minute dedupe): nothing yet, so every signal is written
  }) as typeof fetch;
  try { return await run(); } finally { globalThis.fetch = real; }
}
const rich = (timeoutMs = 25000) => makeLlmRich([], { fn: 'support_reply', taskClass: 'conversation_reply', timeoutMs })('ZZ DEMO rules', 'ZZ DEMO question');
const signals = () => state.runs.filter((r) => r.agent === 'llm_gateway_auth').map((r) => (r.counts as Record<string, unknown>).signal);

const OK_TEXT = 'The reveal fee is 3% of the quotation you choose; no card fee is added and no VAT is charged on it.';
const generated = (content: string, extra: Record<string, unknown> = {}) =>
  J({ ok: true, used_llm: true, outcome: 'generated', content, model: 'anthropic/claude-sonnet-5.5', finish_reason: 'stop', truncated: false, cost_usd: 0.0004, ...extra }, 200, SERVED);
const COMPANY = 'REVEAL FEE: the customer pays 3% of the selected quotation value. No card fee is added and no VAT is charged on it.';
// deno-lint-ignore no-explicit-any
const fakeAdmin: any = { rpc: (fn: string) => Promise.resolve({ data: fn === 'fn_company_context' ? { block: COMPANY } : null, error: null }) };
const reply = (extra: Record<string, unknown> = {}) => aiReply(defaultDeps(fakeAdmin, 'support_reply'),
  { seat: 'customer_support', channel: 'email', audience: 'customer', lang: 'en', message: 'ZZ DEMO what is the reveal fee?', ...extra });

// ==== D1 — OPENROUTER DOWN, AS THE CLIENT SEES IT ==================================================================
Deno.test('D1 control: a gateway that answers gives the reply, outage false, one call', async () => {
  const r = await withGateway(() => generated(JSON.stringify({ answer: OK_TEXT })), () => reply());
  assertEquals([r.reply, r.outage ?? false], [OK_TEXT, false]);
  assertEquals(state.bodies.length, 1);
  assertEquals(state.bodies[0].fn, 'support_reply');
});

const DOWN: [string, Gateway, number, string][] = [
  ['the gateway walked its ladder and every model failed (502)', () => J({ ok: false, error: 'all_models_failed', detail: 'Provider returned error' }, 502, SERVED), 1, 'gateway_http_502:all_models_failed'],
  ['every route open-circuit (503 circuit_open)', () => J({ ok: false, used_llm: false, outcome: 'circuit_open', error: 'every model route for this task class is open-circuit', cost_usd: 0 }, 503, SERVED), 1, 'circuit_open'],
  ['the gateway itself failed (500)', () => J({ ok: false, error: 'route_failed', detail: 'no route' }, 500, SERVED), 1, 'gateway_http_500:route_failed'],
  ['no worker served the call, twice (503, no envelope)', () => J({ code: 'WORKER_LIMIT', message: 'no worker' }, 503), 2, 'gateway_http_503'],
  ['connection refused', () => { throw new TypeError('error sending request for url (https://zz-demo.example.invalid/functions/v1/ai_gateway): Connection refused (os error 111)'); }, 1, 'client_error: TypeError: error sending request'],
];
for (const [name, gw, calls, error] of DOWN) {
  Deno.test(`D1 ${name}: llm.ts names it, never throws, and it reads as an outage`, async () => {
    const r = await withGateway(gw, () => rich());
    assertEquals(r.content, null);
    assertStringIncludes(String(r.error), error);
    assertEquals(state.bodies.length, calls, 'one retry only for a call no worker served, never for an envelope the gateway wrote');
    assert(isOpenRouterDown(r.error, r.http_status), String(r.error));
    assertEquals(await withGateway(gw, () => makeLlm([], { fn: 'support_reply' })('s', 'i')), null, 'the string contract: null, never a throw');
    const said = await withGateway(gw, () => reply());
    assertEquals([said.reply, said.outage], ['', true]);
    assertEquals(modelOrOutage(said, 'CODE-WRITTEN NOTICE'), 'CODE-WRITTEN NOTICE');
  });
}

Deno.test('D1 visible: a 5xx with no JSON body leaves the gateway_error row llm.ts owns', async () => {
  await withGateway(() => new Response('upstream connect error', { status: 500, headers: SERVED }), () => rich());
  assertEquals(signals(), ['gateway_error']);
});

Deno.test('D1 recovery: llm.ts holds no latch; the call after an outage is answered', async () => {
  const r = await withGateway((_b, _s, n) => n <= 2 ? J({ ok: false, error: 'all_models_failed' }, 502, SERVED) : generated(JSON.stringify({ answer: OK_TEXT })),
    async () => [await rich(), await rich(), await rich()]);
  assertEquals(r.map((x) => x.error === null), [false, false, true]);
  assertEquals(r[2].content, JSON.stringify({ answer: OK_TEXT }));
});

// ==== D2 — MODEL SLOW =============================================================================================
const hangs: Gateway = (_b, signal) => new Promise<Response>((_res, rej) => {
  signal?.addEventListener('abort', () => rej(new DOMException('The signal has been aborted', 'AbortError')), { once: true });
});
Deno.test('D2 a gateway that never answers: the client aborts at timeoutMs + 5000, names it, and it is an outage', async () => {
  const t0 = Date.now();
  const r = await withGateway(hangs, () => rich(1));
  const ms = Date.now() - t0;
  assertEquals(r.error, 'client_timeout_5001ms');
  assert(ms >= 5000 && ms < 7000, 'no hang: ' + ms + ' ms');
  assertEquals(state.bodies[0].client_timeout_ms, 5001, 'the gateway is told the real patience, so its wall lands inside it');
  assert(isOpenRouterDown(r.error, r.http_status));
});

Deno.test('D2 the turn clock: no call starts with under MIN_CALL_MS left, and none is given more than PER_CALL_MS', async () => {
  const late = await withGateway(() => generated(JSON.stringify({ answer: OK_TEXT })), () => reply({ deadline: Date.now() + MIN_CALL_MS - 500 }));
  assertEquals([late.reply, late.outage], ['', true]);
  assertEquals(state.bodies.length, 0, 'out of time before the first call: nothing is asked, and only then a held notice is licensed');
  await withGateway(() => generated(JSON.stringify({ answer: OK_TEXT })), () => reply({ deadline: Date.now() + 120_000 }));
  assertEquals(state.bodies[0].client_timeout_ms, PER_CALL_MS + 5000, 'a far deadline still caps each call at PER_CALL_MS (+ llm.ts\'s 5 s margin)');
});

// ==== EMPTY AND UNEXPECTED ANSWERS — THE MODEL IS UP ================================================================
Deno.test('format: the gateway\'s empty_completion (the provider answered nothing) is not an outage; no code text', async () => {
  const gw: Gateway = () => J({ ok: false, error: 'empty_completion', detail: 'empty completion: finish_reason=stop completion_tokens=0', ladder: ['m'] }, 502, SERVED);
  const r = await withGateway(gw, () => rich());
  assertEquals(r.content, null);
  assertStringIncludes(String(r.error), 'empty_completion');
  assert(!isOpenRouterDown(r.error, r.http_status), String(r.error));
  const said = await withGateway(gw, () => reply());
  assertEquals([said.reply, said.outage], ['', false]);
  assertEquals(modelOrOutage(said, 'CODE-WRITTEN NOTICE'), '');
});

Deno.test('format: an HTML page with 200 in front of the gateway is no_body, not an outage', async () => {
  const r = await withGateway(() => new Response('<html>ok</html>', { status: 200, headers: { 'content-type': 'text/html' } }), () => rich());
  assertEquals([r.content, r.error], [null, 'no_body']);
  assert(!isOpenRouterDown(r.error, r.http_status));
});

Deno.test('format: a truncated answer gets exactly one controlled repair, then fails closed with null', async () => {
  const cut = () => generated('{"answer":"The reveal fee is 3% of the quo', { finish_reason: 'length', truncated: true });
  const out = await withGateway(cut, () => makeLlm([], { fn: 'support_reply' })('ZZ DEMO rules', 'q'));
  assertEquals(out, null);
  assertEquals(state.bodies.length, 2);
  assertStringIncludes(String(state.bodies[1].sys), 'cut off by the output limit');
  assertEquals(signals(), ['output_truncated', 'output_truncated_failed_closed']);
  // control: the repair that comes back whole is used
  const fixed = await withGateway((_b, _s, n) => n === 1 ? cut() : generated('Complete.'), () => makeLlm([], { fn: 'support_reply' })('s', 'q'));
  assertEquals(fixed, 'Complete.');
});

// ==== 4xx — AN ANSWER, NEVER AN OUTAGE ==============================================================================
Deno.test('4xx: a policy refusal, a platform 429 and a 400 whose text says "timeout" are not outages', async () => {
  const cases: [Gateway, number][] = [
    [() => J({ ok: false, used_llm: false, outcome: 'review_needs_counterpart', error: 'name counterpart_model', cost_usd: 0 }, 400, SERVED), 400],
    [() => new Response('Too Many Requests', { status: 429 }), 429],
    [() => J({ ok: false, error: 'upstream request timeout' }, 400, SERVED), 400],
  ];
  for (const [gw, status] of cases) {
    const r = await withGateway(gw, () => rich());
    assertEquals([r.content, r.http_status], [null, status]);
    assert(!isOpenRouterDown(r.error, r.http_status), String(r.error));
    const said = await withGateway(gw, () => reply());
    assertEquals(said.outage, false, String(r.error));
  }
});

Deno.test('4xx: the sender\'s spent rate bucket stops the reply with one call, rateLimited, not an outage', async () => {
  const said = await withGateway(() => J({ ok: true, used_llm: false, outcome: 'rate_limited', detail: { allowed: false } }, 200, SERVED), () => reply({ rateKey: 'wa:+971500000042' }));
  assertEquals([said.reply, said.outage, said.rateLimited], ['', false, true]);
  assertEquals(state.bodies.length, 1);
});

// ==== D12 — SECRET ROTATION MID-TRAFFIC =============================================================================
Deno.test('D12 the credential is read at call time: a rotation between calls is presented on the very next call', async () => {
  state.cred = 'zz-cred-old-0123456789abcdef0123';
  const seen = await withGateway(() => generated('ok'), async () => {
    await rich();
    state.cred = 'zz-cred-new-fedcba9876543210fedc';   // fn_it_credential_rotate writes app_secrets
    await rich();
    return state.bodies.map((b) => b.__secret);
  });
  assertEquals(seen, ['zz-cred-old-0123456789abcdef0123', 'zz-cred-new-fedcba9876543210fedc'], 'no cache, no restart');
  state.cred = 'zz-cred-old-0123456789abcdef0123';
});

Deno.test('D12 a 401/403 is named gateway_forbidden, leaves its row, is not an outage, and the next call recovers', async () => {
  for (const status of [401, 403]) {
    const r = await withGateway((_b, _s, n) => n === 1 ? J({ ok: false, error: 'forbidden' }, status, SERVED) : generated('ok'), async () => [await rich(), await rich()]);
    assertEquals([r[0].error, r[0].http_status], ['gateway_forbidden', status]);
    assertEquals(state.bodies.length, 2, 'a refused credential is not retried blind; the next call is answered');
    assert(!isOpenRouterDown(r[0].error, r[0].http_status));
    assertEquals(signals(), ['gateway_forbidden']);
    assertEquals(r[1].content, 'ok');
  }
});

Deno.test('D12 the verifier unreachable (503 credential_check_unavailable) is named and left as its own row', async () => {
  const r = await withGateway(() => J({ ok: false, error: 'credential_check_unavailable' }, 503, SERVED), () => rich());
  assertEquals([r.error, r.http_status], ['credential_check_unavailable', 503]);
  assertEquals(state.bodies.length, 1);
  assertEquals(signals(), ['verifier_unavailable']);
});
