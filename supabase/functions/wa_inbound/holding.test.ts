// The WhatsApp holding line (holding.ts, founder ruling 1636): at most once per person per quiet window, read from their history
// first, recorded in notifications the way PRODUCTION's triggers accept it, never after the reply, never on a fixture number,
// never followed by silence. Every dependency is a stub; nothing reaches Twilio.
// Final audit 12 Nov 2026 (W2, integration F1, proof p4 F-HOLDING): the row named requested_by 'wa_inbound', trigger a05 refused
// it, the error was discarded, so no holding line was ever recorded and the same sentence went before 29 of 29 replies. The
// table below refuses that row as production does; on main the first three tests fail (no row; a second line; no finding).
// Known-bad controls: without the `t.holding !== undefined` guard a second ask arms a second line; without settleHoldingFor in
// sendWa, or the settle in index.ts's finally, the hooks test fails.
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { HOLDING_LINE, HOLDING_QUIET_MIN } from '../_shared/holding_notice.ts';
// The module builds its service-role client at import (shared.ts): give it a stub host first, as the handler tests do
// (_shared/twilio_free_harness.ts). Nothing here reaches it; every dependency is passed in.
(Deno.env as unknown as { get: (k: string) => string | undefined }).get = (k) => ({ SUPABASE_URL: 'https://db.invalid', SUPABASE_SERVICE_ROLE_KEY: 'stub-service-role' } as Record<string, string>)[k];
import type { HoldingDeps } from './holding.ts';
const { armWaHolding, HOLDING_TYPE, noSilenceAfterHolding, sendHoldingLine } = await import('./holding.ts');
import type { WaTurn } from './turn.ts';

type Row = Record<string, unknown>;
// read from production 12 Nov 2026 (org_role where status = 'active'), the seats a05 accepts besides 'platform'
const SEATS = new Set(['platform', 'customer_support', 'it_engineer', 'sales_engineer', 'ceo', 'accountant', 'marketing']);
/** notifications as production's insert triggers treat a holding row: a05 refuses a requester that is not a seat; with
 *  `rehearsal`, zzz_notifications_demo_guard turns every inserted row into 'held'. The reads filter as PostgREST would. */
function fakeAdmin(o: { existing?: Row[]; rehearsal?: boolean; readFails?: boolean } = {}) {
  const rows: Row[] = [...(o.existing ?? [])];
  let next = 500;
  const admin = {
    from: (_t: string) => {
      const f: [string, string, unknown][] = [];
      let patch: Row | null = null;
      const match = (r: Row) => f.every(([op, c, v]) => op === 'eq' ? r[c] === v : op === 'gte' ? String(r[c]) >= String(v) : true);
      const q: Record<string, unknown> = {
        select: () => q, order: () => q,
        eq: (c: string, v: unknown) => { f.push(['eq', c, v]); return q; },
        gte: (c: string, v: unknown) => { f.push(['gte', c, v]); return q; },
        limit: () => Promise.resolve(o.readFails ? { data: null, error: { message: 'down' } }
          : { data: rows.filter(match).sort((a, b) => String(b.created_at).localeCompare(String(a.created_at))), error: null }),
        update: (p: Row) => { patch = p; return q; },
        then: (ok: (v: unknown) => unknown) => { if (patch) for (const r of rows.filter(match)) Object.assign(r, patch); return Promise.resolve({ data: null, error: null }).then(ok); },
        insert: (r: Row) => ({ select: () => ({ maybeSingle: () => {
          if (!SEATS.has(String(r.requested_by))) return Promise.resolve({ data: null, error: { code: '23514', message: `notifications.requested_by ${r.requested_by} is not an active seat` } });
          const row = { id: ++next, created_at: new Date().toISOString(), ...r, ...(o.rehearsal ? { status: 'held' } : {}) };
          rows.push(row);
          return Promise.resolve({ data: { id: row.id, status: row.status }, error: null });
        } }) }),
      };
      return q;
    },
  };
  return { admin, rows };
}
function deps(o: { existing?: Row[]; enabled?: boolean; typingOk?: boolean; rehearsal?: boolean; readFails?: boolean } = {}) {
  const f = fakeAdmin(o);
  const sent: { to: string; text: string }[] = [];
  const typing: string[] = [];
  const findings: string[] = [];
  const d: HoldingDeps = {
    admin: f.admin,
    setting: async (k) => (k === 'wa_autoreply_enabled' ? (o.enabled === false ? 'false' : 'true') : ''),
    send: async (to, text) => { sent.push({ to, text }); return { ok: true }; },
    typing: async (_to, sid) => { typing.push(sid); return o.typingOk === false ? { ok: false, err: '20404 not enabled' } : { ok: true }; },
    finding: (k) => { findings.push(k); return Promise.resolve(); },
  };
  return { d, rows: f.rows, sent, typing, findings };
}
const REAL = 'whatsapp:+971501234567';
const PHONE = '+971501234567';
const turn = (over: Partial<WaTurn> = {}) => ({ From: REAL, MessageSid: 'SM' + 'a'.repeat(32), receivedAt: new Date().toISOString(), timings: {}, ...over }) as unknown as WaTurn;
const tick = (ms = 20) => new Promise((r) => setTimeout(r, ms));
const ago = (min: number) => new Date(Date.now() - min * 60_000).toISOString();
const line = (body: string, min: number, status = 'sent') => ({ id: 41, type: HOLDING_TYPE, channel: 'whatsapp', to_phone: PHONE, body, status, created_at: ago(min) });

