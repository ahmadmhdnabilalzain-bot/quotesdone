// think() with a mocked model, embedder and database. No network, no env, no paid call.
import { assert, assertEquals, assertMatch } from 'jsr:@std/assert';
import type { GateAnswer } from './llm_hold.ts';
import { authoritative, isFixtureRequest, parseSearchResults, refuse, replayHeld, taskClassFor, think, type LlmReply, type Phase, type ThinkDeps } from './think.ts';

type Call = { phase: Phase; system: string; input: string; o: Record<string, unknown> };
function mock(o: {
  gate?: unknown; replies: Partial<Record<Phase, (LlmReply | string)[]>>;
  retrieve?: unknown[]; search?: { url: string; title: string }[]; pages?: Record<string, string>;
}) {
  const calls: Call[] = []; const rpcs: [string, Record<string, unknown>][] = [];
  const queues: Record<string, (LlmReply | string)[]> = JSON.parse(JSON.stringify(o.replies));
  const deps: ThinkDeps = {
    gate: () => Promise.resolve((o.gate ?? { allowed: false, rule: 'route_not_registered' }) as GateAnswer),
    llm: (phase, system, input, opts) => {
      calls.push({ phase, system, input, o: opts as Record<string, unknown> });
      const next = queues[phase]?.shift();
      const r: LlmReply = typeof next === 'string' ? { content: next, model: phase === 'verify' ? 'openai/gpt-sol-5.6' : 'qwen/qwen3.8-max-0902' } : (next ?? { content: null, error: 'no mock reply' });
      return Promise.resolve(r);
    },
    embed: (t) => Promise.resolve(t ? [0.1, 0.2, 0.3] : null),
    rpc: (fn, args) => {
      rpcs.push([fn, args]);
      if (fn === 'fn_reason_retrieve') return Promise.resolve({ data: o.retrieve ?? [], error: null });
      if (fn === 'fn_case_recall') return Promise.resolve({ data: { cases: [] }, error: null });
      if (fn === 'fn_reason_hold') return Promise.resolve({ data: 42, error: null });
      if (fn === 'fn_reason_held_due') return Promise.resolve({ data: [{ id: 42, request: { seat: 'ceo', surface: 'ceo.command_intent', question: 'stop the campaign', decision: { name: 'intent', options: [{ id: 'stop', meaning: 'halt work' }, { id: 'ask', meaning: 'a question' }] } } }], error: null });
      return Promise.resolve({ data: 1, error: null });
    },
    search: () => Promise.resolve(o.search ?? []),
    read: (u) => Promise.resolve(o.pages?.[u] ?? null),
  };
  return { deps, calls, rpcs };
}
const J = (x: unknown) => JSON.stringify(x);
const POOL_PLAN = J({
  steps: [{ id: 's1', goal: 'which authority sets private pool rules in Dubai', query: 'Dubai Municipality private villa swimming pool depth and fencing regulations' },
          { id: 's2', goal: 'the same in Abu Dhabi', query: 'Abu Dhabi private swimming pool building regulations depth' }],
  facts: [{ name: 'emirate', why: 'each emirate has its own authority and limits', changes_answer: true, value: null, from: null },
          { name: 'community', why: 'master developers add rules', changes_answer: true, value: null, from: null }],
  high_stakes: true,
});
const KB = [{ source: 'kb_chunks', id: 7, title: 'Dubai Municipality pool guideline', excerpt: 'Private pools need a permit; fencing 1.2 m ...', citation: 'DM-POOL-2021', similarity: 0.91, trust: 'reviewed' }];

