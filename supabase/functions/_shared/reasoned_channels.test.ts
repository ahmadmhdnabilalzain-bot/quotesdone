// reasoned_channels with a MOCKED model: each channel's one decision, answered each way, held with no guess,
// and queued (or deliberately not) with the surface, dedupe key and subject its replay needs. No network, no paid call.
//
//   deno test --no-lock --node-modules-dir=auto --allow-read=. supabase/functions/_shared/reasoned_channels.test.ts
import { assert, assertEquals } from 'jsr:@std/assert@1';
import type { ThinkDeps } from './think.ts';
import { portalPassage, queueWhatsAppMeaning, quoteOptions, quoteQuestion, socialMeaning, socialOptions, whatsappMeaning, whatsappOptions, widgetMeaning, widgetOptions } from './reasoned_channels.ts';

const J = (x: unknown) => JSON.stringify(x);
/** held: the founder's hold. choice: what the mocked model decides (it is refused and re-asked if not an option). */
function mock(o: { held?: boolean; choice?: string }) {
  const rpcs: [string, Record<string, unknown>][] = []; const prompts: string[] = [];
  let llmCalls = 0;
  const deps: ThinkDeps = {
    gate: () => Promise.resolve((o.held ? { allowed: false, rule: 'founder_hold', held: 1, routes: 8 } : { allowed: false, rule: 'route_not_registered' }) as never),
    llm: (phase, system) => {
      prompts.push(system); llmCalls++;
      if (phase === 'decompose') return Promise.resolve({ content: J({ steps: [{ id: 's1', goal: 'read what they ask', needs_knowledge: false }], facts: [] }) });
      return Promise.resolve({ content: J({ answer: 'Read as a whole, the message asks this.', decision: { choice: o.choice } }), model: 'mock' });
    },
    embed: () => Promise.resolve(null),
    rpc: (fn, args) => { rpcs.push([fn, args]); return Promise.resolve({ data: fn === 'fn_reason_hold' ? 42 : { cases: [] }, error: null }); },
  };
  return { deps, rpcs, prompts, llm: () => llmCalls, held: () => rpcs.filter(([f]) => f === 'fn_reason_hold').map(([, a]) => a) };
}
const INTENTS = [{ intent_key: 'pricing', label: 'Fees and pricing' }, { intent_key: 'contact_human', label: 'Asking for a person, or who runs the company' }];
const TRADES = [{ code: 'hvac', label: 'HVAC & air conditioning', label_ar: 'التكييف والتهوية' }, { code: 'landscaping', label: 'Landscaping & pools' }];
const WA = { message: 'can you guys sort out my villa AC?', intents: INTENTS, trades: TRADES, phone: 'whatsapp:+971500000021', messageSid: 'SMZZDEMO1' };

Deno.test('WhatsApp: every answer the database holds is an option — intent rows, size, the list, each trade, a trade we lack, none', () => {
  const ids = whatsappOptions(INTENTS, TRADES).map((x) => x.id);
  assertEquals(ids, ['intent:pricing', 'intent:contact_human', 'size', 'coverage:list', 'trade:hvac', 'trade:landscaping', 'coverage:other', 'none']);
});

Deno.test('WhatsApp: answered each way — a trade, an intent, the size question — and never queued when answered', async () => {
  for (const choice of ['trade:hvac', 'intent:pricing', 'size', 'none']) {
    const m = mock({ choice });
    const r = await whatsappMeaning(m.deps, WA);
    assertEquals(r.value, choice);
    assertEquals(m.held(), []);
  }
  // A choice that is not an option is refused and re-asked, never passed on.
  const bad = mock({ choice: 'trade:catering' });
  assertEquals((await whatsappMeaning(bad.deps, WA)).value, null);
});

Deno.test('WhatsApp held: no guess, and filed only when the caller says nothing else answered — without a second think()', async () => {
  const m = mock({ held: true });
  const r = await whatsappMeaning(m.deps, WA);
  assertEquals([r.value, r.result.status, r.result.reason], [null, 'held', 'model_hold']);
  assertEquals(m.held(), [], 'not filed on the first ask');
  const id = await queueWhatsAppMeaning(m.deps, WA, r.result.reason!);
  assertEquals(id, 42);
  const [row] = m.held();
  assertEquals([row.p_seat, row.p_surface, row.p_dedupe_key, row.p_reason], ['customer_support', 'wa_inbound.intent_table', 'wa_meaning:SMZZDEMO1', 'model_hold']);
  assertEquals(row.p_subject, { channel: 'whatsapp', phone: 'whatsapp:+971500000021', message_sid: 'SMZZDEMO1' });
  // The replay re-runs the stored request: it carries every option, so the replayed choice is one of them.
  const req = row.p_request as { decision: { options: { id: string }[] } };
  assert(req.decision.options.some((x) => x.id === 'trade:hvac'));
});

