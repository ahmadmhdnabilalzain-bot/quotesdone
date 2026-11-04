// DRILLS D1, D2, D12 AND THE EMPTY-ANSWER FAULTS, AGAINST THE REAL GATEWAY (it_engineer, 3 Nov 2026).
// docs/release/qualification_matrix.md §5.1 listed D1 (OpenRouter down), D2 (model slow) and D12 (secret rotation
// mid-traffic) as GAP. These load ai_gateway/index.ts's own Deno.serve handler (_shared/twilio_free_harness.ts: env,
// Deno.serve and the database replaced) and put a stub where https://openrouter.ai is. The CHAIN tests send the real
// _shared/llm.ts client and the real aiReply (through think.ts defaultDeps, the wiring every reply path uses) through
// that handler, so what is asserted is what a customer-facing seat would actually do: no network, no paid call.
//
// For each fault three things are asserted. SAFE: no code-written reply is licensed while the model is up
// (founder_instruction 1339: isOpenRouterDown / aiReply.outage), and nothing is cached or logged as a success that was
// not one. VISIBLE: the rows the it_engineer seat reads are written (fn_record_llm_attempt -> llm_attempt and the
// llm_route_health breaker, fn_llm_log -> ai_cost_log, observe -> agent_runs fn:ai_gateway). RECOVERY: the next call,
// with the fault gone, is answered with no manual step and no restart.
//
// THE KNOWN-GOOD CONTROLS. 'D1 control' proves the stub provider is reached and its answer comes back as a reply, and
// 'D1 ... outage' proves outage:true can be produced at all, so a green on "not an outage" cannot come from a harness
// that never reaches the gateway or a classifier that always says false (and the reverse).
//   cd /home/user/quotesdone && DENO_NO_PACKAGE_JSON=1 deno test --no-lock --node-modules-dir=auto \
//     --allow-env=SUPABASE_URL,SUPABASE_SERVICE_ROLE_KEY,RESEND_INBOUND_NO_SERVE --allow-net=127.0.0.1 \
//     --allow-read=/home/user/quotesdone supabase/functions/ai_gateway/drill_provider_faults.test.ts
import { assert, assertEquals, assertStringIncludes } from 'jsr:@std/assert@1';
import { invoke, loadFunction, type Stub } from '../_shared/twilio_free_harness.ts';
import { isOpenRouterDown, modelOrOutage } from '../_shared/openrouter_down.ts';
import { aiReply } from '../_shared/ai_reply.ts';
import { defaultDeps } from '../_shared/think.ts';

const J = (o: unknown, status = 200, headers: Record<string, string> = {}) =>
  new Response(JSON.stringify(o), { status, headers: { 'content-type': 'application/json', ...headers } });

