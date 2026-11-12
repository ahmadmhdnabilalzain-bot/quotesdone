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
const { armWaHolding, holdingClaimKey, HOLDING_TYPE, liveSend, noSilenceAfterHolding, sendHoldingLine } = await import('./holding.ts');
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
        insert: (r: Row) => ({ select: () => ({ maybeSingle: async () => {
          await new Promise((res) => setTimeout(res, 5));   // a database round trip: another turn can run in between
          if (!SEATS.has(String(r.requested_by))) return { data: null, error: { code: '23514', message: `notifications.requested_by ${r.requested_by} is not an active seat` } };
          // notifications_dedupe_key_uidx (partial unique index on dedupe_key, production)
          if (r.dedupe_key != null && rows.some((x) => x.dedupe_key === r.dedupe_key)) return { data: null, error: { code: '23505', message: 'duplicate key value violates unique constraint "notifications_dedupe_key_uidx"' } };
          const row = { id: ++next, created_at: new Date().toISOString(), ...r, ...(o.rehearsal ? { status: 'held' } : {}) };
          rows.push(row);
          return { data: { id: row.id, status: row.status }, error: null };
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

// review round 2: requested by 'platform' (a05 accepts it; z90 then files no delivery.request, so no 'sent_unconfirmed' CEO report)
Deno.test('a slow reply: one holding line, recorded as production accepts it (requested by platform, sent by customer_support, no to_role)', async () => {
  const s = deps();
  const t = turn({ receivedAt: new Date(Date.now() - 20_000).toISOString() });   // already past the threshold
  const h = armWaHolding(t, 'customer', 'ar', s.d);
  armWaHolding(t, 'customer', 'ar', s.d);   // the real reply asked after a speculative draft: the same turn
  await tick();
  await h!.settle();
  assertEquals(s.sent.map((x) => x.text), [HOLDING_LINE.ar[0]]);
  const rec = s.rows.filter((r) => r.type === HOLDING_TYPE);
  assertEquals(rec.map((r) => [r.status, r.requested_by, r.to_role ?? null, r.dedupe_key]), [['sent', 'platform', null, holdingClaimKey(PHONE, Date.now())]]);
  assertEquals(rec[0].sender, 'customer_support');
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
  // the claim is the record (review of 12 Nov 2026): no claim, no send; a missing line is better than a second one
  assertEquals(await sendHoldingLine(bad as HoldingDeps, { to: REAL, lang: 'en', audience: 'customer', stillDue: () => true }), 'unrecorded');
  assertEquals(s.sent.length, 0);
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
  // review of 12 Nov 2026: answered only when the send was delivered (or captured on a fixture), so a failed send is re-asked
  assert(/if \(r\.ok \|\| r\.err === FIXTURE_CAPTURE_NOTE\) \{ answeredHoldingFor\(to\);/.test(door) && door.indexOf('answeredHoldingFor(to)') > door.indexOf('sendWhatsApp(admin'));
  const index = Deno.readTextFileSync(new URL('./index.ts', import.meta.url));
  assert(/finally \{[\s\S]*await t\.holding\?\.settle\(\)[\s\S]*await noSilenceAfterHolding\(t\)/.test(index), 'the turn\'s end settles it and makes sure a reply follows');
  // the holding line is the only fixed text holding.ts sends, and it is never sent on email
  const src = Deno.readTextFileSync(new URL('./holding.ts', import.meta.url));
  assertEquals([...src.matchAll(/d\.send\(([^)]*)\)/g)].map((m) => m[1]), ['o.to, text']);
  // review round 2: the live send is straight to Twilio, never through sendWa (which would count the line as its own answer)
  assert(/export const liveSend = \(db: Admin\) => \(to: string, text: string\) => sendWhatsApp\(db, to, text\);/.test(src) && /send: liveSend\(admin\)/.test(src)
    && !/from '\.\/replies\.ts'/.test(src));
  assert(/const text = holdingLine\(o\.lang, o\.audience, went\.map\(/.test(src));
  assert(/requested_by: HOLDING_REQUESTER/.test(src) && /export const HOLDING_REQUESTER = 'platform';/.test(src));
});

// Review of 12 Nov 2026 (BLOCKING, probe race.test.ts): attachments are never merged into a burst, so two photos sent together
// are two turns whose holding lines fall due in the same second. Read-send-record let both send. The claim row comes first,
// under a key unique per person and window. Fails on 1e8378c59 (2 lines, same wording).
Deno.test('two turns of one person due together: one holding line, the other turn finds the claim', async () => {
  const s = deps();
  const a = sendHoldingLine(s.d, { to: REAL, lang: 'en', audience: 'customer', stillDue: () => true });
  const b = sendHoldingLine(s.d, { to: REAL, lang: 'en', audience: 'customer', stillDue: () => true });
  assertEquals((await Promise.all([a, b])).sort(), ['already_held', 'sent']);
  assertEquals(s.sent.length, 1);
  assertEquals(s.rows.map((r) => r.status), ['sent'], 'the claimed row carries the outcome');
  const late = deps();
  let due = true;
  const p = sendHoldingLine(late.d, { to: REAL, lang: 'en', audience: 'customer', stillDue: () => due });
  await new Promise((r) => setTimeout(r, 1)); due = false;   // the reply becomes ready while the claim is written
  assertEquals(await p, 'reply_ready');
  assertEquals([late.sent.length, late.rows.map((r) => r.status)], [0, ['cancelled']]);
});

// Review round 2 (12 Nov 2026, BLOCKING, probe self_answer.test.ts): the holding line went through sendWa, which counts a delivered
// send as the answer, so the line answered itself and a turn that then died was never re-asked. Driven here through the REAL
// transport (holding.ts liveSend -> _shared/wa_send.ts sendWhatsApp), with fetch stubbed only at api.twilio.com.
Deno.test('the holding line never answers itself: a turn that dies after it is still re-asked', async () => {
  const s = deps();
  const twilio: string[] = [];
  const realFetch = globalThis.fetch;
  globalThis.fetch = ((input: RequestInfo | URL, init?: RequestInit) => {
    const u = new URL(typeof input === 'string' ? input : input instanceof URL ? input.href : input.url);
    if (u.hostname !== 'api.twilio.com') return Promise.reject(new Error('unexpected request: ' + u.href));
    twilio.push(String(init?.body ?? ''));
    return Promise.resolve(new Response(JSON.stringify({ sid: 'SM' + 'b'.repeat(32), status: 'queued' }), { status: 201, headers: { 'content-type': 'application/json' } }));
  }) as typeof fetch;
  try {
    // the Twilio settings sendWhatsApp reads from app_secrets
    const secrets = { from: (_t: string) => { const q: Record<string, unknown> = { select: () => q, eq: (_c: string, k: string) => { q.k = k; return q; },
      maybeSingle: () => Promise.resolve({ data: { value: ({ twilio_account_sid: 'ACzz', twilio_api_key_sid: 'SKzz', twilio_api_key_secret: 'zz', twilio_wa_from: '+14155550100' } as Record<string, string>)[String(q.k)] ?? '' }, error: null }) }; return q; } };
    let filed = 0;
    const d: HoldingDeps = { ...s.d, send: liveSend(secrets) };
    const t = turn({ receivedAt: new Date(Date.now() - 20_000).toISOString(),
      heldTurn: () => { filed++; return Promise.resolve({ notice: '', sent: false, err: null, held_id: 1 }); } } as unknown as Partial<WaTurn>);
    armWaHolding(t, 'customer', 'en', d);
    await tick(60);
    await t.holding!.settle();
    assertEquals(twilio.length, 1, 'the holding line reached (stubbed) Twilio');
    assert(t.holdingWent, 'the line went');
    assert(!t.holding!.answered, 'the line counted as its own answer');
    assertEquals([await noSilenceAfterHolding(t), filed], [true, 1], 'a turn that died after the line is re-asked once');
  } finally { globalThis.fetch = realFetch; }
});

// Review round 2 (BLOCKING): the line went through sendWa, which counts a delivered send as the answer, so the line answered
// itself. The live send is now straight to Twilio (the hooks test pins it). Review round 3 (probe reply_during_own_send.test.ts):
// a REAL reply delivered while the line's own send is still in flight must count as the answer, or a second answer follows a
// minute later from the re-ask. Fails on b9a84d502 (the ownSend guard dropped it).
Deno.test('a reply delivered while the holding line is still being sent is the answer: no re-ask', async () => {
  const { answeredHoldingFor, settleHoldingFor } = await import('../_shared/holding_notice.ts');
  const s = deps();
  let filed = 0;
  const d: HoldingDeps = { ...s.d, send: async (to, text) => { await new Promise((r) => setTimeout(r, 200)); return await s.d.send(to, text); } };
  const t = turn({ receivedAt: new Date(Date.now() - 20_000).toISOString(),
    heldTurn: () => { filed++; return Promise.resolve({ notice: '', sent: false, err: null, held_id: 1 }); } } as unknown as Partial<WaTurn>);
  armWaHolding(t, 'customer', 'en', d);
  await tick(60);
  settleHoldingFor(REAL); answeredHoldingFor(REAL);   // replies.ts sendWa for the real reply, Twilio accepted it
  await t.holding!.settle();
  assert(t.holdingWent && t.holding!.answered);
  assertEquals([await noSilenceAfterHolding(t), filed], [false, 0]);
});

// Review round 2 (SHOULD FIX D): a 'failed' WhatsApp row is re-sent by SMS (send_whatsapp), and a holding line by SMS minutes later
// is worse than none. A line that could not be sent is recorded 'cancelled' with its reason. Fails on 81f76e7d5 ('failed').
Deno.test('a holding line Twilio refused is recorded cancelled, never failed (no SMS re-send)', async () => {
  const s = deps();
  const d: HoldingDeps = { ...s.d, send: () => Promise.resolve({ ok: false, err: '63016 outside the window' }) };
  assertEquals(await sendHoldingLine(d, { to: REAL, lang: 'en', audience: 'customer', stillDue: () => true }), 'failed');
  assertEquals(s.rows.map((r) => r.status), ['cancelled']);
  assert(/never retried/.test(String(s.rows[0].last_error)) && /63016/.test(String(s.rows[0].last_error)));
});
