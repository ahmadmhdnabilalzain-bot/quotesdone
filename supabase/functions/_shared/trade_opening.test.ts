// deno test --no-lock --node-modules-dir=none supabase/functions/_shared/trade_opening.test.ts
// The customer doors' question (ledger 1614): a not-open trade is a 409 in both languages; an outage is never a refusal.
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { joinIfNotOpen, notOpenAnswer, waPhone } from './trade_opening.ts';

const db = (answer: unknown, error: unknown = null) => {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  return { calls, rpc: (fn: string, args: Record<string, unknown>) => { calls.push({ fn, args }); return Promise.resolve({ data: answer, error: error as { message: string } | null }); } };
};

Deno.test('a trade that is not open is a 409 carrying both languages and the waiting list', async () => {
  const d = db({ state: 'not_open', codes: ['aluminium'], closed: [{ code: 'aluminium', verified: 2, open_at: 10 }], message: 'EN', message_en: 'EN', message_ar: 'AR', waitlisted: true });
  const g = await joinIfNotOpen(d, { slugs: ['aluminium', 'aluminium', ''], channel: 'portal', customerId: 'c1', lang: 'en', intakeId: 'i1' });
  assertEquals(g.state, 'not_open');
  assertEquals(d.calls[0].fn, 'fn_trade_waitlist_join');
  assertEquals(d.calls[0].args.p_slugs, ['aluminium']);
  assertEquals([d.calls[0].args.p_channel, d.calls[0].args.p_customer, d.calls[0].args.p_intake], ['portal', 'c1', 'i1']);
  const a = notOpenAnswer(g);
  assertEquals([a.status, a.body.code, a.body.message, a.body.message_ar, a.body.waitlisted], [409, 'trade_not_open', 'EN', 'AR', true]);
  assertEquals(a.body.trades, ['aluminium']);
});

Deno.test('an open or unclassified trade proceeds; an outage answers unknown, never not_open', async () => {
  assertEquals((await joinIfNotOpen(db({ state: 'open', codes: ['painting'], closed: [] }), { slugs: ['painting'], channel: 'portal', lang: 'en' })).state, 'open');
  assertEquals((await joinIfNotOpen(db({ state: 'unclassified', codes: [], closed: [] }), { slugs: ['general'], channel: 'portal', lang: 'en' })).state, 'unclassified');
  const out = await joinIfNotOpen(db(null, { message: 'function does not exist' }), { slugs: ['painting'], channel: 'portal', lang: 'en' });
  assertEquals(out.state, 'unknown');
  assert(out.error?.includes('does not exist'));
  const none = db({ state: 'open' });
  assertEquals((await joinIfNotOpen(none, { slugs: [], channel: 'whatsapp', lang: 'ar' })).state, 'unclassified');
  assertEquals(none.calls.length, 0, 'no trade named: nothing asked');
});

Deno.test('the WhatsApp number is keyed without its channel prefix', () => {
  assertEquals(waPhone('whatsapp:+971501234567'), '+971501234567');
  assertEquals(waPhone('971501234567'), '+971501234567');
  assertEquals(waPhone(''), '');
});
