// An order is a conversation (ceo, 16 Nov 2026, founder: "how do they talk to each other?"). Every turn of an order is a held
// question (scripts/sql/an_order_is_a_conversation_until_its_outcome.sql, fn_order_ask) that replayHeld reasons with think() as
// it does any seat's duty. This pins, with the model stubbed and no network:
//   1. the routes: a seat's turns (order_plan, order_status, order_retro) are its own duty on its own judgement route, never
//      the easy class; the CEO's (order_answer, order_response, order_next) are on his routine route, never his Opus route;
//   2. a turn is ONE model call (a fixed one-step plan and normal stakes: no planner, no verifier);
//   3. the seat's plan comes back as its own writing: the prompt asks for the fields beside the choice (decision.authored)
//      and no verbatim evidence is demanded, while a reader's fields (no authored flag) still need it.
import { assert, assertEquals, assertStringIncludes } from 'jsr:@std/assert@1';
import { EASY_DUTY_SURFACE, INTERNAL_DUTY_SURFACE, replayHeld, think, type LlmReply, type ThinkDeps, type ThinkRequest } from './think.ts';

const PLAN_FIELDS = [
  { key: 'reason', question: 'why can, partly or cannot' }, { key: 'steps', question: 'a JSON array of {tool, action, by}' },
  { key: 'needs', question: 'a JSON array of needs' }, { key: 'risks', question: 'the risks' }, { key: 'milestones', question: 'a JSON array of {at, expect}' },
];
const OPTIONS = [{ id: 'can', meaning: 'can' }, { id: 'partly', meaning: 'partly' }, { id: 'cannot', meaning: 'cannot' }];

// the request exactly as fn_order_ask stores it, with what replayHeld adds for the surface
function request(seat: 'it_engineer' | 'ceo', surface: string, authored = true): ThinkRequest {
  return {
    seat, surface, question: 'The CEO ordered you order #27 to it_engineer: Microsoft inbox placement at least 80% on a GlockApps retest. Write your plan.',
    context: { audience: 'internal', case: { order: { handoff_id: 27, measure: 'placement_inbox_pct', target: 80 }, your_tools: [{ tool: 'sender_readings' }] } },
    decision: { name: surface, options: OPTIONS, fields: PLAN_FIELDS, ...(authored ? { authored: true } : {}) },
    plan: { steps: [] }, research: false, stakes: 'normal', subject: { handoff_id: 27, kind: 'plan', round: 1 },
    easy: EASY_DUTY_SURFACE.test(surface), internalDuty: INTERNAL_DUTY_SURFACE.test(surface),
  };
}
function deps(reply: () => LlmReply) {
  const calls: { phase: string; system: string; taskClass: string }[] = [];
  const d = {
    gate: () => Promise.resolve(null),
    llm: (phase: string, system: string, _i: string, o: { taskClass: string }) => { calls.push({ phase, system, taskClass: o.taskClass }); return Promise.resolve(reply()); },
    embed: () => Promise.resolve([0.1, 0.2]),
    rpc: (fn: string) => Promise.resolve({ data: fn === 'fn_judgement_record' ? 41 : fn.startsWith('fn_case_recall') ? { cases: [] } : fn === 'fn_seat_pool_context' ? { block: '' } : [], error: null }),
  } as unknown as ThinkDeps;
  return { d, calls };
}
const PLAN = {
  answer: 'Partly: I keep the sending side clean and read every verdict; the re-test, the warm-up recipients and the volume come from others.',
  reasoning: ['the register: glockapps_test is the engineer session\'s'], cited: [], confidence: 0.7, asked_back: null,
  decision: { choice: 'partly', fields: {
    reason: { value: 'I cannot run a GlockApps test, change DNS or create warm-up volume myself.' },
    steps: { value: '[{"tool":"sender_readings","action":"confirm SPF, DKIM and DMARC pass","by":"2026-11-23"}]' },
    needs: { value: '[{"kind":"engineer_session","tool":"glockapps_test","what":"a GlockApps re-test after the warm-up week"}]' },
    risks: { value: 'a re-test before enough volume reads low' },
    milestones: { value: '[{"at":"2026-11-23T18:00:00+04:00","expect":50}]' } } },
};

Deno.test('the routes: a seat\'s order turns are its own duty on its own route; the CEO\'s are on his routine route', () => {
  for (const seat of ['it_engineer', 'sales_engineer', 'marketing', 'customer_support', 'accountant']) {
    for (const k of ['order_plan', 'order_status', 'order_retro']) {
      assert(INTERNAL_DUTY_SURFACE.test(`${seat}.${k}`), `${seat}.${k} is the seat's own duty`);
      assert(!EASY_DUTY_SURFACE.test(`${seat}.${k}`), `${seat}.${k} keeps the seat's own judgement route`);
    }
  }
  for (const k of ['order_answer', 'order_response', 'order_next']) {
    assert(INTERNAL_DUTY_SURFACE.test(`ceo.${k}`) && EASY_DUTY_SURFACE.test(`ceo.${k}`), `ceo.${k} on the routine route`);
  }
  assert(!EASY_DUTY_SURFACE.test('ceo.management_review'), 'the hard reviews keep the CEO\'s own route');
  assert(!EASY_DUTY_SURFACE.test('it_engineer.order_answer'), 'only the CEO answers an order on the routine route');
});

