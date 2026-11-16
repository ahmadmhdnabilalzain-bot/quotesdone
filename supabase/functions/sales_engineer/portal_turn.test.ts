// The portal chat turn's clock and facts (portal_turn.ts). Run: deno test supabase/functions/sales_engineer/portal_turn.test.ts
import { assert, assertEquals } from 'jsr:@std/assert';
import { CUSTOMER_SAFE, FACTS_CHARS, MAX_RECORDS, PORTAL_TURN_MS, RECORD_CHARS, customerSafe, plainLanguage, portalFacts, portalRules, wrappedReply } from './portal_turn.ts';
import type { FlagLookup } from './portal_turn.ts';
import { aiSystem } from '../_shared/ai_reply.ts';
import { MIN_CALL_MS, PER_CALL_MS, RESERVE_MS } from '../_shared/brief_answer.ts';
import { functionSource } from '../../../scripts/lib/function_sources.mjs';

const EDGE_IDLE_WALL_MS = 150_000;   // Supabase answers 504 when a function has sent nothing for 150 s

// prevented by: this test. Measured 27 Oct 2026: portal turns of 58-150 s, one a 504 at the wall.
Deno.test('the turn is bounded at under half the edge wall, and leaves room for a full stream and one more rung', () => {
  assert(PORTAL_TURN_MS <= EDGE_IDLE_WALL_MS / 2, 'PORTAL_TURN_MS ' + PORTAL_TURN_MS);
  // the reads before the call take ~2-5 s (embed bounded at 1.5 s, recall + retrieval in parallel); what is left must fit
  // a whole streamed answer plus the reserve for another model
  assert(PORTAL_TURN_MS - 5_000 >= PER_CALL_MS + RESERVE_MS - 10_000 && RESERVE_MS >= MIN_CALL_MS);
});

Deno.test('facts: their own quotes first, then at most MAX_RECORDS records of at most RECORD_CHARS each, capped in total', () => {
  const recs = Array.from({ length: 9 }, (_, i) => ({ title: 'T' + i, content: 'x'.repeat(5000), corpus: 'sales_knowledge', record_id: i }));
  const f = portalFacts({ facts: "THEIR OWN QUOTES (scoped in SQL to this customer):\n[{\"supplier_label\":\"Supplier A\"}]", passages: recs });
  assert(f.startsWith("THIS CONVERSATION'S FACTS:\nTHEIR OWN QUOTES"), f.slice(0, 80));
  assert(f.length <= FACTS_CHARS);
  assertEquals((f.match(/^\[\d\] /gm) ?? []).length <= MAX_RECORDS, true);
  for (const block of f.split(/\n\n\[\d\] /).slice(1)) assert(block.length <= RECORD_CHARS + 5);
});

Deno.test('facts: nothing to give is an empty string (the message rides alone), and a raw corpus tag is never printed', () => {
  assertEquals(portalFacts({ facts: '', passages: [] }), '');
  assertEquals(portalFacts({}), '');
  const f = portalFacts({ passages: [{ title: 'Wardrobe carcass', content: 'Moisture-resistant MDF or marine plywood.', corpus: 'agent_knowledge', record_id: 42 }] });
  assert(f.includes('Wardrobe carcass') && !f.includes('agent_knowledge') && !f.includes('42'), f);
});

Deno.test('rules: plain text for the portal, and a signed-in customer is never told to log in', () => {
  const r = portalRules();
  assert(/no markdown/.test(r) && /120 words/.test(r) && /never tell them to log in/.test(r));
});

// prevented by: these two tests. 27 Oct 2026, the first measured run of the streamed portal turn: every reply reached the
// screen as {"answer":"..."} because the shared rules (aiSystem) asked for a JSON object that only aiReply parses.
Deno.test('the streamed portal prompt asks for plain text, never the JSON object aiReply parses', () => {
  const base = { seat: 'sales_engineer' as const, channel: 'portal', audience: 'customer' as const, lang: 'en' as const, message: 'q' };
  const plain = aiSystem({ ...base, rules: portalRules(), plainText: true }, 'en');
  assert(!/Return ONE JSON object/.test(plain) && /plain text: no JSON/.test(plain), plain.slice(-300));
  assert(/Return ONE JSON object/.test(aiSystem(base, 'en')), 'aiReply callers keep their JSON contract');
});

