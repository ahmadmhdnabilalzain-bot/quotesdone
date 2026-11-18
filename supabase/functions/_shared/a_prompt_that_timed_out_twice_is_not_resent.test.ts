// A PROMPT THAT TIMED OUT TWICE IS NOT SENT AGAIN AS IT WAS (it_engineer, 18 Nov 2026). Measured on production (ai_cost_log fn
// resilience_ping, 48 h to 18 Nov 10:20Z): the held replay sent the same prompt_hash again after it had ended at the gateway's
// wall with 0 output tokens - ceo 25 billed failures over 19 hashes, it_engineer 9 over 9 and never answered - each try at the
// same size and the same high effort (_shared/think/replay.ts). These replay replayHeld against a claim that says how many
// earlier tries timed out (fn_reason_held_due's gateway_timeouts, scripts/sql/a_prompt_that_timed_out_twice_is_not_resent.sql)
// and record what each model call was asked. No network, no env, no paid call.
import { assert, assertEquals } from 'jsr:@std/assert';
import { GATEWAY_TIMEOUT, MODEL_STEP_KINDS, replayHeld, replayShape, timedOutAtGateway, type HeldRow, type LlmReply, type ThinkDeps } from './think.ts';

const J = (x: unknown) => JSON.stringify(x);
type Call = { phase: string; effort?: string };
type Rpc = { fn: string; args: Record<string, unknown> };

const decisionRow = (o: Partial<HeldRow> & { audience?: string; effort?: 'low' | 'medium' | 'high'; plan?: boolean } = {}): HeldRow => ({
  id: o.id ?? 700, seat: o.seat ?? 'it_engineer', surface: o.surface ?? 'it_engineer.order_plan', subject: null, created_at: new Date().toISOString(),
  attempts: o.attempts, gateway_timeouts: o.gateway_timeouts,
  request: {
    seat: (o.seat ?? 'it_engineer') as never, surface: o.surface ?? 'it_engineer.order_plan', question: 'Can you raise Microsoft inbox placement to 80% by the due date?',
    context: { audience: (o.audience ?? 'internal') as never },
    decision: { name: 'order_plan', options: [{ id: 'can', meaning: 'I can' }, { id: 'cannot', meaning: 'I cannot' }] },
    ...(o.effort ? { effort: o.effort } : {}),
    ...(o.plan ? { plan: { steps: [] } } : {}),
  },
});

function rig(rows: HeldRow[], answer: 'timeout' | 'answer' = 'timeout') {
  const calls: Call[] = []; const rpcs: Rpc[] = []; let left = [...rows];
  const deps: ThinkDeps = {
    gate: () => Promise.resolve({ allowed: true } as never),
    llm: (phase, _s, _i, o): Promise<LlmReply> => {
      calls.push({ phase, effort: o.effort });
      if (phase === 'decompose') return Promise.resolve({ content: J({ steps: [{ id: 's1', goal: 'g', query: 'q', needs_knowledge: false }], facts: [] }), model: 'm' });
      // the production shape: the gateway's wall, nothing written (held row 43959, 18 Nov 09:30Z)
      if (answer === 'timeout') return Promise.resolve({ content: null, model: null, error: 'gateway_http_502:gateway_deadline' });
      return Promise.resolve({ content: J({ answer: 'I can.', reasoning: [], cited: [], confidence: 0.8, asked_back: null, decision: { choice: 'can' } }), model: 'm' });
    },
    embed: () => Promise.resolve([0.1, 0.2, 0.3]),
    rpc: (fn, args) => {
      rpcs.push({ fn, args });
      if (fn === 'fn_reason_held_due') { const out = left.slice(0, Number(args.p_limit)); left = left.slice(out.length); return Promise.resolve({ data: out, error: null }); }
      if (fn === 'fn_case_recall' || fn === 'fn_case_recall_ml') return Promise.resolve({ data: { cases: [] }, error: null });
      if (fn === 'fn_reason_held_resolve') return Promise.resolve({ data: { status: 'still_held' }, error: null });
      return Promise.resolve({ data: null, error: null });
    },
  };
  const resolved = () => rpcs.filter((r) => r.fn === 'fn_reason_held_resolve').map((r) => r.args.p_result as Record<string, unknown>);
  const findings = () => rpcs.filter((r) => r.fn === 'fn_it_engineer_finding_upsert').map((r) => r.args);
  return { deps, calls, resolved, findings };
}
const run = (r: ReturnType<typeof rig>) => replayHeld(null, 2, r.deps, undefined, { maxRows: 2, budgetMs: 90_000, rowMs: 0 });