Deno.test('the founder\'s pool question: steps, sources, and a question back ALONGSIDE what can already be said', async () => {
  const m = mock({ retrieve: KB, replies: {
    decompose: [POOL_PLAN],
    synthesise: [J({ answer: 'In Dubai a private villa pool needs a Dubai Municipality permit and a fence of at least 1.2 m; typical residential depths run 1.2 to 1.5 m, and master communities such as Emaar add their own approval. In Abu Dhabi the Department of Municipalities and Transport applies. Which emirate and community is your villa in?', reasoning: ['s1: DM governs Dubai'], cited: ['kb_chunks:7'], confidence: 0.8, asked_back: 'Which emirate and community is your villa in?' })],
    verify: [J({ verdict: 'agree', problems: [] })],
  } });
  const r = await think(m.deps, { seat: 'customer_support', surface: 'think.answer', question: 'I want to build a pool at my villa — what depth, what is legal?', context: { audience: 'customer' } });
  assertEquals(r.status, 'answered');
  assert(r.steps.some((s) => s.kind === 'decompose' && s.status === 'done'));
  assertEquals(r.steps.filter((s) => s.kind === 'retrieve').length, 2);
  assertEquals(r.sources.map((s) => s.id), ['kb_chunks:7']);
  assertEquals(r.missing_context.map((f) => f.name), ['emirate', 'community']);
  assertMatch(String(r.asked_back), /emirate/);
  // high stakes: verified by ANOTHER family, routed through the author's model as counterpart (#877)
  assertEquals(r.verified?.status, 'agreed');
  const v = m.calls.find((c) => c.phase === 'verify')!;
  assertEquals(v.o.counterpartModel, 'qwen/qwen3.8-max-0902');
  assertEquals(v.o.taskClass, 'knowledge_validation');
});

Deno.test('under the hold nothing is guessed: status held, filed in the seat queue, no model called', async () => {
  const m = mock({ gate: { allowed: false, rule: 'founder_hold', held: 1, routes: 8 }, replies: {} });
  const r = await think(m.deps, { seat: 'customer_support', surface: 'wa_inbound.needs_a_person', question: 'you people cheated me, I want my money back', dedupeKey: 'wa:SM1',
    decision: { name: 'needs_a_person', options: [{ id: 'needs_a_person', meaning: 'complaint' }, { id: 'no_person', meaning: 'else' }] } });
  assertEquals(r.status, 'held');
  assertEquals(r.held_id, 42);
  assertEquals(m.calls.length, 0);
  const hold = m.rpcs.find(([f]) => f === 'fn_reason_hold')!;
  assertEquals(hold[1].p_seat, 'customer_support');
  assertEquals(hold[1].p_dedupe_key, 'wa:SM1');
  assertEquals(hold[1].p_reason, 'model_hold');
});

Deno.test('an evasive draft is refused and another pass is forced', async () => {
  const m = mock({ retrieve: KB, replies: {
    decompose: [J({ steps: [{ id: 's1', goal: 'g', query: 'q' }], facts: [] })],
    synthesise: [J({ answer: 'I need to check and get back to you.', cited: [], confidence: 0.2 }),
                 J({ answer: 'Glass balustrades on a villa balcony in Dubai are typically 10+10 mm laminated toughened glass, at least 1.1 m high, fixed in an aluminium base shoe; Civil Defence and the Dubai Building Code set the height and the load.', reasoning: ['s1: the code sets height and load'], cited: ['kb_chunks:7'], confidence: 0.7 })],
  } });
  const r = await think(m.deps, { seat: 'sales_engineer', surface: 'think.answer', question: 'what glass do I need for a balcony railing?', context: { audience: 'customer' } });
  assertEquals(r.status, 'answered');
  assertEquals(r.steps.filter((s) => s.kind === 'synthesise').map((s) => s.status), ['refused', 'done']);
  assertMatch(m.calls.filter((c) => c.phase === 'synthesise')[1].system, /PREVIOUS DRAFT WAS REFUSED/);
});

Deno.test('a model that keeps evading is queued, never answered with an excuse', async () => {
  const ev = J({ answer: 'I cannot answer that.', cited: [] });
  const m = mock({ replies: { decompose: [J({ steps: [], facts: [] })], synthesise: [ev, ev, ev] } });
  const r = await think(m.deps, { seat: 'customer_support', surface: 'think.answer', question: 'how thick is a gypsum board?' });
  assertEquals(r.status, 'held');
  assertMatch(String(r.reason), /^model_failed/);
});

