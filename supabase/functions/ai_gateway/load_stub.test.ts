// THE LOAD-TEST STUB CAN NEVER ANSWER A REAL PERSON, AND NEVER CALLS THE PROVIDER (it_engineer, 11 Nov 2026, ruling 1622).
// _shared/load_stub.ts answers a chat turn with a canned completion after a realistic delay, so 100 concurrent chats can
// be measured for nothing. This file pins who gets it, against ai_gateway/index.ts's own handler
// (_shared/twilio_free_harness.ts: env, Deno.serve and the database replaced; a stub where https://openrouter.ai is):
//   - the stub needs ALL of: a PROVEN run tag, its open window opened by 'load_test', models_allowed=false, and no
//     subject or a fixture subject (pure table + the real handler);
//   - a real subject, or a fixture check that fails, is REFUSED with no provider call;
//   - THE CONTROL: the same body with no run tag reaches the stub provider, so "0 provider calls" below is the stub's
//     doing and not a harness that never reaches the provider.
//   cd <repo> && DENO_NO_PACKAGE_JSON=1 deno test --no-lock --node-modules-dir=none \
//     --allow-env=SUPABASE_URL,SUPABASE_SERVICE_ROLE_KEY,RESEND_INBOUND_NO_SERVE --allow-net=127.0.0.1 \
//     --allow-read=. supabase/functions/ai_gateway/load_stub.test.ts
import { assert, assertEquals, assertStringIncludes } from 'jsr:@std/assert@1';
import { invoke, loadFunction, type Stub } from '../_shared/twilio_free_harness.ts';
import { CANNED_TEXT, CANNED_TEXT_AR, DEFAULT_DELAY_MS, delayRange, isOpenLoadWindow, loadStubVerdict, subjectVerdictOf, type LoadWindow } from '../_shared/load_stub.ts';

const J = (o: unknown, status = 200) => new Response(JSON.stringify(o), { status, headers: { 'content-type': 'application/json' } });
const SOON = () => new Date(Date.now() + 3600_000).toISOString();
const LOAD_WIN = (over: Partial<NonNullable<LoadWindow>> = {}): LoadWindow =>
  ({ opened_by: 'load_test', models_allowed: false, ended_at: null, expires_at: SOON(), note: 'delay_ms=40-60', ...over });

// ==== the rule, clause by clause ===================================================================================
Deno.test('loadStubVerdict: every clause is required, and a real or unanswered subject is refused', () => {
  const now = Date.now();
  assertEquals(loadStubVerdict(null, LOAD_WIN(), null, 'none', now).mode, 'normal', 'no proven tag -> normal path');
  assertEquals(loadStubVerdict('zzload1', null, null, 'none', now).mode, 'normal', 'no window -> normal');
  assertEquals(loadStubVerdict('zzload1', LOAD_WIN(), new Error('down'), 'none', now).mode, 'normal', 'window read failed -> normal');
  assertEquals(loadStubVerdict('zzload1', LOAD_WIN({ opened_by: 'demo_factory.withRun' }), null, 'none', now).mode, 'normal', 'an e2e window is not a load window');
  assertEquals(loadStubVerdict('zzload1', LOAD_WIN({ models_allowed: true }), null, 'none', now).mode, 'normal', 'a paid window is never a load window');
  assertEquals(loadStubVerdict('zzload1', LOAD_WIN({ models_allowed: null }), null, 'none', now).mode, 'normal', 'only an explicit false');
  assertEquals(loadStubVerdict('zzload1', LOAD_WIN({ ended_at: new Date().toISOString() }), null, 'none', now).mode, 'normal', 'ended');
  assertEquals(loadStubVerdict('zzload1', LOAD_WIN({ expires_at: new Date(now - 1000).toISOString() }), null, 'none', now).mode, 'normal', 'expired');
  assertEquals(loadStubVerdict('zzload1', LOAD_WIN(), null, 'real', now).mode, 'refuse');
  assertEquals(loadStubVerdict('zzload1', LOAD_WIN(), null, 'unknown', now).mode, 'refuse');
  assertEquals(loadStubVerdict('zzload1', LOAD_WIN(), null, 'fixture', now).mode, 'stub');
  const v = loadStubVerdict('zzload1', LOAD_WIN(), null, 'none', now);
  assertEquals(v.mode, 'stub');
  assertEquals(v.mode === 'stub' && v.delay, [40, 60]);
  assert(isOpenLoadWindow(LOAD_WIN(), now));
  assertEquals(delayRange(null), DEFAULT_DELAY_MS);
  assertEquals(delayRange('delay_ms=900-100'), DEFAULT_DELAY_MS, 'an inverted range falls back to the default');
  assertEquals(delayRange('delay_ms=99999-99999'), [20000, 20000], 'clamped');
  assertEquals(subjectVerdictOf(false, null, null), 'none');
  assertEquals(subjectVerdictOf(true, { fixture: true }, null), 'fixture');
  assertEquals(subjectVerdictOf(true, { fixture: false }, null), 'real');
  assertEquals(subjectVerdictOf(true, null, null), 'unknown');
  assertEquals(subjectVerdictOf(true, { fixture: true }, new Error('x')), 'unknown');
});

