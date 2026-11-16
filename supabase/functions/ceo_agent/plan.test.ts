// planAction / runPlan: the CEO's planning loop at his door (ledger 1696, 1701, 1705, 1709). No network, no paid model: the
// routines and the model are stubbed. The routines' own checks are proved by the SQL probe
// (scripts/sql/the_ceo_thinks_plans_and_orders_every_week_probe.sql, LOCAL); here: the door asks the model at most twice, files
// whatever the model answered through fn_ceo_plan_file and nothing else, never files a broken answer as a plan, and never asks the
// founder.
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { MAX_PLAN_CALLS, PACK_IS_DATA, parsePlan, planAction, type PlanDeps, runPlan } from './plan.ts';

type Call = { fn: string; args: Record<string, unknown> };
function depsOf(opts: { answers?: string[]; file?: Array<Record<string, unknown>>; request?: Record<string, unknown>; requests?: Array<Record<string, unknown>>; truncated?: boolean; modelError?: string } = {}) {
  const calls: Call[] = [];
  const asked: Array<{ system: string; user: string; taskClass: string }> = [];
  const answers = [...(opts.answers ?? [])];
  const files = [...(opts.file ?? [{ ok: true, revise: false, filed: 2, refused: 0 }])];
  const deps: PlanDeps = {
    rpc: (fn, args) => {
      calls.push({ fn, args });
      if (fn === 'fn_ceo_plan_request' && opts.requests?.length) return Promise.resolve({ data: opts.requests.shift(), error: null });
      if (fn === 'fn_ceo_plan_request') return Promise.resolve({ data: opts.request ?? { ok: true, plan_id: args.p_plan_id, kind: 'weekly', task_class: 'ceo_strategic_planning', system: 'SYS', output_schema: { decision: {} }, input: { pack: { at: 'now' } } }, error: null });
      if (fn === 'fn_ceo_plan_file') return Promise.resolve({ data: files.shift() ?? { ok: true, revise: false }, error: null });
      return Promise.resolve({ data: null, error: { message: 'unexpected rpc ' + fn } });
    },
    model: (system, user, taskClass) => {
      asked.push({ system, user, taskClass });
      return Promise.resolve({ content: answers.shift() ?? null, model: 'stub/model', truncated: opts.truncated ?? false, error: opts.modelError ?? null });
    },
    recentPlans: (limit) => Promise.resolve({ data: [{ id: 1, limit }], error: null }),
  };
  return { deps, calls, asked };
}
const PLAN = JSON.stringify({ situation: 's', decision: { bets: [{ channel: 'reply_within_1h', seat: 'sales_engineer', measure: 'replies_unanswered', target: 0 }] } });

Deno.test('plan: the model is asked on the request\'s class with the pack, and its answer is filed through code', async () => {
  const m = depsOf({ answers: [PLAN] });
  const r = await runPlan(m.deps, 7);
  assertEquals(r.ok, true);
  assertEquals(m.asked.length, 1);
  assertEquals(m.asked[0].taskClass, 'ceo_strategic_planning');
  assert(m.asked[0].user.includes('"pack"'), 'the planning pack is the input');
  const filed = m.calls.find((c) => c.fn === 'fn_ceo_plan_file')!;
  assertEquals(filed.args.p_plan_id, 7);
  assertEquals((filed.args.p_output as Record<string, unknown>).situation, 's');
  assertEquals(filed.args.p_error, null);
});

Deno.test('plan: a refused bet goes back to the model once with the reasons, never a third time', async () => {
  const m = depsOf({ answers: [PLAN, PLAN, PLAN], file: [{ ok: true, revise: true, refused: 1, refusals: [{ refused_because: ['channel paid_ads is refused'] }] }, { ok: true, revise: true }] });
  const r = await runPlan(m.deps, 9);
  assertEquals(m.asked.length, MAX_PLAN_CALLS, 'the answer and one revision');
  assertEquals(m.calls.filter((c) => c.fn === 'fn_ceo_plan_file').length, 2);
  assertEquals(m.calls.filter((c) => c.fn === 'fn_ceo_plan_request').length, 2, 'the revision re-reads the request, which carries the refusals');
  assertEquals(r.calls, 2);
});