// ---- the database the gateway sees -------------------------------------------------------------------------------
const MODEL = 'anthropic/claude-sonnet-5.5', FALLBACK = 'google/gemini-3.8-flash';
const ROUTE = { model: MODEL, fallback: FALLBACK, tier: 'mid', task_class: 'conversation_reply', use_llm: true, max_tokens: 900, why: 'policy: conversation_reply', cache: false, cache_ttl_min: 0 };
type DbCall = { path: string; rpc: string | null; method: string; body: Record<string, unknown> | null };
const db = {
  route: { ...ROUTE } as Record<string, unknown>,
  gate: (_m: string): Record<string, unknown> => ({ allowed: true, rule: 'registered_breaker_closed' }),
  accepted: new Set<string>(['zz-cred-old-0123456789abcdef0123']),
  cred: 'zz-cred-old-0123456789abcdef0123',      // app_secrets.cred_fn_support_reply, as llm.ts reads it
  onAuth: (_presented: string) => {},             // a side effect at the moment the gateway verifies (D12 mid-flight)
  verifierDown: false,
  calls: [] as DbCall[],
};
const stub: Stub = {
  handle: async (req, u) => {
    const rpc = u.pathname.match(/^\/rest\/v1\/rpc\/(.+)$/)?.[1] ?? null;
    const body = req.method === 'POST' ? await req.clone().json().catch(() => null) : null;
    db.calls.push({ path: u.pathname, rpc, method: req.method, body });
    if (rpc === 'fn_internal_auth') {
      if (db.verifierDown) return J({ code: '57P01', message: 'terminating connection due to administrator command' }, 503);
      const presented = String(body?.p_secret ?? '');
      db.onAuth(presented);
      const ok = db.accepted.has(presented);
      return J(ok ? { ok: true, context: 'fn.support_reply', credential_id: 7, legacy: false } : { ok: false });
    }
    if (rpc === 'fn_ai_route') return J(db.route);
    // aiReply's second rung names counterpart_model: a reviewer route of another family
    if (rpc === 'fn_ai_route_review_for') return J({ ...db.route, model: FALLBACK, fallback: 'openai/gpt-6-luna-pro' });
    if (rpc === 'fn_kernel_paid_provider_gate') return J(db.gate(String(body?.p_model ?? '')));
    if (rpc === 'fn_llm_cache_lookup') return J({ hit: false });
    if (rpc === 'fn_model_cost_usd') return J(0.0001);
    if (u.pathname === '/rest/v1/app_secrets') {
      const key = (u.searchParams.get('key') || '').replace(/^eq\./, '');
      const value = key.startsWith('cred_fn_') ? db.cred : 'zz-stub-secret-0123456789abcdef0123';
      return (req.headers.get('accept') || '').includes('vnd.pgrst.object') ? J({ value }) : J([{ value }]);
    }
    return undefined;
  },
};
const rpcs = (name: string) => db.calls.filter((c) => c.rpc === name).map((c) => c.body ?? {});
const runRows = () => db.calls.filter((c) => c.path === '/rest/v1/agent_runs').map((c) => c.body as Record<string, unknown>);

// ---- the provider -----------------------------------------------------------------------------------------------
type Provider = (body: Record<string, unknown>, signal: AbortSignal | null, n: number) => Response | Promise<Response>;
const OK_TEXT = 'The reveal fee is 3% of the quotation you choose; no card fee is added and no VAT is charged on it.';
const completion = (content: unknown, finish = 'stop', extra: Record<string, unknown> = {}) =>
  J({ id: 'gen-zz', object: 'chat.completion', choices: [{ index: 0, message: { role: 'assistant', content }, finish_reason: finish }], usage: { prompt_tokens: 1200, completion_tokens: 40, cost: 0.0004 }, ...extra });
const answers: Provider = () => completion(JSON.stringify({ answer: OK_TEXT }));
let provider: Provider = answers;
const providerCalls: { model: string; body: Record<string, unknown> }[] = [];
/** A provider that never answers until the caller aborts — the slow model of D2. */
const hangs: Provider = (_b, signal) => new Promise<Response>((_res, rej) => {
  if (!signal) return;                         // no signal: a hang the test itself would time out on
  signal.addEventListener('abort', () => rej(new DOMException('The signal has been aborted', 'AbortError')), { once: true });
});

const handler = await loadFunction('ai_gateway', () => import('./index.ts'));
const gatewayAnswers: { status: number; json: Record<string, unknown> | null }[] = [];
const viaHarness = globalThis.fetch;
globalThis.fetch = (async (input: RequestInfo | URL, init?: RequestInit) => {
  const req = input instanceof Request ? input : new Request(String(input), init);
  const u = new URL(req.url);
  if (u.hostname === 'openrouter.ai') {
    if (u.pathname === '/api/v1/models') return J({ data: [] });
    const body = JSON.parse(await req.clone().text());
    providerCalls.push({ model: String(body.model), body });
    return await provider(body, init?.signal ?? req.signal, providerCalls.length);
  }
  // _shared/llm.ts's hop: answered by the real handler, exactly as the edge runtime would.
  if (u.pathname === '/functions/v1/ai_gateway') {
    const out = await invoke(handler, stub, JSON.parse(await req.clone().text()));
    gatewayAnswers.push({ status: out.status, json: out.json });
    return J(out.json, out.status, { 'x-served-by': 'supabase-edge-runtime' });
  }
  return viaHarness(input, init);
}) as typeof fetch;
// Imported after the harness has replaced Deno.env: llm.ts fixes its gateway URL at import.
const { makeLlm, makeLlmRich } = await import('../_shared/llm.ts');

