// THE SEAT EXAM'S JUDGE NAMES THE ANSWERING MODEL, THROUGH THE REAL GATEWAY (it_engineer, 19 Nov 2026).
// Seat exam run 1 (seat_exam_run id 1, week 15 Nov) asked 18 and passed 1. In its window llm_attempt / ai_cost_log hold 18
// calls of fn knowledge_exam task routine_employee_reasoning (the wordings) and 0 of task knowledge_validation (the judge):
// it_engineer/index.ts called the judge with no counterpart_model, model_policy.knowledge_validation.reviews_class is
// non-empty, and ai_gateway/handle.ts answers such a review 400 review_needs_counterpart before any model is chosen. The 17
// misses were graded by the exact-phrase check alone; 13 were right answers in other words.
//
// This loads ai_gateway/index.ts's own handler (_shared/twilio_free_harness.ts: env, Deno.serve and the database replaced),
// puts a stub where https://openrouter.ai is, and sends the exam's REAL model calls (seat_exam_calls.ts, the wiring index.ts
// uses, through _shared/llm.ts) into it. No network, no paid call, ZZ DEMO text only.
//   THE CONTROL: the judge as it was sent on 16 Nov (no counterpart) is refused 400 review_needs_counterpart by this stub
//   gateway, so a green below cannot come from a harness that accepts anything.
//   THE FIX: the judge carries counterpart_model = the answer's model, the gateway asks fn_ai_route_review_for with it, and
//   the reviewer it returns (another family) is the model called.
//   cd /tmp/claude-0/wtEX && DENO_NO_PACKAGE_JSON=1 deno test --no-lock --node-modules-dir=auto \
//     --allow-env=SUPABASE_URL,SUPABASE_SERVICE_ROLE_KEY,RESEND_INBOUND_NO_SERVE --allow-net=127.0.0.1 \
//     --allow-read=. supabase/functions/it_engineer/the_judge_names_the_answering_model.test.ts
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { invoke, loadFunction, type Stub } from '../_shared/twilio_free_harness.ts';
import { JUDGE_SYSTEM, REWORD_SYSTEM, type AskRow, type ExamItem, judgeInput, runExamBatch } from './seat_exam.ts';

const J = (o: unknown, status = 200, headers: Record<string, string> = {}) =>
  new Response(JSON.stringify(o), { status, headers: { 'content-type': 'application/json', ...headers } });