Deno.test('a decision must be one of its options', async () => {
  const opts = { name: 'intent', options: [{ id: 'build', meaning: 'make something' }, { id: 'ask', meaning: 'a question' }] };
  const m = mock({ replies: { decompose: [J({ steps: [{ id: 's1', goal: 'read the instruction', needs_knowledge: false }], facts: [] })],
    synthesise: [J({ answer: 'He wants a thing made.', decision: { choice: 'make' } }), J({ answer: 'He wants a new report built, so this is work.', decision: { choice: 'build' } })] } });
  const r = await think(m.deps, { seat: 'ceo', surface: 'ceo.command_intent', question: 'set up a weekly supplier report', decision: opts });
  assertEquals(r.decision?.choice, 'build');
  assertEquals(m.calls.filter((c) => c.phase === 'synthesise').length, 2);
  assertEquals(m.calls[0].o.taskClass, 'routine_employee_reasoning');
});

Deno.test('refuse(): asking back needs a decision-changing missing fact and something said with it', () => {
  const base = { sourceIds: new Set<string>(), conversationText: '' };
  assertMatch(String(refuse({ answer: 'Which emirate is it in, so I can tell you exactly what applies there?', asked_back: 'Which emirate?' }, { ...base, missing: [] })), /no missing fact changes the answer/);
  assertMatch(String(refuse({ answer: 'Which emirate?', asked_back: 'Which emirate?' }, { ...base, missing: [{ name: 'emirate', why: '', changes_answer: true, value: null, from: null }] })), /nothing said alongside/);
  assertMatch(String(refuse({ answer: 'See the guide.', cited: ['kb:9'] }, { ...base, missing: [] })), /not among the sources/);
  assertEquals(refuse({ answer: 'Dubai requires a DM permit and a 1.2 m fence; Abu Dhabi applies DMT rules. Which emirate is the villa in?', asked_back: 'Which emirate?' }, { ...base, missing: [{ name: 'emirate', why: '', changes_answer: true, value: null, from: null }] }), null);
});

Deno.test('refuse(): a field value needs the asker\'s own words as evidence', () => {
  const decision = { name: 'fields', fields: [{ key: 'glass_thickness', question: 'thickness' }] };
  const o = { missing: [], sourceIds: new Set<string>(), decision, conversationText: 'we need 12 mm clear toughened glass' };
  assertEquals(refuse({ answer: 'thickness stated', decision: { fields: { glass_thickness: { value: '12 mm', evidence: '12 mm clear toughened' } } } }, o), null);
  assertMatch(String(refuse({ answer: 'thickness stated', decision: { fields: { glass_thickness: { value: '10 mm', evidence: '10 mm' } } } }, o)), /no evidence copied verbatim/);
  // a real quote from the conversation carrying a DIFFERENT value is still an invented value
  assertMatch(String(refuse({ answer: 'x', decision: { fields: { glass_thickness: { value: 'aluminium', evidence: '12 mm clear toughened' } } } }, o)), /not in the evidence/);
  // a one-letter "quote" is not evidence
  assertMatch(String(refuse({ answer: 'x', decision: { fields: { glass_thickness: { value: 'a', evidence: 'a' } } } }, o)), /no evidence copied verbatim/);
});

Deno.test('refuse(): an answer with no reasoning steps, and a padded evasion phrased another way, are refused', () => {
  const o = { missing: [], sourceIds: new Set<string>(), conversationText: '', requireTrail: true };
  assertMatch(String(refuse({ answer: 'Gypsum board is 12.5 mm for walls and 9.5 mm for ceilings in UAE practice.' }, o)), /no reasoning steps/);
  assertMatch(String(refuse({ answer: 'Our team will contact you.', reasoning: ['x'] }, o)), /defers or declines/);
});

Deno.test('a decision with no options is held, never answered with a free string', async () => {
  const m = mock({ replies: {} });
  const r = await think(m.deps, { seat: 'ceo', surface: 'ceo.command_intent', question: 'stop', decision: { name: 'intent', options: [] } });
  assertEquals([r.status, r.reason], ['held', 'no_options']);
  assertEquals(m.calls.length, 0);
});