Deno.test('the seat\'s plan: one call on its judgement route, the fields asked beside the choice and kept as written', async () => {
  const m = deps(() => ({ content: JSON.stringify(PLAN), model: 'stub/seat' }));
  const r = await think(m.d, request('it_engineer', 'it_engineer.order_plan'));
  assertEquals(r.status, 'answered', JSON.stringify(r).slice(0, 400));
  assertEquals(r.decision?.choice, 'partly');
  assertStringIncludes(String(r.decision?.fields?.steps?.value), '"tool":"sender_readings"');
  assertStringIncludes(String(r.decision?.fields?.milestones?.value), '"expect":50');
  assertEquals(m.calls.length, 1, 'one model call: ' + m.calls.map((c) => c.phase).join(','));
  assertEquals(m.calls[0].taskClass, 'internal_judgement');
  assertStringIncludes(m.calls[0].system, 'write every field in your own words');
  assertStringIncludes(m.calls[0].system, 'milestones (a JSON array of {at, expect})');
});

Deno.test('the CEO\'s answer runs on his routine route, one call', async () => {
  const m = deps(() => ({ content: JSON.stringify({ ...PLAN, decision: { choice: 'can', fields: { reason: { value: 'accept: the plan answers every need' } } } }), model: 'stub/routine' }));
  const r = await think(m.d, request('ceo', 'ceo.order_answer'));
  assertEquals(r.status, 'answered');
  assertEquals(m.calls.length, 1);
  assertEquals(m.calls[0].taskClass, 'routine_employee_reasoning');
});

Deno.test('a reader\'s fields (no authored flag) still need the person\'s own words: the change is scoped to order turns', async () => {
  const m = deps(() => ({ content: JSON.stringify(PLAN), model: 'stub/seat' }));
  const r = await think(m.d, request('it_engineer', 'it_engineer.order_plan', false));
  assert(r.status !== 'answered', 'unproven fields must be refused without the authored flag: ' + r.status);
  assert(!m.calls[0].system.includes('write every field in your own words'));
});

// Review orderconv item 6 (16 Nov 2026): fn_order_ask stores 'easy', v_seat = 'ceo' in the request, and replayHeld reads
// row.request.easy before its surface regex. So if the SQL lands before a function carrying the new routing.ts is deployed,
// the CEO's turns still run on his routine route. A surface the regex does not know stands in for the old regex here.
Deno.test('the replay honours easy in the stored request: the CEO\'s turn stays on his routine route before routing.ts lands', async () => {
  const surface = 'ceo.order_turn_before_the_deploy';
  assert(!EASY_DUTY_SURFACE.test(surface), 'the stand-in surface is unknown to the regex');
  const run = async (easy: boolean | undefined) => {
    const calls: string[] = [];
    let claimed = false;
    const d = {
      gate: () => Promise.resolve(null),
      llm: (_p: string, _s: string, _i: string, o: { taskClass: string }) => { calls.push(o.taskClass); return Promise.resolve({ content: JSON.stringify({ ...PLAN, decision: { choice: 'can', fields: { reason: { value: 'accept' } } } }), model: 'stub' }); },
      embed: () => Promise.resolve([0.1, 0.2]),
      rpc: (fn: string) => {
        if (fn === 'fn_reason_held_due') {
          const rows = claimed ? [] : [{ id: 1, seat: 'ceo', surface, subject: null, created_at: new Date().toISOString(),
            request: { ...request('ceo', surface), easy, internalDuty: undefined } }];
          claimed = true;
          return Promise.resolve({ data: rows, error: null });
        }
        return Promise.resolve({ data: fn === 'fn_reason_held_resolve' ? { status: 'applied' } : fn.startsWith('fn_case_recall') ? { cases: [] } : fn === 'fn_seat_pool_context' ? { block: '' } : [], error: null });
      },
    } as unknown as ThinkDeps;
    await replayHeld({} as never, 1, d);
    return calls;
  };
  const withFlag = await run(true);
  assert(withFlag.length >= 1 && withFlag.every((c) => c === 'routine_employee_reasoning'), 'easy true: the routine route, got ' + withFlag.join(','));
  const without = await run(undefined);
  assert(without.length >= 1 && without.every((c) => c !== 'routine_employee_reasoning'), 'no flag and an unknown surface: not the routine route, got ' + without.join(','));
});