// ==== the real handler ============================================================================================
const ROUTE = { model: 'anthropic/claude-sonnet-5.5', fallback: 'google/gemini-3.8-flash', tier: 'mid', task_class: 'conversation_reply',
  use_llm: true, max_tokens: 900, why: 'policy: conversation_reply', cache: false, cache_ttl_min: 0, stream: true };
const CRED = 'zz-cred-0123456789abcdef0123456789';
const db = { window: LOAD_WIN() as LoadWindow, fixture: null as unknown, fixtureErr: false, logs: [] as Record<string, unknown>[] };
const stub: Stub = {
  handle: async (req, u) => {
    const rpc = u.pathname.match(/^\/rest\/v1\/rpc\/(.+)$/)?.[1] ?? null;
    const body = req.method === 'POST' ? await req.clone().json().catch(() => null) : null;
    if (rpc === 'fn_internal_auth') return J(body?.p_secret === CRED ? { ok: true, context: 'fn.site_assistant', credential_id: 7, legacy: false } : { ok: false });
    if (rpc === 'fn_ai_route') return J(ROUTE);
    if (rpc === 'fn_kernel_paid_provider_gate') return J({ allowed: true, rule: 'registered_breaker_closed' });
    if (rpc === 'fn_llm_cache_lookup') return J({ hit: false });
    if (rpc === 'fn_model_cost_usd') return J(0.0001);
    if (rpc === 'fn_llm_log') { db.logs.push(body ?? {}); return J(null); }
    if (rpc === 'fn_ai_subject_is_fixture') return db.fixtureErr ? J({ code: '57014', message: 'canceling statement due to statement timeout' }, 500) : J(db.fixture);
    if (u.pathname === '/rest/v1/rehearsal_window') {
      const rows = db.window ? [db.window] : [];
      return (req.headers.get('accept') || '').includes('vnd.pgrst.object') ? (db.window ? J(db.window) : J({ code: 'PGRST116' }, 406)) : J(rows);
    }
    if (u.pathname === '/rest/v1/app_secrets') {
      const value = 'zz-stub-secret-0123456789abcdef0123';
      return (req.headers.get('accept') || '').includes('vnd.pgrst.object') ? J({ value }) : J([{ value }]);
    }
    return undefined;
  },
};