// The model matrix as production holds it (model_policy knowledge_validation, read 19 Nov 2026): primary qwen/qwen3.8-flash,
// fallback anthropic/claude-sonnet-5.5; the seats answered on openai/gpt-6-luna-pro (68 asks) and anthropic/claude-opus-5.5 (11).
const AUTHOR = 'openai/gpt-6-luna-pro';
const REVIEWER = 'qwen/qwen3.8-flash', REVIEWER_FB = 'anthropic/claude-sonnet-5.5';
// llm.ts reads cred_fn_knowledge_exam before the first gateway hop, i.e. from the harness's own default for an unlisted secret
const CRED = 'stub-secret-value-0123456789abcdef';
type DbCall = { path: string; rpc: string | null; body: Record<string, unknown> | null };
const db = { calls: [] as DbCall[] };
const stub: Stub = {
  handle: async (req, u) => {
    const rpc = u.pathname.match(/^\/rest\/v1\/rpc\/(.+)$/)?.[1] ?? null;
    const body = req.method === 'POST' ? await req.clone().json().catch(() => null) : null;
    db.calls.push({ path: u.pathname, rpc, body });
    if (rpc === 'fn_internal_auth') return J(String(body?.p_secret) === CRED ? { ok: true, context: 'fn.knowledge_exam', credential_id: 9, legacy: false } : { ok: false });
    if (rpc === 'fn_ai_route') {
      const tc = String(body?.p_task_class ?? '');
      return J({ model: tc === 'knowledge_validation' ? REVIEWER : AUTHOR, fallback: REVIEWER_FB, tier: 'small', task_class: tc, use_llm: true,
                 max_tokens: 800, why: 'policy: ' + tc, cache: false, cache_ttl_min: 0 });
    }
    // fn_ai_route_review_for picks outside the author's family (openai) from the class's own pair
    if (rpc === 'fn_ai_route_review_for') {
      return J({ model: REVIEWER, fallback: REVIEWER_FB, tier: 'small', task_class: body?.p_task_class, use_llm: true, max_tokens: 800,
                 cache: false, cache_ttl_min: 0, independent: true, reviewer_family: 'qwen', reviewer_tier: 'standard', author_model: body?.p_counterpart_model,
                 author_family: ['openai'], why: 'policy: knowledge_validation | INDEPENDENT REVIEW: author wrote on ' + body?.p_counterpart_model });
    }
    if (rpc === 'fn_kernel_paid_provider_gate') return J({ allowed: true, rule: 'registered_breaker_closed' });
    if (rpc === 'fn_llm_cache_lookup') return J({ hit: false });
    if (rpc === 'fn_model_cost_usd') return J(0.0001);
    // the review class's row: knowledge_validation judges other classes' output, so it needs the author's model; the
    // reworder's class (routine_employee_reasoning) reviews nothing
    if (u.pathname === '/rest/v1/model_policy') {
      const tc = (u.searchParams.get('task_class') || '').replace(/^eq\./, '');
      const row = { reviews_class: tc === 'knowledge_validation' ? ['knowledge_ingestion', 'internal_judgement', 'routine_employee_reasoning'] : [] };
      return (req.headers.get('accept') || '').includes('vnd.pgrst.object') ? J(row) : J([row]);
    }
    if (u.pathname === '/rest/v1/app_secrets') {
      const key = (u.searchParams.get('key') || '').replace(/^eq\./, '');
      const value = key.startsWith('cred_fn_') ? CRED : 'zz-stub-secret-0123456789abcdef0123';
      return (req.headers.get('accept') || '').includes('vnd.pgrst.object') ? J({ value }) : J([{ value }]);
    }
    return undefined;
  },
};
const rpcs = (name: string) => db.calls.filter((c) => c.rpc === name).map((c) => c.body ?? {});

// ---- the provider: a wording for the reworder, a verdict for the judge -------------------------------------------------
const ITEM: ExamItem = {
  item_id: 'accountant-exam-03', seat: 'accountant',
  q_en: "Is anything added to the reveal fee for paying by card, and who bears Stripe's fee?",
  expected_facts: ['nothing is added for paying by card', '2.9% plus AED 1'], used_wordings: [], fix_id: null, fix_ref: null,
};
const WORDING = 'When the reveal fee is paid by card, does anything get added, and who carries Stripe’s fee?';
const completion = (content: string) => J({ id: 'gen-zz', object: 'chat.completion', choices: [{ index: 0, message: { role: 'assistant', content }, finish_reason: 'stop' }],
  usage: { prompt_tokens: 900, completion_tokens: 40, cost: 0.0001 } });
const providerCalls: { model: string; system: string }[] = [];
const gatewayBodies: Record<string, unknown>[] = [];
const gatewayAnswers: { status: number; json: Record<string, unknown> | null }[] = [];

const handler = await loadFunction('ai_gateway', () => import('../ai_gateway/index.ts'));
const viaHarness = globalThis.fetch;
globalThis.fetch = (async (input: RequestInfo | URL, init?: RequestInit) => {
  const req = input instanceof Request ? input : new Request(String(input), init);
  const u = new URL(req.url);
  if (u.hostname === 'openrouter.ai') {
    if (u.pathname === '/api/v1/models') return J({ data: [] });
    const body = JSON.parse(await req.clone().text());
    const system = String((body.messages ?? []).filter((m: { role: string }) => m.role === 'system').map((m: { content: unknown }) => typeof m.content === 'string' ? m.content : JSON.stringify(m.content)).join(' '));
    providerCalls.push({ model: String(body.model), system });
    if (system.includes('You grade one exam answer')) return completion(JSON.stringify({ facts: ITEM.expected_facts.map((fact) => ({ fact, present: true })) }));
    return completion(JSON.stringify({ wording: WORDING }));
  }
  // _shared/llm.ts's hop: answered by the real gateway handler, exactly as the edge runtime would
  if (u.pathname === '/functions/v1/ai_gateway') {
    const body = JSON.parse(await req.clone().text());
    gatewayBodies.push(body);
    const out = await invoke(handler, stub, body);
    gatewayAnswers.push({ status: out.status, json: out.json });
    return J(out.json, out.status, { 'x-served-by': 'supabase-edge-runtime' });
  }
  return viaHarness(input, init);
}) as typeof fetch;
// imported after the harness has replaced Deno.env: llm.ts fixes its gateway URL at import
const { makeLlmRich } = await import('../_shared/llm.ts');
const { examModelCalls } = await import('./seat_exam_calls.ts');

