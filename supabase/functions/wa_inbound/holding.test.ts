// The WhatsApp holding line (holding.ts, founder ruling 1636): once per turn, never after the reply, through the outbox's
// duplicate guard, recorded in notifications, never on a fixture number. Every dependency is a stub; nothing reaches Twilio.
// Known-bad controls: without the `t.holding !== undefined` guard a second ask arms a second line (the 'once' test sends 2);
// without settleHoldingFor in sendWa, or the settle in index.ts's finally, the last test fails (the door and the turn's end).
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { HOLDING_LINE } from '../_shared/holding_notice.ts';
// The module builds its service-role client at import (shared.ts): give it a stub host first, as the handler tests do
// (_shared/twilio_free_harness.ts). Nothing here reaches it; every dependency is passed in.
(Deno.env as unknown as { get: (k: string) => string | undefined }).get = (k) => ({ SUPABASE_URL: 'https://db.invalid', SUPABASE_SERVICE_ROLE_KEY: 'stub-service-role' } as Record<string, string>)[k];
import type { HoldingDeps } from './holding.ts';
const { armWaHolding, HOLDING_TYPE, sendHoldingLine } = await import('./holding.ts');
import type { WaTurn } from './turn.ts';

type Row = Record<string, unknown>;
/** A notifications table in memory: the reads recentSends makes, and inserts. */
function fakeAdmin(existing: Row[] = []) {
  const rows: Row[] = [...existing];
  const admin = {
    from: (_t: string) => {
      const q = {
        select: () => q, in: () => q, gte: () => q, eq: () => q,
        limit: () => Promise.resolve({ data: rows.filter((r) => ['sent', 'sending'].includes(String(r.status))), error: null }),
        insert: (r: Row) => { rows.push(r); return Promise.resolve({ data: null, error: null }); },
      };
      return q;
    },
  };
  return { admin, rows };
}
function deps(o: { existing?: Row[]; enabled?: boolean; typingOk?: boolean } = {}) {
  const f = fakeAdmin(o.existing);
  const sent: { to: string; text: string }[] = [];
  const typing: string[] = [];
  const d: HoldingDeps = {
    admin: f.admin,
    setting: async (k) => (k === 'wa_autoreply_enabled' ? (o.enabled === false ? 'false' : 'true') : ''),
    send: async (to, text) => { sent.push({ to, text }); return { ok: true }; },
    typing: async (_to, sid) => { typing.push(sid); return o.typingOk === false ? { ok: false, err: '20404 not enabled' } : { ok: true }; },
  };
  return { d, rows: f.rows, sent, typing };
}
const REAL = 'whatsapp:+971501234567';
const turn = (over: Partial<WaTurn> = {}) => ({ From: REAL, MessageSid: 'SM' + 'a'.repeat(32), receivedAt: new Date().toISOString(), timings: {}, ...over }) as unknown as WaTurn;
const tick = (ms = 20) => new Promise((r) => setTimeout(r, ms));

Deno.test('a slow reply: one holding line, in the person\'s language, recorded sent; a second ask in the same turn arms nothing', async () => {
  const s = deps();
  const t = turn({ receivedAt: new Date(Date.now() - 10_000).toISOString() });   // already past 9 s
  const h = armWaHolding(t, 'customer', 'ar', s.d);
  armWaHolding(t, 'customer', 'ar', s.d);   // the real reply asked after a speculative draft: the same turn
  await tick();
  await h!.settle();
  assertEquals(s.sent.map((x) => x.text), [HOLDING_LINE.ar]);
  assertEquals(s.rows.filter((r) => r.type === HOLDING_TYPE).map((r) => r.status), ['sent']);
  assertEquals((t.timings as Record<string, unknown>).holding, 'sent');
  assertEquals(s.typing.length, 2, 'the typing indicator at the ask, and again after the holding line (delivery clears it)');
});

Deno.test('a fast reply: the turn is settled before 9 s and no holding line is ever sent', async () => {
  const s = deps();
  const t = turn();   // just arrived: due in 9 s
  const h = armWaHolding(t, 'customer', 'en', s.d);
  await h!.settle();   // the reply left (sendWa settles it), or the turn ended
  await tick();
  assertEquals(s.sent.length, 0);
  assertEquals(s.rows.length, 0);
});