const providerCalls: Record<string, unknown>[] = [];
const handler = await loadFunction('ai_gateway', () => import('./index.ts'));
const viaHarness = globalThis.fetch;
globalThis.fetch = (async (input: RequestInfo | URL, init?: RequestInit) => {
  const req = input instanceof Request ? input : new Request(String(input), init);
  const u = new URL(req.url);
  if (u.hostname === 'openrouter.ai') {
    if (u.pathname === '/api/v1/models') return J({ data: [] });
    providerCalls.push(JSON.parse(await req.clone().text()));
    return J({ id: 'gen-zz', choices: [{ index: 0, message: { role: 'assistant', content: 'a provider answer' }, finish_reason: 'stop' }], usage: { prompt_tokens: 10, completion_tokens: 4, cost: 0.0001 } });
  }
  return viaHarness(input, init);
}) as typeof fetch;

const BODY = { __secret: CRED, fn: 'site_assistant', task_class: 'conversation_reply', sys: 'ZZ DEMO rules', input: 'ZZ DEMO how does it work?', max: 300, client_timeout_ms: 30000 };
const PROVEN = { authorization: 'Bearer stub-service-role', 'x-qd-e2e-run': 'zzload1' };
function reset(win: LoadWindow = LOAD_WIN()) { db.window = win; db.fixture = null; db.fixtureErr = false; db.logs.length = 0; providerCalls.length = 0; }

Deno.test('CONTROL: with no run tag the same request reaches the provider', async () => {
  reset();
  const r = await invoke(handler, stub, BODY);
  assertEquals(r.status, 200);
  assertEquals(providerCalls.length, 1, 'the stub provider must be reached here, or every "0 provider calls" below proves nothing');
  assert(r.json?.outcome !== 'load_stub');
});

Deno.test('a proven tag in an open load window gets the canned completion after the delay, with 0 provider calls', async () => {
  reset();
  const t0 = Date.now();
  const r = await invoke(handler, stub, BODY, PROVEN);
  assertEquals(r.status, 200);
  assertEquals(r.json?.outcome, 'load_stub');
  assertEquals(r.json?.content, CANNED_TEXT);
  assertEquals(r.json?.cost_usd, 0);
  assert(Date.now() - t0 >= 40, 'the realistic delay was held');
  assertEquals(providerCalls.length, 0);
  assertEquals(db.logs.length, 1, 'one log row, so the run is measured');
  assertEquals(db.logs[0].p_model, 'load_stub');
  assertStringIncludes(String(db.logs[0].p_because), 'no provider call was made');
  assert(!r.calls.some((c) => new URL(c.url).pathname.includes('fn_record_llm_attempt')), 'no breaker or attempt-ledger write');
});

Deno.test('a caller that asks for JSON gets a JSON object it can parse', async () => {
  reset();
  const r = await invoke(handler, stub, { ...BODY, response_format: { type: 'json_object' } }, PROVEN);
  assertEquals(r.json?.outcome, 'load_stub');
  assertEquals(JSON.parse(String(r.json?.content)).load_stub, true);
});

Deno.test('the run-tag header without its proof (a visitor typing it) never gets the stub and never reaches the provider', async () => {
  reset();
  const r = await invoke(handler, stub, BODY, { 'x-qd-e2e-run': 'zzload1' });   // bearer stays the harness's user JWT
  assertEquals(r.status, 503);
  assertEquals(r.json?.outcome, 'rehearsal_tag_unproven');
  assertEquals(providerCalls.length, 0);
});

Deno.test('a proven tag whose window is NOT a load window takes the normal path (no stub)', async () => {
  for (const w of [LOAD_WIN({ opened_by: 'demo_factory.withRun' }), LOAD_WIN({ models_allowed: true }), LOAD_WIN({ expires_at: new Date(Date.now() - 5).toISOString() }), null]) {
    reset(w);
    const r = await invoke(handler, stub, BODY, PROVEN);
    assert(r.json?.outcome !== 'load_stub', 'window ' + JSON.stringify(w) + ' must not stub');
    assert(!db.logs.some((l) => l.p_model === 'load_stub'));
  }
});

