// the_widget_person_check_is_one_small_real_call — customer_support, PR #1392. needsAPerson with a REAL model call
// (ruling 1260: real AI, no stubbed model; graded by code). Replaces the mocked-model reasoned_decisions.test.ts.
// The widget runs it after every reply; on production it planned and retrieved knowledge into a ~15k-token synthesis
// that was cut off at its cap. Proves, against the production ai_gateway inside a tagged rehearsal window (cap USD 2,
// closed in finally): no decompose call, no retrieval, ONE synthesis whose prompt stays small, inside its synthesis cap (SYNTH_MAX),
// and the model's choice is right in English and Arabic. The database side is an in-memory recorder, so nothing is
// written and nothing is sent to anyone. The held path (no model reached) still files the question in the hold queue.
//
//   QD_FIXTURES=1 deno run -A --no-lock --node-modules-dir=auto scripts/e2e/the_widget_person_check_is_one_small_real_call.ts
import { newRun, keys, internalCred, BASE, REF, closeRehearsalWindow } from '../lib/demo_factory.mjs';
import { mgmtFixture, mgmtRead } from '../lib/qd_guard.mjs';
import { needsAPerson } from '../../supabase/functions/_shared/reasoned_decisions.ts';
import { deliverReasoned, type DeliveryIO } from '../../supabase/functions/_shared/reasoned_delivery.ts';
import type { GateAnswer } from '../../supabase/functions/_shared/llm_hold.ts';
import { SYNTH_MAX, type HeldRow, type Phase, type ThinkDeps, type ThinkResult } from '../../supabase/functions/_shared/think.ts';

const CAP_USD = 2;
const TAG = newRun({}).tag;
const { SERVICE } = await keys();
const xcred = await internalCred();
const gw = (await mgmtRead(REF, `select value from public.app_secrets where key='cred_fn_ai'`))[0]?.value;
if (!gw) throw new Error('no gateway credential');

function deps(hold = false) {
  const calls: { phase: Phase; chars: number; max?: number; taskClass: string; model: string | null }[] = [];
  const rpcs: string[] = [];
  const d: ThinkDeps = {
    gate: () => Promise.resolve((hold ? { allowed: false, rule: 'founder_hold', held: 1, routes: 8 } : null) as GateAnswer),
    llm: async (phase, system, input, o) => {
      const r = await fetch(`${BASE}/functions/v1/ai_gateway`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', Authorization: 'Bearer ' + SERVICE, 'x-qd-e2e-run': TAG, 'x-qd-e2e-secret': xcred },
        body: JSON.stringify({ __secret: gw, fn: 'site_assistant', task_class: o.taskClass, agent: o.seat, sys: system, input, max: o.max ?? 900,
          client_timeout_ms: 50_000, cache_ttl_min: 0, response_format: { type: 'json_object' }, subject: o.subject ?? { fixture: true } }),
        signal: AbortSignal.timeout(60_000),
      }).catch((e) => ({ ok: false, json: () => Promise.resolve({ error: String(e) }) } as unknown as Response));
      const j = await r.json().catch(() => ({}));
      calls.push({ phase, chars: system.length + input.length, max: o.max, taskClass: o.taskClass, model: j?.model ?? null });
      return { content: j?.content ?? null, model: j?.model ?? null, error: j?.error ?? null };
    },
    embed: () => Promise.resolve(null),
    // In-memory database: records which routines were asked for; a retrieval would return big rows and fail the size check.
    rpc: (fn) => {
      rpcs.push(fn);
      if (fn === 'fn_reason_hold') return Promise.resolve({ data: 77, error: null });
      if (fn === 'fn_case_recall') return Promise.resolve({ data: { cases: [] }, error: null });
      if (fn.startsWith('fn_reason_retrieve')) return Promise.resolve({ data: Array.from({ length: 6 }, (_, i) => ({ source: 'k', id: i, title: 't', excerpt: 'x'.repeat(1200), similarity: 0.9 })), error: null });
      return Promise.resolve({ data: null, error: null });
    },
  };
  return { d, calls, rpcs };
}