Deno.test('a supplier is always written to in English; the founder gets no holding line', async () => {
  const s = deps();
  const t = turn({ receivedAt: new Date(Date.now() - 10_000).toISOString() });
  const h = armWaHolding(t, 'supplier', 'ar', s.d)!;
  await tick();
  await h.settle();
  assertEquals(s.sent.map((x) => x.text), [HOLDING_LINE.en]);
  const f = deps();
  assertEquals(armWaHolding(turn({ receivedAt: new Date(Date.now() - 10_000).toISOString() }), 'founder', 'en', f.d), null);
  await tick();
  assertEquals(f.sent.length, 0);
});

Deno.test('the outbox duplicate guard applies: the same line to the same person inside the window is recorded cancelled, not sent', async () => {
  const earlier = { id: 41, channel: 'whatsapp', type: HOLDING_TYPE, to_phone: '+971501234567', subject: null, body: HOLDING_LINE.en, status: 'sent', created_at: new Date(Date.now() - 60_000).toISOString(), sent_at: new Date(Date.now() - 60_000).toISOString() };
  const s = deps({ existing: [earlier] });
  const what = await sendHoldingLine(s.d, { to: REAL, lang: 'en', audience: 'customer', stillDue: () => true });
  assertEquals(what, 'duplicate');
  assertEquals(s.sent.length, 0);
  const rec = s.rows.find((r) => r.type === HOLDING_TYPE && r.status === 'cancelled');
  assert(rec && /notification #41/.test(String(rec.last_error)), 'the refusal names the earlier row');
});

Deno.test('autoreply off: nothing; a fixture number: captured, never sent; a reply that left meanwhile: nothing', async () => {
  const off = deps({ enabled: false });
  assertEquals(await sendHoldingLine(off.d, { to: REAL, lang: 'en', audience: 'customer', stillDue: () => true }), 'autoreply_off');
  const fx = deps();
  assertEquals(await sendHoldingLine(fx.d, { to: 'whatsapp:+971500000031', lang: 'en', audience: 'customer', stillDue: () => true }), 'fixture_captured');
  assertEquals(fx.sent.length, 0);
  assertEquals(fx.rows.map((r) => r.status), ['suppressed']);
  const late = deps();
  assertEquals(await sendHoldingLine(late.d, { to: REAL, lang: 'en', audience: 'customer', stillDue: () => false }), 'reply_ready');
  assertEquals(late.sent.length + late.rows.length, 0);
});

Deno.test('the typing indicator: a refusal (the beta not on the account) is recorded and changes nothing else', async () => {
  const s = deps({ typingOk: false });
  const t = turn({ receivedAt: new Date(Date.now() - 10_000).toISOString() });
  const h = armWaHolding(t, 'customer', 'en', s.d)!;
  await tick();
  await h.settle();
  assertEquals(s.sent.length, 1, 'the holding line still goes');
  assert(String((t.timings as Record<string, unknown>).typing_at_ask).includes('not enabled'));
});

Deno.test('the hook sits before the model is asked, and every sendWa settles the line; the turn\'s end settles it too', () => {
  const say = Deno.readTextFileSync(new URL('./say.ts', import.meta.url));
  assert(say.indexOf('armWaHolding(t, aud, lang)') > 0 && say.indexOf('armWaHolding(t, aud, lang)') < say.indexOf('await modelSays('));
  const replies = Deno.readTextFileSync(new URL('./replies.ts', import.meta.url));
  const door = replies.slice(replies.indexOf('export async function sendWa('));
  assert(door.indexOf('settleHoldingFor(to);') > 0 && door.indexOf('settleHoldingFor(to);') < door.indexOf('sendWhatsApp(admin'), 'sendWa settles before it sends');
  const index = Deno.readTextFileSync(new URL('./index.ts', import.meta.url));
  assert(/finally \{[\s\S]*await t\.holding\?\.settle\(\)/.test(index), 'the turn\'s end settles it');
  // the holding line is the only fixed text holding.ts sends, and it is never sent on email
  const src = Deno.readTextFileSync(new URL('./holding.ts', import.meta.url));
  assertEquals([...src.matchAll(/d\.send\(([^)]*)\)/g)].map((m) => m[1]), ['o.to, text']);
  assert(/const text = holdingLine\(o\.lang, o\.audience\);/.test(src));
});