Deno.test('a reply wrapped as JSON or in a code fence is refused; a plain sentence with braces in prose is not', () => {
  const refused = ['it wraps the reply in JSON or a code fence; write only the plain reply text'];
  assertEquals(wrappedReply('{"answer":"Plywood holds screws better.'), refused);
  assertEquals(wrappedReply('```json'), refused);
  assertEquals(wrappedReply('Plywood holds screws better than MDF.'), []);
  assertEquals(wrappedReply('Sizes are {width} by {height} on the drawing.'), []);
});

// Independent review of #1640 (27 Oct 2026): the one-call road dropped the plain-language gate (readability.ts) and fed
// fn_sales_assist's internal and unverified sales_knowledge rows to a customer prompt. Both fail on the PR's first head.
Deno.test('plain language: a long sentence or an internal term is refused and rewritten; a plain reply passes', () => {
  assertEquals(plainLanguage('Plywood holds screws better than MDF. It costs a little more.', 'en'), []);
  const long = 'This ' + 'very '.repeat(30) + 'long sentence goes on.';
  assert(plainLanguage(long, 'en').some((p) => /longer than 28 words/.test(p)));
  assert(plainLanguage('Your request is in the workflow queue.', 'en').some((p) => /jargon/.test(p)));
  assert(plainLanguage('The status is held by fn_intake_gate today.', 'en').some((p) => /internal term/.test(p)));
});

Deno.test('the portal turn applies the plain-language gate, records the score, and withholds internal or unverified records', async () => {
  const src = functionSource('sales_engineer');
  // the plain-language gate holds every sentence; the reply-language rule holds the WHOLE reply (checkWhole), never one sentence:
  // a contact line or an English spec is one sentence in the other script (review of #1830, 4 Nov 2026)
  assert(src.includes('...wrappedReply(t), ...plainLanguage(t, lang)],'), 'the check no longer runs the plain-language gate');
  assert(src.includes('checkWhole: (t: string) => replyLanguageProblems(t, lang),'), 'the reply-language rule no longer holds the whole reply');
  assert(!/\.\.\.plainLanguage\(t, lang\), \.\.\.replyLanguageProblems/.test(src), 'the reply-language rule is back on every sentence');
  assert(src.includes("admin.rpc('fn_support_reply_readability_log'"), 'the reply score is no longer recorded');
  // the records reach the facts only through customerSafe (its behaviour is the cases below)
  const at = src.indexOf('const all = await customerSafe((r.records || [])');
  assert(at > 0, 'the retrieved records no longer pass through customerSafe');
  // 16 Nov 2026: the facts are a list (his quotes, then his account and timeline: who-knows-what gap 3)
  assert(at < src.indexOf('portalFacts({ facts: [ownQuote'), 'customerSafe must run before the facts (and the known figures) are built');
});