const ASK = { seat: 'customer_support' as const, surface: 'site_assistant.person', audience: 'visitor' as const, subject: { email: `qd-${TAG}-widget@example.invalid` } };
const CASES = [
  { id: 'en_person', message: 'ZZ DEMO: Can I speak to a real person please?', expect: true },
  { id: 'ar_person', message: 'ZZ DEMO: أريد التحدث مع موظف حقيقي من فضلك', expect: true },
  { id: 'en_plain', message: 'ZZ DEMO: What is the difference between MDF and plywood?', expect: false },
];
const fails: string[] = [];
const rows: unknown[] = [];
const results: Record<string, ThinkResult> = {};

await mgmtFixture(REF, `insert into public.rehearsal_window (run_tag, opened_by, models_allowed, cap_usd, expires_at)
  values ('qd_run:${TAG}', 'the_widget_person_check_is_one_small_real_call', true, ${CAP_USD}, now() + interval '30 minutes')`, 'rehearsal window');
try {
  for (const c of CASES) {
    const m = deps();
    const r = await needsAPerson(m.d, { ...ASK, message: c.message, dedupeKey: `widget:person:${TAG}:${c.id}` });
    const s = m.calls[0];
    const check = (ok: boolean, why: string) => { if (!ok) fails.push(`${c.id}: ${why}`); };
    check(r.value === c.expect, `value ${r.value}, expected ${c.expect} (status ${r.result.status})`);
    check(JSON.stringify(m.calls.map((x) => x.phase)) === '["synthesise"]', `phases ${m.calls.map((x) => x.phase)}`);
    check(m.rpcs.filter((f) => f.startsWith('fn_reason_retrieve')).length === 0, 'a retrieval ran');
    check(s?.max === SYNTH_MAX, `cap ${s?.max}`);
    check(s?.taskClass === 'customer_communication', `task class ${s?.taskClass}`);
    check((s?.chars ?? 1e9) < 8000, `prompt ${s?.chars} chars`);   // ~4 chars a token: well under 2k (was 14.6-15.7k)
    results[c.id] = r.result;
    rows.push({ id: c.id, value: r.value, model: s?.model, chars: s?.chars });
  }
  // THE FAILURE PATH: held by the gate, no model reached, no guess; the question is filed for the replay.
  const h = deps(true);
  const r = await needsAPerson(h.d, { ...ASK, message: 'ZZ DEMO: I want a human', dedupeKey: `widget:person:${TAG}:held` });
  if (r.value !== null || r.result.status !== 'held') fails.push(`held: value ${r.value}, status ${r.result.status}`);
  if (h.rpcs.filter((f) => f === 'fn_reason_hold').length !== 1) fails.push('held: not filed in fn_reason_hold');
  if (h.calls.length) fails.push('held: a model was called');
  // THE REPLAY FILES THE CEO REPORT: the held row, replayed with the real model's results, reports to the CEO exactly
  // when a person was asked for (reasoned_delivery.ts, site_assistant.person). A recording io: nothing is sent.
  const ceo: string[] = []; const other: string[] = [];
  const io = new Proxy({}, { get: (_t, k) => (key: string) => {
    if (k === 'reportToCeo') ceo.push(key); else other.push(String(k));
    return Promise.resolve({ ok: true });
  } }) as DeliveryIO;
  const held = (id: number, q: string): HeldRow => ({ id, seat: 'customer_support', surface: 'site_assistant.person', subject: { path: '/pricing' },
    request: { seat: 'customer_support', surface: 'site_assistant.person', question: q } as HeldRow['request'] });
  for (const [id, cid] of [[901, 'en_person'], [902, 'ar_person'], [903, 'en_plain']] as const) {
    const d = await deliverReasoned(held(id, CASES.find((c) => c.id === cid)!.message), results[cid], io);
    if (d.delivered !== (cid !== 'en_plain')) fails.push(`replay ${cid}: delivered ${d.delivered}`);
  }
  if (JSON.stringify(ceo) !== '["widget:person:held:901","widget:person:held:902"]') fails.push(`replay: CEO reports ${JSON.stringify(ceo)}`);
  if (other.length) fails.push(`replay: other effects ${other}`);
  rows.push({ replay_ceo_reports: ceo });
} finally {
  await closeRehearsalWindow(TAG);
}
const cost = (await mgmtRead(REF, `select count(*)::int calls, coalesce(sum(cost_aed),0)::float aed from public.ai_cost_log where e2e_run_tag = '${TAG}'`))[0];
console.log(JSON.stringify({ run: TAG, rows, cost, fails }, null, 1));
if (fails.length) Deno.exit(1);
