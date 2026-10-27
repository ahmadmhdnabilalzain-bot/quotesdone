// The portal chat turn's clock and facts (portal_turn.ts). Run: deno test supabase/functions/sales_engineer/portal_turn.test.ts
import { assert, assertEquals } from 'jsr:@std/assert';
import { FACTS_CHARS, MAX_RECORDS, PORTAL_TURN_MS, RECORD_CHARS, plainLanguage, portalFacts, portalRules, wrappedReply } from './portal_turn.ts';
import { aiSystem } from '../_shared/ai_reply.ts';
import { MIN_CALL_MS, PER_CALL_MS, RESERVE_MS } from '../_shared/brief_answer.ts';

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
  const src = await Deno.readTextFile(new URL('./index.ts', import.meta.url));
  assert(src.includes('...wrappedReply(t), ...plainLanguage(t, lang)]'), 'the check no longer runs the plain-language gate');
  assert(src.includes("admin.rpc('fn_support_reply_readability_log'"), 'the reply score is no longer recorded');
  assert(src.includes("(f.tags ?? []).includes('audience:internal') || f.runtime_index_eligible === false"), 'internal / unverified rows are no longer withheld');
  assert(src.includes('let withheld = new Set<string>(skIds);'), 'a failed lookup must withhold every sales_knowledge record (fail closed)');
});