function reset(p: Provider = answers) {
  provider = p; providerCalls.length = 0; gatewayAnswers.length = 0; db.calls.length = 0;
  db.route = { ...ROUTE }; db.gate = () => ({ allowed: true, rule: 'registered_breaker_closed' });
  db.accepted = new Set(['zz-cred-old-0123456789abcdef0123']); db.cred = 'zz-cred-old-0123456789abcdef0123';
  db.onAuth = () => {}; db.verifierDown = false;
}
const BODY = { __secret: 'zz-cred-old-0123456789abcdef0123', fn: 'support_reply', task_class: 'conversation_reply', sys: 'ZZ DEMO rules', input: 'ZZ DEMO what is the reveal fee?', max: 300, client_timeout_ms: 30000 };
const direct = (over: Record<string, unknown> = {}) => invoke(handler, stub, { ...BODY, ...over });
/** The error string llm.ts builds from this gateway answer, read through the real client. */
const llmRich = (timeoutMs = 25000) => makeLlmRich([], { fn: 'support_reply', taskClass: 'conversation_reply', timeoutMs, json: true })('ZZ DEMO rules', 'ZZ DEMO what is the reveal fee?');
const COMPANY = 'REVEAL FEE: the customer pays 3% of the selected quotation value. No card fee is added and no VAT is charged on it.';
// deno-lint-ignore no-explicit-any
const fakeAdmin: any = { rpc: (fn: string) => Promise.resolve({ data: fn === 'fn_company_context' ? { block: COMPANY } : null, error: null }) };
const replyReq = { seat: 'customer_support' as const, channel: 'email', audience: 'customer' as const, lang: 'en' as const, message: 'ZZ DEMO what is the reveal fee?' };
const reply = (extra: Record<string, unknown> = {}) => aiReply(defaultDeps(fakeAdmin, 'support_reply'), { ...replyReq, ...extra });

// ==== D1 — OPENROUTER DOWN ======================================================================================
Deno.test('D1 control: a provider that answers is reached, logged ok, and its words are the reply', async () => {
  reset();
  const r = await direct();
  assertEquals(r.status, 200);
  assertEquals(r.json?.content, JSON.stringify({ answer: OK_TEXT }));
  assertEquals(providerCalls.length, 1, 'the stub provider must be reached, or every "not called" below proves nothing');
  assertEquals(rpcs('fn_record_llm_attempt').map((b) => (b.p as Record<string, unknown>).ok), [true]);
  assertEquals(rpcs('fn_llm_log').at(-1)?.p_ok, true);
  reset();
  const said = await reply();
  assertEquals([said.reply, said.outage ?? false], [OK_TEXT, false]);
  assertEquals(gatewayAnswers.length, 1, 'aiReply reached the real gateway through llm.ts');
});

for (const status of [500, 502, 503]) {
  Deno.test(`D1 OpenRouter HTTP ${status}: the ladder is walked, the failure is recorded, and the caller reads an outage`, async () => {
    reset(() => J({ error: { code: status, message: 'Provider returned error' } }, status));
    const r = await direct();
    assertEquals(r.status, 502);
    assertEquals(r.json?.error, 'all_models_failed');
    assertEquals(providerCalls.map((c) => c.model), [MODEL, FALLBACK], 'primary, then the fallback; never more than two paid calls');
    // visible: each attempt in the reliability ledger (it feeds llm_route_health), the request in ai_cost_log, the run row
    const att = rpcs('fn_record_llm_attempt').map((b) => b.p as Record<string, unknown>);
    assertEquals(att.map((a) => [a.model_route, a.ok]), [[MODEL, false], [FALLBACK, false]]);
    assertStringIncludes(String(att[0].err_excerpt), 'Provider returned error');
    const log = rpcs('fn_llm_log').at(-1)!;
    assertEquals(log.p_ok, false);
    assertStringIncludes(String(log.p_because), 'ALL MODELS FAILED');
    assertEquals(rpcs('fn_llm_cache_store').length, 0, 'nothing cached');
    assert(runRows().some((x) => x.agent === 'fn:ai_gateway' && x.status === 'error'), 'an agent_runs error row for the it_engineer watch');
    // the real client names it and the classifier calls it an outage
    reset(() => J({ error: { code: status } }, status));
    const c = await llmRich();
    assertEquals(c.content, null);
    assertStringIncludes(String(c.error), 'gateway_http_502');
    assert(isOpenRouterDown(c.error, c.http_status), String(c.error));
  });
}