Deno.test('a slow reply: one holding line, recorded as production accepts it (requested by customer_support, no to_role)', async () => {
  const s = deps();
  const t = turn({ receivedAt: new Date(Date.now() - 20_000).toISOString() });   // already past the threshold
  const h = armWaHolding(t, 'customer', 'ar', s.d);
  armWaHolding(t, 'customer', 'ar', s.d);   // the real reply asked after a speculative draft: the same turn
  await tick();
  await h!.settle();
  assertEquals(s.sent.map((x) => x.text), [HOLDING_LINE.ar[0]]);
  const rec = s.rows.filter((r) => r.type === HOLDING_TYPE);
  assertEquals(rec.map((r) => [r.status, r.requested_by, r.to_role ?? null, r.dedupe_key]), [['sent', 'customer_support', null, 'wa_holding:SM' + 'a'.repeat(32)]]);
  assertEquals((t.timings as Record<string, unknown>).holding, 'sent');
  assertEquals(s.findings, []);
  assertEquals(s.typing.length, 2, 'the typing indicator at the ask, and again after the holding line (delivery clears it)');
});

Deno.test('once per person per quiet window: the next slow turn sends none; after the window a different wording goes', async () => {
  const s = deps();
  for (let i = 0; i < 3; i++) await sendHoldingLine(s.d, { to: REAL, lang: 'en', audience: 'customer', stillDue: () => true });
  assertEquals(s.sent.length, 1, 'three slow turns inside the window: one holding line (on main: three)');
  assertEquals(await sendHoldingLine(s.d, { to: REAL, lang: 'en', audience: 'customer', stillDue: () => true }), 'already_held');
  const later = deps({ existing: [line(HOLDING_LINE.en[0], HOLDING_QUIET_MIN + 5)] });
  assertEquals(await sendHoldingLine(later.d, { to: REAL, lang: 'en', audience: 'customer', stillDue: () => true }), 'sent');
  assertEquals(later.sent.map((x) => x.text), [HOLDING_LINE.en[1]], 'not the sentence they were given last time');
  const all = deps({ existing: [line(HOLDING_LINE.en[0], 200), line(HOLDING_LINE.en[1], 120), line(HOLDING_LINE.en[2], 60)] });
  await sendHoldingLine(all.d, { to: REAL, lang: 'en', audience: 'customer', stillDue: () => true });
  assertEquals(all.sent.map((x) => x.text), [HOLDING_LINE.en[0]], 'every wording used today: the one given longest ago');
  const failed = deps({ existing: [line(HOLDING_LINE.en[0], 2, 'failed')] });
  assertEquals(await sendHoldingLine(failed.d, { to: REAL, lang: 'en', audience: 'customer', stillDue: () => true }), 'sent', 'a line that never reached them does not count');
});

Deno.test('a refused record is the it_engineer\'s finding, never silent; a rehearsal guard\'s "held" is set back to what happened', async () => {
  const s = deps();
  const bad = { ...s.d, admin: { from: (t: string) => { const q = (s.d.admin as { from: (t: string) => Record<string, unknown> }).from(t);
    return { ...q, insert: () => ({ select: () => ({ maybeSingle: () => Promise.resolve({ data: null, error: { code: '23514', message: 'refused' } }) }) }) }; } } };
  assertEquals(await sendHoldingLine(bad as HoldingDeps, { to: REAL, lang: 'en', audience: 'customer', stillDue: () => true }), 'sent');
  assertEquals(s.findings, ['wa_inbound:holding_unrecorded']);
  const r = deps({ rehearsal: true });
  await sendHoldingLine(r.d, { to: REAL, lang: 'en', audience: 'customer', stillDue: () => true });
  assertEquals(r.rows.map((x) => x.status), ['sent'], 'a held row could be released and sent minutes later');
});

Deno.test('a fast reply: the turn is settled before the threshold and no holding line is ever sent', async () => {
  const s = deps();
  const t = turn();   // just arrived
  const h = armWaHolding(t, 'customer', 'en', s.d);
  await h!.settle();   // the reply is ready (say.ts adopt), or it left (sendWa), or the turn ended
  await tick();
  assertEquals(s.sent.length, 0);
  assertEquals(s.rows.length, 0);
});

Deno.test('a supplier is always written to in English; the founder gets no holding line', async () => {
  const s = deps();
  const t = turn({ receivedAt: new Date(Date.now() - 20_000).toISOString() });
  const h = armWaHolding(t, 'supplier', 'ar', s.d)!;
  await tick();
  await h.settle();
  assertEquals(s.sent.map((x) => x.text), [HOLDING_LINE.en[0]]);
  assertEquals(s.rows[0].lang, 'en');
  const f = deps();
  assertEquals(armWaHolding(turn({ receivedAt: new Date(Date.now() - 20_000).toISOString() }), 'founder', 'en', f.d), null);
  await tick();
  assertEquals(f.sent.length, 0);
});