Deno.test('a row with two recorded timeouts is not sent at the same effort: the answer goes at medium and the planner is skipped', async () => {
  const r = rig([decisionRow({ attempts: 3, gateway_timeouts: 2 })]);
  await run(r);
  assertEquals(r.calls.filter((c) => c.phase === 'decompose').length, 0, 'the plan that burned 51 s of the 90 s budget is not asked again');
  const answers = r.calls.filter((c) => c.phase === 'synthesise');
  assert(answers.length >= 1, 'the lighter try is still asked once');
  assert(answers.every((c) => c.effort === 'medium'), `every answer call at medium, saw ${J(answers)}`);
  const [res] = r.resolved();
  assertEquals(res.gateway_timeouts, 3, 'the lighter try that timed out is counted too');
  assert(String(res.replay_shape).startsWith('lighter'), String(res.replay_shape));
  const [f] = r.findings();
  assert(f, 'a lighter try that did not answer is closed with a finding');
  assertEquals((f.p_evidence as Record<string, unknown>).owner_seat, 'it_engineer');
  assertEquals(f.p_blast, 'internal');
});

Deno.test('the same row with one recorded timeout is still asked as it was, and its timeout is counted on the row', async () => {
  const r = rig([decisionRow({ attempts: 2, gateway_timeouts: 1 })]);
  await run(r);
  assertEquals(r.calls.filter((c) => c.phase === 'decompose').length, 1, 'as asked: the planner runs');
  assert(r.calls.filter((c) => c.phase === 'synthesise').every((c) => c.effort === undefined), 'no effort named: the class keeps its own');
  assertEquals(r.resolved()[0].gateway_timeouts, 2, 'the second timeout is written where the next claim reads it');
  assertEquals(r.findings().length, 0);
});

Deno.test('a claim from before the SQL (no count) behaves exactly as before', async () => {
  const r = rig([decisionRow({})]);
  await run(r);
  assertEquals(r.calls.filter((c) => c.phase === 'decompose').length, 1);
  assertEquals(r.resolved()[0].gateway_timeouts, 1);
  assertEquals(r.resolved()[0].replay_shape, undefined);
});

Deno.test('a lighter try that answers is recorded as answered and files nothing', async () => {
  const r = rig([decisionRow({ attempts: 3, gateway_timeouts: 2 })], 'answer');
  const out = await run(r) as { rows: { status: string; shape?: string }[] };
  assertEquals(out.rows[0].status, 'answered');
  assertEquals(out.rows[0].shape, 'lighter');
  assertEquals(r.resolved()[0].gateway_timeouts, 2, 'an answer adds no timeout');
  assertEquals(r.findings().length, 0);
});

Deno.test('a customer-facing row with two timeouts is not sent again at all, and its owning seat gets a finding', async () => {
  const r = rig([decisionRow({ seat: 'customer_support', surface: 'customer_support.reply', audience: 'customer', attempts: 3, gateway_timeouts: 2 })]);
  await run(r);
  assertEquals(r.calls.length, 0, 'no model call: nothing billed, and no lighter effort on a reply a customer reads');
  const [res] = r.resolved();
  assertEquals(res.status, 'held', 'resolved as not answered, so the 3-try bound closes it (fn_reason_held_resolve: failed)');
  assert(String(res.reason).startsWith('not_sent_again'), String(res.reason));
  assertEquals(res.gateway_timeouts, 2);
  const [f] = r.findings();
  assertEquals(f.p_blast, 'customer_facing');
  assertEquals((f.p_evidence as Record<string, unknown>).owner_seat, 'customer_support');
  assertEquals(f.p_raised_by, 'customer_support');
});