Deno.test('thin knowledge is researched on the authoritative web, cited, and written back as pending knowledge', async () => {
  const url = 'https://www.dm.gov.ae/pools';
  const m = mock({ retrieve: [{ source: 'kb_chunks', id: 1, title: 'x', excerpt: 'unrelated', similarity: 0.7 }],
    search: [{ url: 'https://evil.example.com/x', title: 'no' }, { url, title: 'DM pools' }], pages: { [url]: 'Private pools require a building permit.' },
    replies: {
      decompose: [J({ steps: [{ id: 's1', goal: 'DM pool rule', query: 'dubai private pool permit' }], facts: [] })],
      research: [J({ findings: [{ statement: 'Private pools require a Dubai Municipality building permit.', url }] })],
      synthesise: [J({ answer: 'In Dubai a private pool needs a Dubai Municipality building permit before work starts.', reasoning: ['s1: DM requires a permit'], cited: ['web:s1.1'], confidence: 0.7 })],
    } });
  const r = await think(m.deps, { seat: 'customer_support', surface: 'think.answer', question: 'do I need a permit for a pool in Dubai?' });
  assertEquals(r.status, 'answered');
  assertEquals(r.sources[0].url, url);
  const p = m.rpcs.find(([f]) => f === 'fn_reason_propose_knowledge')!;
  assertEquals((p[1].p_sources as { url: string }[])[0].url, url);
});

Deno.test('only authority hosts over https are read', () => {
  assert(authoritative('https://www.dm.gov.ae/x'));
  assert(authoritative('https://u.ae/en/information'));
  assert(!authoritative('http://www.dm.gov.ae/x'));
  assert(!authoritative('https://dm.gov.ae.evil.com/x'));
  assert(!authoritative('https://169.254.169.254/latest'));
  const html = '<a rel="nofollow" class="result__a" href="//duckduckgo.com/l/?uddg=https%3A%2F%2Fwww.dm.gov.ae%2Fpools&amp;rut=1">DM <b>pools</b></a><a class="result__a" href="https://spam.com">x</a>';
  assertEquals(parseSearchResults(html), [{ url: 'https://www.dm.gov.ae/pools', title: 'DM pools' }]);
});

Deno.test('replayHeld reasons a held row once the hold lifts and hands the result to the resolver', async () => {
  const m = mock({ replies: { decompose: [J({ steps: [{ id: 's1', goal: 'read it', needs_knowledge: false }], facts: [] })],
    synthesise: [J({ answer: 'He is halting work in flight.', decision: { choice: 'stop' } })] } });
  const out = await replayHeld(null, 3, m.deps) as { replayed: number };
  assertEquals(out.replayed, 1);
  const res = m.rpcs.find(([f]) => f === 'fn_reason_held_resolve')!;
  assertEquals(res[1].p_id, 42);
  assertEquals((res[1].p_result as { decision: { choice: string } }).decision.choice, 'stop');
  assert(!m.rpcs.some(([f]) => f === 'fn_reason_hold'), 'a replay must not re-queue itself');
});

// ── THE LEARNING LOOP: every judgement is opened by its recall and closed with what it decided ──────
Deno.test('a judgement is recorded WITH its recall record, then closed with the decision', async () => {
  const m = mock({ retrieve: KB, replies: {
    decompose: [J({ steps: [{ id: 's1', goal: 'g', query: 'q' }], facts: [], high_stakes: false })],
    synthesise: [J({ decision: { choice: 'stop' }, answer: 'The founder asks to halt the campaign now.', reasoning: ['s1: he said stop'], cited: [], confidence: 0.9 })],
  } });
  const r = await think(m.deps, { seat: 'ceo', surface: 'ceo.command_intent', question: 'stop the campaign', subject: { command_id: 7 },
    decision: { name: 'intent', options: [{ id: 'stop', meaning: 'halt work' }, { id: 'ask', meaning: 'a question' }] } });
  assertEquals(r.status, 'answered');
  const names = m.rpcs.map(([f]) => f);
  const rec = m.rpcs.find(([f]) => f === 'fn_judgement_record')!;
  assert(rec, 'no judgement row was opened');
  assert(names.indexOf('fn_case_recall') < names.indexOf('fn_judgement_record'), 'the judgement was recorded before the recall');
  assertEquals((rec[1].p_recall as { available: boolean }).available, true);
  assertEquals(rec[1].p_subject, { command_id: 7 });
  const dec = m.rpcs.find(([f]) => f === 'fn_judgement_decided')!;
  assertEquals([dec[1].p_status, dec[1].p_decision], ['answered', 'stop']);
});