Deno.test('D1 connection refused: fetch throws on every rung; the reply is empty and licensed as an outage', async () => {
  reset(() => { throw new TypeError('error sending request for url (https://openrouter.ai/api/v1/chat/completions): Connection refused (os error 111)'); });
  const r = await direct();
  assertEquals([r.status, r.json?.error], [502, 'all_models_failed']);
  assertEquals(providerCalls.length, 2);
  assertStringIncludes(String((rpcs('fn_record_llm_attempt')[0].p as Record<string, unknown>).err_excerpt), 'Connection refused');
  reset(provider);
  const said = await reply();
  assertEquals([said.reply, said.outage], ['', true]);
  assertEquals(modelOrOutage(said, 'CODE-WRITTEN NOTICE'), 'CODE-WRITTEN NOTICE', 'the one case the code-written fallback is licensed');
  assertEquals(providerCalls.length, 4, 'two rungs x two paid attempts, never more');
});

Deno.test('D1 every route open-circuit: no provider call, a HELD log row, outage; the circuit closing needs no manual step', async () => {
  reset();
  db.gate = (m) => ({ allowed: false, rule: 'route_open', reason: 'circuit open until 2026-11-03 12:05:00+00', model: m });
  const r = await direct();
  assertEquals([r.status, r.json?.outcome], [503, 'circuit_open']);
  assertEquals(providerCalls.length, 0, 'an open circuit is never called into');
  assertStringIncludes(String(rpcs('fn_llm_log').at(-1)?.p_because), 'HELD');
  const c = await llmRich();
  assertEquals([c.error, c.http_status, c.used_llm], ['circuit_open', 503, false]);
  assert(isOpenRouterDown(c.error, c.http_status));
  const held = await reply();
  assertEquals([held.reply, held.outage], ['', true]);
  // recovery: open_until passes, the kernel gate answers allowed, and the very next call reaches the provider
  db.gate = () => ({ allowed: true, rule: 'registered_breaker_closed' });
  db.calls.length = 0;
  const back = await reply();
  assertEquals([back.reply, back.outage ?? false], [OK_TEXT, false]);
  assertEquals(rpcs('fn_record_llm_attempt').map((b) => (b.p as Record<string, unknown>).ok), [true], 'the success the breaker closes on is recorded');
});

Deno.test('D1 recovery: after a provider outage the next call is answered with no restart and no manual step', async () => {
  reset(() => J({ error: { code: 503 } }, 503));
  assertEquals((await reply()).outage, true);
  provider = answers;
  const back = await reply();
  assertEquals([back.reply, back.outage ?? false], [OK_TEXT, false]);
});

// ==== D2 — MODEL SLOW ===========================================================================================
Deno.test('D2 the provider hangs: the gateway gives up inside the caller\'s declared patience and the client reads an outage', async () => {
  reset(hangs);
  const t0 = Date.now();
  // timeoutMs 4000: llm.ts aborts at 9000 ms and declares client_timeout_ms 9000, so the gateway's wall is 8000 ms
  const c = await llmRich(4000);
  const ms = Date.now() - t0;
  assertEquals(gatewayAnswers.at(-1)?.status, 502);
  assertEquals(gatewayAnswers.at(-1)?.json?.error, 'gateway_deadline', 'the gateway answered, the client did not have to abort');
  assert(ms < 9000, 'settled before the client\'s own abort at 9000 ms: ' + ms);
  assertEquals(providerCalls.length, 1, 'no second attempt starts with under 4 s of the wall left');
  assertStringIncludes(String(c.error), 'gateway_http_502');
  assert(isOpenRouterDown(c.error, c.http_status));
  assertStringIncludes(String(rpcs('fn_llm_log').at(-1)?.p_because), 'ALL MODELS FAILED');
});