Deno.test('three timeouts (the lighter try included) is never sent again', async () => {
  const r = rig([decisionRow({ attempts: 3, gateway_timeouts: 3 })]);
  await run(r);
  assertEquals(r.calls.length, 0);
  assertEquals(r.findings().length, 1);
});

Deno.test('an internal row already at medium with its own plan has nothing lighter left: closed, not re-sent', () => {
  assertEquals(replayShape(decisionRow({ gateway_timeouts: 2, effort: 'medium', plan: true })).send, 'not_again');
  // a row with its own plan but the class's high effort is still sent lighter, keeping its plan
  const s = replayShape(decisionRow({ gateway_timeouts: 2, plan: true }));
  assertEquals(s.send, 'lighter');
  if (s.send === 'lighter') { assertEquals(s.request.effort, 'medium'); assertEquals(s.request.plan, { steps: [] }); }
  // never 'low': the gateway raises low to high on a class that decides (effort_policy.ts effortFor)
  const l = replayShape(decisionRow({ gateway_timeouts: 2, effort: 'high' }));
  assert(l.send === 'lighter' && l.request.effort === 'medium');
});

Deno.test('what counts as a timeout: the gateway wall and a client timeout, never a call the replay did not start', () => {
  const failed = (detail: string) => ({ status: 'held' as const, steps: [{ id: 'synthesise.1', kind: 'synthesise', goal: 'g', status: 'failed' as const, detail }] });
  assert(timedOutAtGateway(failed('gateway_http_502:gateway_deadline')));
  assert(timedOutAtGateway(failed('client_timeout_105000ms')));
  assert(!timedOutAtGateway(failed('turn_deadline: 1200 ms left')), 'a call never started bought nothing');
  assert(!timedOutAtGateway(failed('unwritten: the reply is not one JSON object')));
  assert(!timedOutAtGateway({ status: 'answered', steps: failed('gateway_http_502:gateway_deadline').steps }), 'an answer is not a timeout');
  // a retrieval step is not a prompt: an embedding that timed out is not counted
  assert(!timedOutAtGateway({ status: 'held', steps: [{ id: 's1', kind: 'retrieve', goal: 'g', status: 'failed', detail: 'embedding_unavailable: embed timeout' }] }));
  // the SQL counts legacy rows with the same words and the same steps (a_prompt_that_timed_out_twice_is_not_resent.sql)
  const sql = Deno.readTextFileSync(new URL('../../../scripts/sql/a_prompt_that_timed_out_twice_is_not_resent.sql', import.meta.url));
  assert(sql.includes(`~* '${GATEWAY_TIMEOUT.source}'`), 'the claim and the replay count timeouts by one pattern');
  assert(sql.includes(`s->>'kind' in (${[...MODEL_STEP_KINDS].map((k) => `'${k}'`).join(', ')})`), 'and on the same model steps');
  assert(/returning h\.id, h\.seat, h\.surface, h\.request, h\.subject, h\.created_at, h\.attempts,/.test(sql));
});

Deno.test('a planner that timed out is counted: its cause stays on the step the run fell back from (the CEO\'s 51 s plans)', async () => {
  // the planner hits the wall (21 CEO plans at 51.3 s, 48 h to 18 Nov) and the answer then fails too
  const r = rig([decisionRow({ attempts: 1 })]);
  const deps: ThinkDeps = { ...r.deps, llm: (phase, s, i, o) => phase === 'decompose'
    ? Promise.resolve({ content: null, model: null, error: 'gateway_http_502:gateway_deadline' }) : r.deps.llm(phase, s, i, o) };
  await replayHeld(null, 2, deps, undefined, { maxRows: 2, budgetMs: 90_000, rowMs: 0 });
  const [res] = r.resolved();
  const plan = (res.steps as { kind: string; detail?: unknown }[]).find((s) => s.kind === 'decompose');
  assertEquals(plan?.detail, 'gateway_http_502:gateway_deadline; one-step plan used', 'not "unparseable plan"');
  assertEquals(res.gateway_timeouts, 1);
});