Deno.test('WhatsApp: a reasoning that FAILED (not the hold) is filed with its reason, and no model is called a second time', async () => {
  const m = mock({ choice: 'trade:catering' });       // not an option: refused on every pass, so the reasoning fails
  const r = await whatsappMeaning(m.deps, WA);
  assertEquals(r.value, null);
  const calls = m.llm();
  assert(calls > 0);
  await queueWhatsAppMeaning(m.deps, WA, r.result.reason ?? 'failed');
  assertEquals(m.llm(), calls, 'filing the question calls no model');
  assertEquals(m.held().length, 1);
  assert(String(m.held()[0].p_reason).length > 0);
});

Deno.test('website widget: ONE think() decides the question, the passage and the side; never queued (no channel to answer later)', async () => {
  const P = [{ content: 'Warranty terms are set by each supplier.' }];
  assertEquals(widgetOptions(P, false).map((o) => o.id), ['size', 'cost', 'count', 'timeline', 'kb:0', 'none']);
  assertEquals(widgetOptions(P, true).length, 18, 'crossed with the three sides only when the side is unknown');
  for (const [choice, q, side] of [['cost', 'cost', null], ['kb:0|supplier', 'kb:0', 'supplier'], ['size|customer', 'size', 'customer'], ['none|unknown', 'none', null]] as const) {
    const m = mock({ choice });
    const r = await widgetMeaning(m.deps, { message: 'q', passages: P, askSide: choice.includes('|') });
    assertEquals([r.question, r.side], [q, side], choice);
    assertEquals(m.prompts.filter((p) => /DECISION/.test(p)).length, 1, 'one decision, one synthesis');
  }
  const h = mock({ held: true });
  const r = await widgetMeaning(h.deps, { message: 'what does it cost?', passages: P, askSide: true });
  assertEquals([r.question, r.side], [null, null]);
  assertEquals(h.held(), [], 'an anonymous visitor cannot be answered later, so nothing is filed');
});

Deno.test('portal chat: the quote field and the passage are reasoned; held, nothing is chosen and nothing queued', async () => {
  const Q = [{ id: 'q1', supplier_label: 'Supplier A', exclusions: 'scaffolding above 4m' }];
  const ids = quoteOptions(Q, 'my ceilings are 3.2 m').map((o) => o.id);
  assert(ids.includes('q:0:exclusions:applies') && ids.includes('q:0:exclusions:does_not_apply') && ids.includes('q:0:warranty') && ids.at(-1) === 'none');
  assert(!quoteOptions(Q, 'what is excluded?').map((o) => o.id).includes('q:0:exclusions:applies'), 'no figure in the question: no applicability to decide');
  assertEquals((await quoteQuestion(mock({ choice: 'q:0:warranty' }).deps, { message: 'warranty?', quotes: Q })).value, 'q:0:warranty');
  assertEquals((await portalPassage(mock({ choice: 'kb:0' }).deps, { message: 'q', passages: [{ content: 'x' }] })).value, 'kb:0');
  const h = mock({ held: true });
  assertEquals((await quoteQuestion(h.deps, { message: 'warranty?', quotes: Q })).value, null);
  assertEquals((await portalPassage(h.deps, { message: 'q', passages: [{ content: 'x' }] })).value, null);
  assertEquals(h.held(), []);
});

const LIB = [
  { key: 'pricing', priority: 10, reply_en: 'Posting a request is free.', active: true },
  { key: 'human_handoff', priority: null, reply_en: 'Passed to our team.', active: true },
  { key: 'hours', priority: 40, reply_en: 'Sunday to Thursday.', active: false },
];
const PASSAGES = [{ content: 'Warranty terms are set by each supplier.', citation: 'support:12' }];
const SOCIAL = { message: 'who sets the warranty?', library: LIB, passages: PASSAGES, platform: 'instagram', messageId: 'mZZDEMO', userId: 'ZZDEMO1' };

Deno.test('social: only active standard rows, the size statement, the three FAQs, each passage and none are options', () => {
  assertEquals(socialOptions(LIB, PASSAGES).map((x) => x.id), ['lib:pricing', 'size', 'faq:cost', 'faq:count', 'faq:timeline', 'kb:0', 'none']);
});

Deno.test('social DM: answered, held with the passages on the row for the replay; a comment is never queued', async () => {
  assertEquals((await socialMeaning(mock({ choice: 'kb:0' }).deps, SOCIAL)).value, 'kb:0');
  const m = mock({ held: true });
  assertEquals((await socialMeaning(m.deps, SOCIAL)).value, null);
  const [row] = m.held();
  assertEquals([row.p_seat, row.p_surface, row.p_dedupe_key], ['marketing', 'marketing_social.library_match', 'social_meaning:instagram:mZZDEMO']);
  assertEquals(row.p_subject, { platform: 'instagram', message_id: 'mZZDEMO', user_id: 'ZZDEMO1', passages: [{ content: PASSAGES[0].content, citation: 'support:12' }] });
  const c = mock({ held: true });
  assertEquals((await socialMeaning(c.deps, { ...SOCIAL, comment: true })).value, null);
  assertEquals(c.held(), []);
});