Deno.test('a load run that names a REAL subject is refused with no provider call', async () => {
  reset(); db.fixture = { fixture: false, why: 'a real customer' };
  const r = await invoke(handler, stub, { ...BODY, subject: { customer_id: '00000000-0000-4000-8000-000000000001' } }, PROVEN);
  assertEquals(r.status, 503);
  assertEquals(r.json?.outcome, 'load_stub_refused');
  assertEquals(providerCalls.length, 0);
});

Deno.test('a load run whose fixture check fails is refused, never stubbed or sent', async () => {
  reset(); db.fixtureErr = true;
  const r = await invoke(handler, stub, { ...BODY, subject: { email: 'qd-zzload1-c1@example.invalid' } }, PROVEN);
  assertEquals(r.json?.outcome, 'load_stub_refused');
  assertEquals(providerCalls.length, 0);
});

Deno.test('a load run with a FIXTURE subject is stubbed', async () => {
  reset(); db.fixture = { fixture: true, why: 'harness identity' };
  const r = await invoke(handler, stub, { ...BODY, subject: { email: 'qd-zzload1-c1@example.invalid' } }, PROVEN);
  assertEquals(r.json?.outcome, 'load_stub');
  assertEquals(providerCalls.length, 0);
});

Deno.test('a streamed load turn is the OpenRouter SSE shape: the canned words, then usage at cost 0, then [DONE]', async () => {
  reset();
  const res = await handler(new Request('https://fn.invalid/', { method: 'POST',
    headers: { 'content-type': 'application/json', ...PROVEN }, body: JSON.stringify({ ...BODY, stream: true }) }));
  assertStringIncludes(res.headers.get('content-type') || '', 'event-stream');
  assertEquals(res.headers.get('x-qd-model'), 'load_stub');
  const sse = await res.text();
  const datas = sse.split('\n').filter((l) => l.startsWith('data: ')).map((l) => l.slice(6));
  assertEquals(datas.at(-1), '[DONE]');
  const chunks = datas.slice(0, -1).map((d) => JSON.parse(d));
  assertEquals(chunks.map((c) => c.choices[0].delta.content ?? '').join(''), CANNED_TEXT);
  assertEquals(chunks.at(-1).usage.cost, 0);
  assertEquals(providerCalls.length, 0);
  await new Promise((r) => setTimeout(r, 30));   // let observe()'s background agent_runs write land on the stub
});

// IN THE CONVERSATION'S LANGUAGE (11 Nov 2026): the first run's English stub failed every Arabic conversation's language
// check (14 of 139 turns HTTP 503 after the whole ladder). A caller whose rules say "Reply in Arabic" gets the Arabic reply,
// streamed WHOLE: the stream split sentences on . ? ! only, so the Arabic reply's last sentence (ending ؟) was dropped.
Deno.test('a load turn whose rules ask for Arabic is answered in Arabic, every sentence streamed', async () => {
  reset();
  const sys = "You are QuotesDone's customer support.\n- Reply in Arabic in the customer's own register: mirror the dialect they write in.";
  const res = await handler(new Request('https://fn.invalid/', { method: 'POST',
    headers: { 'content-type': 'application/json', ...PROVEN }, body: JSON.stringify({ ...BODY, sys, input: [{ role: 'user', content: 'كيف تعمل المنصة؟' }], stream: true }) }));
  const sse = await res.text();
  const words = sse.split('\n').filter((l) => l.startsWith('data: ') && l !== 'data: [DONE]').map((l) => JSON.parse(l.slice(6)).choices[0].delta.content ?? '').join('');
  assertEquals(words, CANNED_TEXT_AR);
  const plain = await invoke(handler, stub, { ...BODY, sys: 'rules\n- Reply in UAE English, the language this conversation is in.', input: [{ role: 'user', content: 'كيف تعمل المنصة؟' }] }, PROVEN);
  assertEquals(plain.json?.content, CANNED_TEXT, 'the rules decide, not the script of the message (a supplier is answered in English)');
  assertEquals(providerCalls.length, 0);
  await new Promise((r) => setTimeout(r, 30));
});