Deno.test('D2 aiReply under a turn deadline: one slow call, no second one, settled in bounded time, outage', async () => {
  reset(hangs);
  const t0 = Date.now();
  const said = await reply({ deadline: t0 + 8_100 });
  const ms = Date.now() - t0;
  assertEquals([said.reply, said.outage], ['', true]);
  assertEquals(providerCalls.length, 1, 'MIN_CALL_MS: no call starts once under 8 s are left');
  assert(said.attempts.some((a) => a.startsWith('deadline')), said.attempts.join(' | '));
  // llm.ts declares timeoutMs + 5000 (its own documented margin), so the gateway's wall lands 2 s past the turn's deadline
  assert(ms < 8_100 + 5_000, 'bounded by the deadline plus llm.ts\'s 5 s client margin: ' + ms);
});

// ==== UNEXPECTED FORMAT AND EMPTY COMPLETIONS — THE MODEL IS UP ==================================================
const EMPTY_SHAPES: [string, Provider][] = [
  ['choices: []', () => J({ id: 'gen-zz', choices: [], usage: { prompt_tokens: 1200, completion_tokens: 0 } })],
  ["content ''", () => completion('')],
  ['content null', () => completion(null)],
  ["finish_reason 'length' with nothing written", () => completion('', 'length')],
  ['an HTML page served with 200', () => new Response('<html><body>Something went wrong</body></html>', { status: 200, headers: { 'content-type': 'text/html' } })],
];
for (const [name, p] of EMPTY_SHAPES) {
  Deno.test(`format: ${name} is an empty answer, not an outage, and is never cached or logged as a success`, async () => {
    reset(p);
    db.route = { ...ROUTE, cache_ttl_min: 60 };   // a cacheable class: an empty answer must still never be stored
    const r = await direct();
    assertEquals(r.status, 502);
    assertEquals(rpcs('fn_llm_cache_store').length, 0);
    assertEquals(rpcs('fn_llm_log').at(-1)?.p_ok, false);
    assert(rpcs('fn_record_llm_attempt').every((b) => (b.p as Record<string, unknown>).ok === false));
    const c = await llmRich();
    assertEquals(c.content, null);
    assert(!isOpenRouterDown(c.error, c.http_status), 'the provider answered with nothing; the model is up: ' + c.error);
    const said = await reply();
    assertEquals([said.reply, said.outage], ['', false]);
    assertEquals(modelOrOutage(said, 'CODE-WRITTEN NOTICE'), '', 'ruling 1339: no code-written reply while the model is up');
  });
}

Deno.test('format: one rung refused at the network and the other answering empty is still the model up', async () => {
  reset((_b, _s, n) => { if (n % 2 === 1) throw new TypeError('error sending request: connection reset'); return completion(''); });
  const c = await llmRich();
  assert(!isOpenRouterDown(c.error, c.http_status), String(c.error));
});

Deno.test('format: content that is not JSON when JSON was asked is an answer: no outage, no code text', async () => {
  reset(() => completion('Sorry {this is not the object'));
  const said = await reply();
  assertEquals([said.reply, said.outage], ['', false]);
  assert(providerCalls.length >= 2, 'the model was asked again, not replaced by code');
});