// Independent review of #1640, second round (27 Oct 2026): the first fix covered sales_knowledge only, while ops_knowledge
// and agent_knowledge records from fn_sales_assist still reached the customer prompt and the figure check unfiltered
// (measured: 7,705 of 9,107 readable ops rows outside the customer scope, 2,077 of 2,078 readable agent rows another
// key's notes or unverified). These fail on the PR's 3fea670db head, which has no customerSafe.
const flags: Record<string, Record<string, unknown>[]> = {
  sales_knowledge: [
    { record_id: 'sk-ok', tags: ['trade:joinery'], runtime_index_eligible: true },
    { record_id: 'sk-int', tags: ['audience:internal'], runtime_index_eligible: true },
    { record_id: 'sk-inel', tags: [], runtime_index_eligible: false },
  ],
  ops_knowledge: [
    { record_id: 'op-ok', scope_type: 'category', dept_key: null, runtime_eligible: true, supersession_state: 'current', validation_status: 'author_verified' },
    { record_id: 'op-dept', scope_type: 'department', dept_key: 'sales', runtime_eligible: true, supersession_state: 'current', validation_status: 'reviewed' },
    { record_id: 'op-role', scope_type: 'role', dept_key: null, runtime_eligible: true, supersession_state: 'current', validation_status: 'reviewed' },
    { record_id: 'op-draft', scope_type: 'company', dept_key: null, runtime_eligible: true, supersession_state: 'current', validation_status: 'draft' },
    { record_id: 'op-inel', scope_type: 'company', dept_key: null, runtime_eligible: false, supersession_state: 'current', validation_status: 'validated' },
    { record_id: 'op-old', scope_type: 'company', dept_key: null, runtime_eligible: true, supersession_state: 'superseded', validation_status: 'validated' },
  ],
  agent_knowledge: [
    { id: 1, agent_key: '_global', validation_status: 'author_verified' },
    { id: 2, agent_key: '_global', validation_status: 'unvalidated' },
    { id: 3, agent_key: 'it_engineer', validation_status: 'author_verified' },
    { id: 4, agent_key: 'cat:joinery-suppliers', validation_status: 'unsourced' },
    { id: 5, agent_key: '_global', validation_status: 'quarantined' },
  ],
};
const fake: FlagLookup = (rule, ids) => Promise.resolve({ data: (flags[rule.table] ?? []).filter((f) => ids.includes(String(f[rule.key]))), error: null });
const rec = (corpus: string, record_id: string) => ({ corpus, record_id, title: corpus + ' ' + record_id, content: 'AED 999 per metre (' + record_id + ')' });

Deno.test('ops_knowledge and agent_knowledge records that are internal, ineligible or unverified never reach the facts', async () => {
  const records = [
    rec('sales_knowledge', 'sk-ok'), rec('sales_knowledge', 'sk-int'), rec('sales_knowledge', 'sk-inel'),
    ...['op-ok', 'op-dept', 'op-role', 'op-draft', 'op-inel', 'op-old'].map((i) => rec('ops_knowledge', i)),
    ...['1', '2', '3', '4', '5'].map((i) => rec('agent_knowledge', i)),
    rec('company_faq', '624'),
  ];
  const kept = await customerSafe(records, fake);
  assertEquals(kept.map((x) => x.corpus + ':' + x.record_id),
    ['sales_knowledge:sk-ok', 'ops_knowledge:op-ok', 'agent_knowledge:1', 'company_faq:624']);
  // so their text (and its figures, which briefNumbers would make "known") is not in the facts
  const facts = portalFacts({ passages: kept });
  for (const bad of ['op-dept', 'op-role', 'op-draft', 'op-inel', 'op-old', '(2)', '(3)', '(4)', '(5)', 'sk-int', 'sk-inel']) assert(!facts.includes(bad), bad);
});

Deno.test('customerSafe fails closed: an error, a throw or a missing row withholds the record, per corpus', async () => {
  const records = [rec('ops_knowledge', 'op-ok'), rec('agent_knowledge', '1'), rec('sales_knowledge', 'sk-ok'), rec('ops_knowledge', 'op-unknown')];
  const erroring: FlagLookup = (rule, ids) => rule.table === 'ops_knowledge' ? Promise.resolve({ data: null, error: { message: 'timeout' } }) : fake(rule, ids);
  assertEquals((await customerSafe(records, erroring)).map((x) => x.record_id), ['1', 'sk-ok']);
  const throwing: FlagLookup = (rule, ids) => rule.table === 'agent_knowledge' ? Promise.reject(new Error('network')) : fake(rule, ids);
  assertEquals((await customerSafe(records, throwing)).map((x) => x.record_id), ['op-ok', 'sk-ok']);
  // op-unknown has no row to read back, so it is not trusted
  assertEquals((await customerSafe(records, fake)).map((x) => x.record_id), ['op-ok', '1', 'sk-ok']);
});