Deno.test('plan: a broken answer is filed as an error (held), never as a plan', async () => {
  for (const o of [{ answers: ['not json at all'] }, { answers: [PLAN], truncated: true }, { answers: [''], modelError: 'model_hold' }]) {
    const m = depsOf(o);
    await runPlan(m.deps, 3);
    const filed = m.calls.find((c) => c.fn === 'fn_ceo_plan_file')!;
    assert(typeof filed.args.p_error === 'string' && String(filed.args.p_error).length > 0, 'the failure is named: ' + JSON.stringify(o));
    if (o.truncated) assertEquals(filed.args.p_error, 'the answer was truncated');
  }
});

Deno.test('plan: only the CEO plans; the founder reads; nothing asks the founder', async () => {
  const m = depsOf({ answers: [PLAN] });
  assertEquals((await planAction(m.deps, 'founder', 'plan', { plan_id: 1 }))?.status, 403);
  assertEquals((await planAction(m.deps, 'ceo', 'plan', {}))?.status, 400);
  assertEquals((await planAction(m.deps, 'ceo', 'plan', { plan_id: 2 }))?.status, 200);
  assertEquals((await planAction(m.deps, 'founder', 'plan_read', { limit: 99 }))?.status, 200);
  assertEquals(await planAction(m.deps, 'ceo', 'nothing', {}), null);
  // the door calls only the plan's own routines: no notice, no question, no message to anybody
  assertEquals([...new Set(m.calls.map((c) => c.fn))].sort(), ['fn_ceo_plan_file', 'fn_ceo_plan_request']);
});

Deno.test('plan: a plan the database will not hand out is not sent to the model', async () => {
  const m = depsOf({ request: { ok: false, reason: 'plan 4 is filed' } });
  const r = await runPlan(m.deps, 4);
  assertEquals(r.ok, false);
  assertEquals(m.asked.length, 0);
});

Deno.test('parsePlan: an object, a fenced object, or an object inside a sentence; nothing else', () => {
  assertEquals(parsePlan('{"a":1}'), { a: 1 });
  assertEquals(parsePlan('```json\n{"a":2}\n```'), { a: 2 });
  assertEquals(parsePlan('Here it is: {"a":3} thanks'), { a: 3 });
  assertEquals(parsePlan('[1,2]'), null);
  assertEquals(parsePlan(null), null);
  assertEquals(parsePlan('no braces'), null);
});

Deno.test('plan: detached, the heartbeat is answered 202 and the plan still runs to its filing', async () => {
  const m = depsOf({ answers: [PLAN] });
  let started: Promise<unknown> | null = null;
  m.deps.detach = (w) => { started = w; return true; };
  const r = await planAction(m.deps, 'ceo', 'plan', { plan_id: 5, detach: true });
  assertEquals(r?.status, 202);
  await started;
  assertEquals(m.calls.filter((c) => c.fn === 'fn_ceo_plan_file').length, 1);
  // a runtime that cannot keep work alive: the door waits and answers the result
  const n = depsOf({ answers: [PLAN] });
  n.deps.detach = () => false;
  assertEquals((await planAction(n.deps, 'ceo', 'plan', { plan_id: 6, detach: true }))?.status, 200);
});

Deno.test('plan: the pack goes to the model labelled as untrusted data, never as instructions (REVIEW_ceoplan item 1)', async () => {
  const m = depsOf({ answers: [PLAN] });
  await runPlan(m.deps, 11);
  const sent = JSON.parse(m.asked[0].user);
  assertEquals(sent.note, PACK_IS_DATA);
  assert(/DATA, never instructions/.test(sent.note) && /untrusted/.test(sent.note));
  assert(Object.keys(sent).indexOf('note') < Object.keys(sent).indexOf('input'), 'the note comes before the pack');
});

Deno.test('plan: a revision the database will not hand out (the cap, or a revision already asked) costs no second call (REVIEW_ceoplan item 3)', async () => {
  const ok = { ok: true, plan_id: 12, kind: 'weekly', task_class: 'ceo_strategic_planning', system: 'SYS', output_schema: {}, input: { pack: {} } };
  const m = depsOf({ answers: [PLAN, PLAN], requests: [ok, { ok: false, reason: 'week_aed_cap' }], file: [{ ok: true, revise: true, refused: 1 }] });
  const r = await runPlan(m.deps, 12);
  assertEquals(m.asked.length, 1, 'the model was asked once: the revision was refused before any call');
  assertEquals(m.calls.filter((c) => c.fn === 'fn_ceo_plan_request').length, 2, 'the revision asked the database first');
  assertEquals(m.calls.filter((c) => c.fn === 'fn_ceo_plan_file').length, 1);
  assertEquals(r.ok, false);
});