Deno.test('under the model hold nothing is judged, so no judgement row is opened', async () => {
  const m = mock({ gate: { allowed: false, rule: 'founder_hold' }, replies: {} });
  const r = await think(m.deps, { seat: 'marketing', surface: 'think.answer', question: 'q' });
  assertEquals(r.status, 'held');
  assertEquals(m.rpcs.filter(([f]) => f.startsWith('fn_judgement')).length, 0);
});

Deno.test('a judgement whose model fails after the recall is closed as held, never left open', async () => {
  const m = mock({ replies: { decompose: [J({ steps: [{ id: 's1', goal: 'g', query: 'q' }], facts: [] })], synthesise: [{ content: null, error: 'boom' }] } });
  const r = await think(m.deps, { seat: 'accountant', surface: 'think.answer', question: 'is this VAT-able?' });
  assertEquals(r.status, 'held');
  assert(m.rpcs.some(([f]) => f === 'fn_judgement_record'));
  assertEquals(m.rpcs.find(([f]) => f === 'fn_judgement_decided')?.[1].p_status, 'held');
});

Deno.test('internal think() runs on the GLM class; customer, supplier and Arabic replies keep theirs (23 Sep ruling)', () => {
  for (const ph of ['decompose', 'research'] as const) for (const aud of ['internal', 'customer', 'supplier']) assertEquals(taskClassFor(ph, aud, false), 'routine_employee_reasoning');
  assertEquals(taskClassFor('synthesise', 'internal', false), 'routine_employee_reasoning');
  assertEquals(taskClassFor('synthesise', 'internal', true), 'routine_employee_reasoning');
  assertEquals(taskClassFor('synthesise', 'customer', true), 'customer_communication');
  assertEquals(taskClassFor('synthesise', 'visitor', false), 'customer_communication');
  assertEquals(taskClassFor('synthesise', 'supplier', false), 'supplier_communication');
  assertEquals(taskClassFor('synthesise', 'internal', false, 'ar'), 'customer_communication');
  assertEquals(taskClassFor('verify', 'internal', false), 'knowledge_validation');
});

Deno.test('a fixture question is held but never queued for a paid replay (e2e journey, 24 Sep 2026)', async () => {
  const HOLD = { allowed: false, rule: 'founder_hold', held: 1, routes: 8 };
  const opts = { name: 'trade', options: [{ id: 'aluminium', meaning: 'aluminium work' }, { id: 'glazing', meaning: 'glazing work' }] };
  const m = mock({ gate: HOLD, replies: {} });
  const r = await think(m.deps, { seat: 'sales_engineer', surface: 'inquiry_intake.trade', decision: opts,
    question: 'We need 40 aluminium windows', subject: { intake_id: 'x', fixture: true } });
  assertEquals(r.status, 'held');
  assert(!m.rpcs.some(([f]) => f === 'fn_reason_hold'), 'a fixture must not be filed');
  const real = mock({ gate: HOLD, replies: {} });
  await think(real.deps, { seat: 'sales_engineer', surface: 'inquiry_intake.trade', decision: opts, question: 'We need 40 aluminium windows', subject: { intake_id: 'x' } });
  assert(real.rpcs.some(([f]) => f === 'fn_reason_hold'), 'a real subject is still filed');
  assertEquals(isFixtureRequest({ subject: { intake_id: 'x' } }), false);
});