Deno.test('one rule per corpus the portal reads unfiltered, and no lookup when none of them was retrieved', async () => {
  assertEquals(Object.keys(CUSTOMER_SAFE).sort(), ['agent_knowledge', 'kb_chunks', 'ops_knowledge', 'sales_knowledge', 'support_knowledge']);
  let calls = 0;
  const counting: FlagLookup = (rule, ids) => { calls++; return fake(rule, ids); };
  assertEquals((await customerSafe([rec('company_faq', '7'), rec('category_specs', 'glass'), rec('category_quote_specs', '3')], counting)).length, 3);
  assertEquals(calls, 0);
});

// Independent review, third round (27 Oct 2026). Measured on production read-only: support_knowledge had 90 of 722 rows
// tagged audience:internal (staff playbooks such as activation and win-back, sourced from founder instructions and memory)
// and kb_chunks 53 rows of agent memory, all reaching the customer prompt unfiltered; sales_knowledge's rule lacked the
// 'kind:company' and internal-source exclusions of fn_reason_retrieve's customer branch; and any corpus without a rule
// passed. These fail on b830ee0dc.
Object.assign(flags, {
  support_knowledge: [
    { record_id: 'su-ok', tags: ['area:billing'], source_ids: ['https://example.invalid/terms'], runtime_index_eligible: true },
    { record_id: 'su-int', tags: ['audience:internal'], source_ids: [], runtime_index_eligible: true },
    { record_id: 'su-mem', tags: [], source_ids: ['internal:memory/the-only-hard-rules-and-operating-doctrine.md'], runtime_index_eligible: true },
  ],
  kb_chunks: [{ id: 70, source_kind: 'standard' }, { id: 71, source_kind: 'memory' }, { id: 72, source_kind: null }],
});
flags.sales_knowledge.push(
  { record_id: 'sk-co', tags: ['kind:company'], source_ids: [], runtime_index_eligible: true },
  { record_id: 'sk-fi', tags: [], source_ids: ['internal:founder_instruction/898'], runtime_index_eligible: true },
);

Deno.test('internal support playbooks, agent memory in kb_chunks and internal-sourced sales rows never reach the facts', async () => {
  const records = [
    ...['su-ok', 'su-int', 'su-mem'].map((i) => rec('support_knowledge', i)),
    ...['70', '71', '72'].map((i) => rec('kb_chunks', i)),
    ...['sk-ok', 'sk-co', 'sk-fi'].map((i) => rec('sales_knowledge', i)),
  ];
  assertEquals((await customerSafe(records, fake)).map((x) => x.corpus + ':' + x.record_id),
    ['support_knowledge:su-ok', 'kb_chunks:70', 'sales_knowledge:sk-ok']);
});

// Founder ruling 1338 (27 Oct 2026): "Withhold from customers." kb_chunks 'generated' (1,317 model-written rows, incl.
// "Typical Cost Ranges (AED)" per trade) passed customerSafe on ae4f96913, which withheld only 'memory'. Fails there.
flags.kb_chunks.push({ id: 73, source_kind: 'generated' }, { id: 74, source_kind: 'regulation' }, { id: 75, source_kind: '' });

Deno.test('model-written kb_chunks rows (source_kind generated) never reach a customer; read sources still do', async () => {
  const records = ['70', '71', '72', '73', '74', '75'].map((i) => rec('kb_chunks', i));
  const kept = await customerSafe(records, fake);
  assertEquals(kept.map((x) => x.record_id), ['70', '74']);
  assert(!portalFacts({ passages: kept }).includes('(73)'), 'a generated row reached the facts');
  // the lookup the portal makes is by primary key and reads only source_kind
  assertEquals([CUSTOMER_SAFE.kb_chunks.key, CUSTOMER_SAFE.kb_chunks.select], ['id', 'id, source_kind']);
  // and it still fails closed: a failed kb_chunks lookup withholds every kb_chunks record
  const erroring: FlagLookup = (rule, ids) => rule.table === 'kb_chunks' ? Promise.resolve({ data: null, error: { message: 'timeout' } }) : fake(rule, ids);
  assertEquals(await customerSafe(records, erroring), []);
});

Deno.test('a corpus with no rule and no pass-through entry is withheld, not trusted', async () => {
  assertEquals(await customerSafe([rec('ceo_knowledge', 'x'), rec('', 'y'), rec('company_faq', '1')], fake), [rec('company_faq', '1')]);
});