function reset() { db.calls.length = 0; providerCalls.length = 0; gatewayBodies.length = 0; gatewayAnswers.length = 0; }
const ANSWER = 'Paying by card adds nothing. QuotesDone carries the Stripe charge itself: 2.9% + AED 1.';

Deno.test('control: the judge as sent on 16 Nov (no counterpart_model) is refused by the gateway before any model runs', async () => {
  reset();
  const r = await makeLlmRich([], { fn: 'knowledge_exam', agent: 'it_engineer', taskClass: 'knowledge_validation', max: 400, timeoutMs: 15_000, json: true, temperature: 0, internalDuty: true })(
    JUDGE_SYSTEM, judgeInput(WORDING, ANSWER, ITEM.expected_facts), 400);
  assertEquals(r.content, null);
  assertEquals([gatewayAnswers[0]?.status, gatewayAnswers[0]?.json?.outcome], [400, 'review_needs_counterpart']);
  assertEquals(providerCalls.length, 0, 'no model is called for a review that cannot prove its independence');
});

Deno.test('the judge carries the answering model as counterpart_model and is routed to a reviewer of another family', async () => {
  reset();
  const calls = examModelCalls(makeLlmRich);
  const j = await calls.judge(JUDGE_SYSTEM, judgeInput(WORDING, ANSWER, ITEM.expected_facts), AUTHOR);
  assertEquals(gatewayBodies.map((b) => [b.fn, b.task_class, b.counterpart_model]), [['knowledge_exam', 'knowledge_validation', AUTHOR]]);
  assertEquals(gatewayAnswers[0].status, 200, 'not rejected by the gateway: ' + JSON.stringify(gatewayAnswers[0].json));
  assertEquals(rpcs('fn_ai_route_review_for').map((b) => [b.p_task_class, b.p_counterpart_model]), [['knowledge_validation', AUTHOR]]);
  assertEquals(rpcs('fn_ai_route').length, 0, 'a review is routed by fn_ai_route_review_for only');
  assertEquals(providerCalls.map((c) => c.model), [REVIEWER]);
  assert(!providerCalls[0].model.startsWith('openai/'), 'the judge is never of the author’s family');
  assertEquals(j.error, null);
  assert(String(j.content).includes('"present":true'));
});

Deno.test('a whole exam ask through the real gateway: a right answer in other words passes on the judge', async () => {
  reset();
  const calls = examModelCalls(makeLlmRich);
  const queue = [ITEM];
  const rows: AskRow[] = [];
  const r = await runExamBatch({
    next: async () => ({ items: queue.length ? [queue.shift()!] : [], stop: null }),
    reword: calls.reword,
    judge: calls.judge,
    answer: async () => ({ status: 'answered', answer: ANSWER, model: AUTHOR, reason: null }),
    record: async (row) => { rows.push(row); return { asked_id: 1, fix_id: null, lesson_needed: false }; },
    lesson: async () => ({ knowledge_id: null, error: 'not called' }),
    now: () => 0,
  }, 1);
  assertEquals([r.asked, r.passed, r.missed], [1, 1, 0]);
  assertEquals([rows[0].wording, rows[0].graded_by, rows[0].pass, rows[0].missing], [WORDING, 'model', true, []]);
  // the wording went out as the reworder's class with the terms to keep; the judge as the review class naming the author
  assertEquals(gatewayBodies.map((b) => [b.task_class, b.counterpart_model ?? null]), [['routine_employee_reasoning', null], ['knowledge_validation', AUTHOR]]);
  assertEquals(JSON.parse(String(gatewayBodies[0].input)).keep_verbatim, ['reveal fee', 'Stripe']);
  assertEquals(gatewayBodies[0].sys, REWORD_SYSTEM);
  assertEquals(gatewayAnswers.map((a) => a.status), [200, 200]);
});