Deno.test('autoreply off, a history that cannot be read, a reply that became ready meanwhile: nothing; a fixture number: captured', async () => {
  const off = deps({ enabled: false });
  assertEquals(await sendHoldingLine(off.d, { to: REAL, lang: 'en', audience: 'customer', stillDue: () => true }), 'autoreply_off');
  const blind = deps({ readFails: true });
  assertEquals(await sendHoldingLine(blind.d, { to: REAL, lang: 'en', audience: 'customer', stillDue: () => true }), 'history_unavailable');
  assertEquals(blind.sent.length, 0, 'never sent without reading whether it was already sent (ruling 1631)');
  const fx = deps();
  assertEquals(await sendHoldingLine(fx.d, { to: 'whatsapp:+971500000031', lang: 'en', audience: 'customer', stillDue: () => true }), 'fixture_captured');
  assertEquals(fx.sent.length, 0);
  assertEquals(fx.rows.map((r) => r.status), ['suppressed']);
  assertEquals(await sendHoldingLine(fx.d, { to: 'whatsapp:+971500000031', lang: 'en', audience: 'customer', stillDue: () => true }), 'already_held', 'a fixture is held once too');
  const late = deps();
  assertEquals(await sendHoldingLine(late.d, { to: REAL, lang: 'en', audience: 'customer', stillDue: () => false }), 'reply_ready');
  assertEquals(late.sent.length + late.rows.length, 0);
});

Deno.test('the typing indicator: a refusal (the beta not on the account) is recorded and changes nothing else', async () => {
  const s = deps({ typingOk: false });
  const t = turn({ receivedAt: new Date(Date.now() - 20_000).toISOString() });
  const h = armWaHolding(t, 'customer', 'en', s.d)!;
  await tick();
  await h.settle();
  assertEquals(s.sent.length, 1, 'the holding line still goes');
  assert(String((t.timings as Record<string, unknown>).typing_at_ask).includes('not enabled'));
});

Deno.test('never followed by silence: a turn that sent the line and then sent no reply is filed for the re-ask, once', async () => {
  const filed: string[] = [];
  const heldTurn = (_a: string, _l: string, _s: string, why: string) => { filed.push(why); return Promise.resolve({ notice: '', sent: false, err: null, held_id: 1 }); };
  const base = { holdingWent: true, holdingFor: { aud: 'customer', lang: 'en' as const }, heldTurn, holding: { answered: false } };
  assertEquals(await noSilenceAfterHolding(turn(base as unknown as Partial<WaTurn>)), true);
  assertEquals(filed, ['no_reply_after_holding']);
  assertEquals(await noSilenceAfterHolding(turn({ ...base, holding: { answered: true } } as unknown as Partial<WaTurn>)), false, 'a reply followed');
  assertEquals(await noSilenceAfterHolding(turn({ ...base, heldFiled: true } as unknown as Partial<WaTurn>)), false, 'already filed');
  assertEquals(await noSilenceAfterHolding(turn({ ...base, holdingWent: false } as unknown as Partial<WaTurn>)), false, 'no line went');
  assertEquals(filed.length, 1);
});

Deno.test('the hooks: armed before the model is asked, settled when the reply is ready, answered by every sendWa, closed by the turn\'s end', () => {
  const say = Deno.readTextFileSync(new URL('./say.ts', import.meta.url));
  assert(say.indexOf('armWaHolding(t, aud, lang)') > 0 && say.indexOf('armWaHolding(t, aud, lang)') < say.indexOf('await modelSays('));
  assert(/const adopt = [^\n]*\n[^\n]*\n\s*if \(r\.text\) void t\.holding\?\.settle\(\);/.test(say), 'the reply being ready settles the line');
  assert(/t\.heldFiled = true;/.test(say), 'heldTurn records that the re-ask will answer');
  const replies = Deno.readTextFileSync(new URL('./replies.ts', import.meta.url));
  const door = replies.slice(replies.indexOf('export async function sendWa('));
  assert(door.indexOf('settleHoldingFor(to);') > 0 && door.indexOf('settleHoldingFor(to);') < door.indexOf('sendWhatsApp(admin'), 'sendWa settles before it sends');
  const index = Deno.readTextFileSync(new URL('./index.ts', import.meta.url));
  assert(/finally \{[\s\S]*await t\.holding\?\.settle\(\)[\s\S]*await noSilenceAfterHolding\(t\)/.test(index), 'the turn\'s end settles it and makes sure a reply follows');
  // the holding line is the only fixed text holding.ts sends, and it is never sent on email
  const src = Deno.readTextFileSync(new URL('./holding.ts', import.meta.url));
  assertEquals([...src.matchAll(/d\.send\(([^)]*)\)/g)].map((m) => m[1]), ['o.to, text']);
  assert(/const text = holdingLine\(o\.lang, o\.audience, went\.map\(/.test(src));
  assert(/requested_by: HOLDING_REQUESTER/.test(src) && /export const HOLDING_REQUESTER = 'customer_support';/.test(src));
});
