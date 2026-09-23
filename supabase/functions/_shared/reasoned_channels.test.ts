// reasoned_channels with a MOCKED model: each channel's one decision, answered each way, held with no guess,
// and queued (or deliberately not) with the surface, dedupe key and subject its replay needs. No network, no paid call.
//
//   deno test --no-lock --node-modules-dir=auto --allow-read=. supabase/functions/_shared/reasoned_channels.test.ts
import { assert, assertEquals } from 'jsr:@std/assert@1';
import type { ThinkDeps } from './think.ts';
import { queueWhatsAppMeaning, siteQuestion, socialMeaning, socialOptions, visitorSide, whatsappMeaning, whatsappOptions } from './reasoned_channels.ts';

const J = (x: unknown) => JSON.stringify(x);
/** held: the founder's hold. choice: what the mocked model decides (it is refused and re-asked if not an option). */
function mock(o: { held?: boolean; choice?: string }) {
  const rpcs: [string, Record<string, unknown>][] = []; const prompts: string[] = [];
  const deps: ThinkDeps = {
    gate: () => Promise.resolve((o.held ? { allowed: false, rule: 'founder_hold', held: 1, routes: 8 } : { allowed: false, rule: 'route_not_registered' }) as never),
    llm: (phase, system) => {
      prompts.push(system);
      if (phase === 'decompose') return Promise.resolve({ content: J({ steps: [{ id: 's1', goal: 'read what they ask', needs_knowledge: false }], facts: [] }) });
      return Promise.resolve({ content: J({ answer: 'Read as a whole, the message asks this.', decision: { choice: o.choice } }), model: 'mock' });
    },
    embed: () => Promise.resolve(null),
    rpc: (fn, args) => { rpcs.push([fn, args]); return Promise.resolve({ data: fn === 'fn_reason_hold' ? 42 : { cases: [] }, error: null }); },
  };
  return { deps, rpcs, prompts, held: () => rpcs.filter(([f]) => f === 'fn_reason_hold').map(([, a]) => a) };
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

Deno.test('WhatsApp held: no guess, and not queued until the caller knows nothing else answered', async () => {
  const m = mock({ held: true });
  const r = await whatsappMeaning(m.deps, WA);
  assertEquals([r.value, r.result.status], [null, 'held']);
  assertEquals(m.held(), [], 'not filed on the first ask');
  const q = await queueWhatsAppMeaning(m.deps, WA);
  assertEquals(q.value, null);
  const [row] = m.held();
  assertEquals([row.p_seat, row.p_surface, row.p_dedupe_key], ['customer_support', 'wa_inbound.intent_table', 'wa_meaning:SMZZDEMO1']);
  assertEquals(row.p_subject, { channel: 'whatsapp', phone: 'whatsapp:+971500000021', message_sid: 'SMZZDEMO1' });
  // The replay re-runs the stored request: it carries every option, so the replayed choice is one of them.
  const req = row.p_request as { decision: { options: { id: string }[] } };
  assert(req.decision.options.some((x) => x.id === 'trade:hvac'));
});

Deno.test('website widget: the question and the visitor side are reasoned, and neither is ever queued (no channel to answer later)', async () => {
  for (const choice of ['size', 'cost', 'count', 'timeline', 'none']) assertEquals((await siteQuestion(mock({ choice }).deps, { message: 'q' })).value, choice);
  for (const choice of ['customer', 'supplier', 'unknown']) assertEquals((await visitorSide(mock({ choice }).deps, { conversation: 'we install chillers' })).value, choice);
  const m = mock({ held: true });
  assertEquals((await siteQuestion(m.deps, { message: 'what does it cost?' })).value, null);
  assertEquals((await visitorSide(m.deps, { conversation: 'i am a supplier' })).value, null);
  assertEquals(m.held(), [], 'an anonymous visitor cannot be answered later, so nothing is filed');
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