Deno.test('format: a truncated answer gets one controlled repair, then fails closed, and the fragment is never cached', async () => {
  reset(() => completion('{"answer":"The reveal fee is 3% of the quo', 'length'));
  db.route = { ...ROUTE, cache_ttl_min: 60 };
  const out = await makeLlm([], { fn: 'support_reply', taskClass: 'conversation_reply' })('ZZ DEMO rules', 'ZZ DEMO what is the reveal fee?');
  assertEquals(out, null);
  assertEquals(gatewayAnswers.length, 2, 'the first call and exactly one repair');
  assertEquals(gatewayAnswers.map((g) => g.json?.truncated), [true, true]);
  assertEquals(rpcs('fn_llm_cache_store').length, 0, 'a fragment cut at the token ceiling is never stored for replay');
  // control: a complete answer on the same cacheable class IS stored, so the zero above is not a harness that never stores
  reset();
  db.route = { ...ROUTE, cache_ttl_min: 60 };
  await direct();
  assertEquals(rpcs('fn_llm_cache_store').length, 1);
});

// ==== 4xx FROM THE GATEWAY — A POLICY ANSWER, NOT AN OUTAGE ======================================================
Deno.test('4xx: a review without its counterpart (400) and a spent rate bucket are answers, never outages', async () => {
  reset();
  const c = await makeLlmRich([], { fn: 'support_reply', taskClass: 'seat_deliberation_ceo' })('s', 'i');
  assertEquals(c.http_status, 400);
  assert(!isOpenRouterDown(c.error, c.http_status), String(c.error));
  assertEquals(providerCalls.length, 0);
  // the gateway's own rate limit for one sender
  const limitedStub: Stub = { handle: async (req, u) => (u.pathname === '/rest/v1/rpc/fn_rate_limit' ? J({ allowed: false, count: 21 }) : await stub.handle!(req, u)) };
  const r = await invoke(handler, limitedStub, { ...BODY, rate_key: 'wa:+971500000042' });
  assertEquals([r.status, r.json?.outcome], [200, 'rate_limited']);
  assertEquals(providerCalls.length, 0);
});

// ==== D12 — SECRET ROTATION MID-TRAFFIC ==========================================================================
const NEW = 'zz-cred-new-fedcba9876543210fedc';
Deno.test('D12 rotation between calls (fn_it_credential_rotate: the old stays valid through the overlap): no call fails', async () => {
  reset();
  assertEquals((await llmRich()).error, null);
  db.cred = NEW; db.accepted = new Set(['zz-cred-old-0123456789abcdef0123', NEW]);   // rotate: app_secrets moves, both valid
  const after = await llmRich();
  assertEquals(after.error, null);
  const presented = rpcs('fn_internal_auth').map((b) => b.p_secret);
  assertEquals(presented.at(-1), NEW, 'llm.ts reads cred_fn_<fn> at call time: the new secret on the very next call, no restart');
  db.accepted = new Set([NEW]);                                                     // the overlap ends, the old is retired
  assertEquals((await llmRich()).error, null);
});

Deno.test('D12 an old credential refused mid-flight fails that one call loudly, not as an outage; the next call recovers', async () => {
  reset();
  db.onAuth = () => { db.cred = NEW; db.accepted = new Set([NEW]); };   // rotated AND retired between read and verify
  const c = await llmRich();
  assertEquals([c.error, c.http_status], ['gateway_forbidden', 403]);
  assert(!isOpenRouterDown(c.error, c.http_status), 'a refused credential is ours to fix, not a licence for code text');
  assert(db.calls.some((x) => x.path === '/rest/v1/agent_runs' && (x.body as Record<string, unknown>)?.agent === 'llm_gateway_auth'),
    'llm.ts writes the gateway_forbidden agent_runs row the it_engineer watch reads');
  db.onAuth = () => {};
  assertEquals((await llmRich()).error, null, 'the next call presents the rotated secret and is answered');
});

Deno.test('D12 the credential verifier unreachable reaches the client as credential_check_unavailable, not as a refusal', async () => {
  reset();
  db.verifierDown = true;
  const c = await llmRich();
  assertEquals(providerCalls.length, 0);
  assertStringIncludes(String(c.error), 'credential_check_unavailable');
  assertEquals(c.http_status, 503);
  db.verifierDown = false;
  assertEquals((await llmRich()).error, null);
});
