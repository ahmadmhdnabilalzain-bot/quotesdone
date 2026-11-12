// The turn gate (burst.ts): several WhatsApp messages in a few seconds get ONE reply, decided by conditional claims on the
// wa_messages arrival rows (so two edge workers can never both answer one message); a loop with an auto-responder stops.
// The database is an in-memory wa_messages that applies the same filters PostgREST would. Nothing reaches a model or Twilio.
// Known-bad controls, both run on 11 Nov 2026: without the conditional claim (stage 'received' and burst unset) the race test
// fails (the leader takes a message another turn had claimed); without the follower rule the three-message test fails (two answers).
import { assert, assertEquals } from 'jsr:@std/assert@1';
// The module builds its service-role client at import (shared.ts): give it a stub host first, as the handler tests do
// (_shared/twilio_free_harness.ts). Nothing here reaches it; every dependency is passed in.
(Deno.env as unknown as { get: (k: string) => string | undefined }).get = (k) => ({ SUPABASE_URL: 'https://db.invalid', SUPABASE_SERVICE_ROLE_KEY: 'stub-service-role' } as Record<string, string>)[k];
import type { GateDeps } from './burst.ts';
const { joinBurst, loopHeld, turnGate } = await import('./burst.ts');
import type { WaTurn } from './turn.ts';

type Row = { id: number; wa_from: string; created_at: string; inbound: string; reply: string; sent: boolean; replied_at: string | null; meta: Record<string, unknown> };
function db(beforeUpdate?: (id: number, rows: Row[]) => void) {
  const rows: Row[] = [];
  let next = 100;
  const admin = {
    from: (_t: string) => {
      const f: { col: string; op: string; v: unknown }[] = [];
      let patch: Record<string, unknown> | null = null;
      const val = (r: Row, col: string) => col.startsWith('meta->>') ? (r.meta[col.slice(7)] ?? null) : (r as unknown as Record<string, unknown>)[col];
      const match = (r: Row) => f.every((c) => c.op === 'eq' ? String(val(r, c.col)) === String(c.v)
        : c.op === 'gte' ? String(val(r, c.col)) >= String(c.v) : c.op === 'is' ? val(r, c.col) == null : true);
      const q: Record<string, unknown> = {
        select: () => q, order: () => q,
        eq: (col: string, v: unknown) => { f.push({ col, op: 'eq', v }); return q; },
        gte: (col: string, v: unknown) => { f.push({ col, op: 'gte', v }); return q; },
        is: (col: string, v: unknown) => { f.push({ col, op: 'is', v }); return q; },
        update: (p: Record<string, unknown>) => { patch = p; return q; },
        limit: () => Promise.resolve({ data: rows.filter(match).map((r) => structuredClone(r)), error: null }),
        then: (ok: (v: unknown) => unknown) => {
          if (patch) { const id = f.find((c) => c.col === 'id')?.v; if (id != null) beforeUpdate?.(Number(id), rows); const hit = rows.filter(match); for (const r of hit) Object.assign(r, structuredClone(patch)); return Promise.resolve({ data: hit.map((r) => ({ id: r.id })), error: null }).then(ok); }
          return Promise.resolve({ data: rows.filter(match), error: null }).then(ok);
        },
      };
      return q;
    },
  };
  const arrive = (from: string, inbound: string, o: Partial<Row> = {}) => {
    const r: Row = { id: ++next, wa_from: from, created_at: new Date().toISOString(), inbound, reply: '', sent: false, replied_at: null,
      meta: { stage: 'received', media: 0, message_sid: 'SM' + String(next).padStart(32, '0') }, ...o };
    rows.push(r); return r;
  };
  return { admin, rows, arrive };
}
const deps = (admin: unknown, quiet = '300', findings: string[] = []): GateDeps => ({
  admin, setting: async (k) => (k === 'wa_burst_quiet_ms' ? quiet : k === 'twilio_wa_from' ? 'whatsapp:+14155550100' : ''),
  finding: async (k) => { findings.push(k); }, sleep: (ms) => new Promise((r) => setTimeout(r, ms)), now: () => Date.now(), isFounder: () => Promise.resolve(false),
});
const A = 'whatsapp:+971500000061';
function turnFor(r: { id: number; created_at: string; inbound: string; meta: Record<string, unknown> }, o: Partial<WaTurn> = {}): WaTurn {
  return { From: A, Body: r.inbound, MessageSid: String(r.meta.message_sid), receivedAt: r.created_at, arrivalId: r.id, media: [], ListId: '', ButtonPayload: '',
    internalCaller: false, logRun: async () => {}, ...o } as unknown as WaTurn;
}
const wait = (ms: number) => new Promise((r) => setTimeout(r, ms));

Deno.test('three messages in under a second: ONE turn answers all three, in order; the other two end without a reply', async () => {
  const w = db();
  const turns: WaTurn[] = [];
  const outcomes: Promise<string>[] = [];
  for (const text of ['hi', 'I need a quote', 'for 12 aluminium windows']) {
    const t = turnFor(w.arrive(A, text));
    turns.push(t);
    outcomes.push(joinBurst(t, deps(w.admin)));
    await wait(150);
  }
  const res = await Promise.all(outcomes);
  assertEquals(res.filter((x) => x === 'answer').length, 1, JSON.stringify(res));
  const lead = turns[res.indexOf('answer')];
  assertEquals(lead.Body, 'hi\nI need a quote\nfor 12 aluminium windows');
  assertEquals(lead.burst?.merged.length, 2);
  assertEquals(w.rows.filter((r) => r.meta.stage === 'merged').every((r) => r.meta.merged_into === lead.arrivalId), true);
  assert(turns.filter((t) => t !== lead).every((t) => t.arrivalId === null), 'a merged turn leaves its row to the leader');
});

Deno.test('a message alone waits the quiet time and is answered as it was written', async () => {
  const w = db();
  const t = turnFor(w.arrive(A, 'what are your fees?'));
  const t0 = Date.now();
  assertEquals(await joinBurst(t, deps(w.admin)), 'answer');
  assert(Date.now() - t0 >= 250, 'it waited for a second message');
  assertEquals(t.Body, 'what are your fees?');
  assertEquals(t.burst, undefined);
});

Deno.test('a document is never merged into a text, nor waits; quiet 0 turns the wait off', async () => {
  const w = db();
  const text = turnFor(w.arrive(A, 'here is my licence'));
  const docRow = w.arrive(A, '', { meta: { stage: 'received', media: 1, message_sid: 'SMdoc' } });
  const doc = turnFor(docRow, { media: [{ url: 'https://api.twilio.com/x', mime: 'application/pdf' }] });
  const [a, b] = await Promise.all([joinBurst(text, deps(w.admin)), joinBurst(doc, deps(w.admin))]);
  assertEquals([a, b], ['answer', 'answer']);
  assertEquals(text.Body, 'here is my licence');
  const off = db();
  const t = turnFor(off.arrive(A, 'hi'));
  const t0 = Date.now();
  assertEquals(await joinBurst(t, deps(off.admin, '0')), 'answer');
  assert(Date.now() - t0 < 100);
});

Deno.test('a claim the database does not confirm never ends a turn silently: it answers alone', async () => {
  const w = db();
  const t = turnFor(w.arrive(A, 'hello'));
  w.rows[0].meta.stage = 'escalated';   // the sweep took it first
  assertEquals(await joinBurst(t, deps(w.admin)), 'answer');
});

Deno.test('the loop cap: three of our replies to an auto-responder inside the hour stop the fourth, and it is flagged', async () => {
  const w = db();
  const auto = 'Thank you for contacting us. We have received your message and our team will get back to you shortly.';
  const at = (min: number) => new Date(Date.now() - min * 60_000).toISOString();
  w.rows.push({ id: 1, wa_from: A, created_at: at(50), inbound: 'Hello, do you supply glass?', reply: 'Yes, we do...', sent: true, replied_at: at(49), meta: { stage: 'handled' } });
  w.rows.push({ id: 2, wa_from: A, created_at: at(40), inbound: auto, reply: 'Thank you...', sent: true, replied_at: at(39), meta: { stage: 'handled' } });
  w.rows.push({ id: 3, wa_from: A, created_at: at(30), inbound: auto, reply: 'Happy to help...', sent: true, replied_at: at(29), meta: { stage: 'handled' } });
  const now = w.arrive(A, auto);
  const findings: string[] = [];
  const inserted: Record<string, unknown>[] = [];
  const t = turnFor(now, { waInsert: async (_r: string, row: Record<string, unknown>) => { inserted.push(row); return {}; } } as Partial<WaTurn>);
  assertEquals((await loopHeld(t, deps(w.admin, '0'))).held, true);
  const r = await turnGate(t, deps(w.admin, '0', findings));
  assert(r instanceof Response);
  assertEquals(findings, ['wa_inbound:auto_reply_loop']);
  assertEquals((inserted[0].meta as Record<string, unknown>).no_autoreply_reason, 'auto_reply_loop');
  // a person writing in between: answered as usual
  const h = turnFor(w.arrive(A, 'sorry, that was our system. Yes, 4 mm clear glass please'));
  assertEquals((await loopHeld(h, deps(w.admin, '0'))).held, false);
});

Deno.test('the gate runs after the arrival and before the reply is composed (index.ts)', () => {
  const src = Deno.readTextFileSync(new URL('./index.ts', import.meta.url));
  const i = src.indexOf('await turnGate(t)');
  assert(i > src.indexOf('await acceptArrival(t, req)') && i < src.indexOf('makeSay(t)'));
});

Deno.test('the history a later turn reads shows a burst once: the leader carries every message, the merged rows are skipped', async () => {
  const { waConversation } = await import('../_shared/wa_history.ts');
  const rows = [
    { inbound: 'hi\nI need a quote\nfor 12 aluminium windows', reply: 'Happy to help...', sent: true, meta: { stage: 'handled' } },
    { inbound: 'I need a quote', reply: '', sent: false, meta: { stage: 'merged', merged_into: 1 } },
    { inbound: 'for 12 aluminium windows', reply: '', sent: false, meta: { stage: 'merged', merged_into: 1 } },
  ];
  const q: Record<string, unknown> = {};
  for (const k of ['select', 'eq', 'lt', 'order']) q[k] = () => q;
  q.limit = () => Promise.resolve({ data: [...rows].reverse(), error: null });
  const conv = await waConversation({ from: () => q }, A, new Date().toISOString());
  assertEquals(conv.map((c) => c.text), ['hi\nI need a quote\nfor 12 aluminium windows', 'Happy to help...']);
});

Deno.test('two turns reaching for one message: only the conditional claim that the database confirms takes it', async () => {
  // B's own turn claims B a moment before the leader's claim lands (a second worker): the leader must not take B as well
  let bId = 0;
  const w = db((id, rows) => { if (id === bId) { const b = rows.find((r) => r.id === bId)!; b.meta = { ...b.meta, burst: 'lead' }; } });
  const a = turnFor(w.arrive(A, 'hi'));
  bId = w.arrive(A, 'I need a quote').id;
  assertEquals(await joinBurst(a, deps(w.admin)), 'answer');
  assertEquals(a.Body, 'hi', 'the leader did not take a message another turn had claimed');
  assertEquals(w.rows.find((r) => r.id === bId)!.meta.stage, 'received');
});

// Final audit 12 Nov 2026, integration F7 (proof p2_burst): the leader claimed two later messages and its worker then died. The
// merged rows are skipped by the history and the sweep hands over the leader's row, which held "hi" only. Fails on main.
Deno.test('a leader that dies after claiming the burst leaves every message on its own row (the sweep and the history see all three)', async () => {
  const w = db();
  const texts = ['hi', 'I need 12 aluminium windows for a villa in Jumeirah', 'they must be delivered before 20 November'];
  const out: Promise<string>[] = [];
  for (const x of texts) { out.push(joinBurst(turnFor(w.arrive(A, x)), deps(w.admin))); await wait(100); }
  assertEquals(await Promise.all(out), ['answer', 'merged', 'merged']);
  // the leader's turn ends here without writing its row (killed): what does the row say?
  const lead = w.rows[0];
  assertEquals(lead.meta.stage, 'received', 'still for the sweep');
  assertEquals(lead.inbound, texts.join('\n'), 'the leader row holds every merged message');
});

// Final audit 12 Nov 2026, W5 / integration F7: unpinned, an arrival row was written 1.1-1.6 s after its receipt stamp, so the
// leader deciding at +quiet missed the next message and "Hi" was answered alone. A turn whose own row was written late looks once
// more after that long before it claims. Fails on main (the second message is answered on its own).
Deno.test('a row written late (the turn ran far from the database) still joins the burst', async () => {
  const w = db();
  const first = w.arrive(A, 'Hi');
  const lead = joinBurst(turnFor(first, { arrivalLagMs: 1_200 } as Partial<WaTurn>), deps(w.admin));
  // the second message was received 200 ms after the first, but its row lands 1.2 s late: after the leader's quiet (300 ms) ran out
  await wait(700);
  const second = w.arrive(A, 'I need quotes for aluminium windows', { created_at: new Date(Date.parse(first.created_at) + 200).toISOString() });
  const follow = joinBurst(turnFor(second, { arrivalLagMs: 1_200 } as Partial<WaTurn>), deps(w.admin));
  assertEquals(await Promise.all([lead, follow]), ['answer', 'merged']);
  assertEquals(w.rows[0].inbound, 'Hi\nI need quotes for aluminium windows');
});

// Final audit 12 Nov 2026, integration F8 (proof p1_messages F-LOOP): a person who sends the same 20+ character message four times
// in an hour got no fourth reply, the founder's own number included. The cap is for machines: a repeat counts only when it comes
// within seconds of our reply, and the founder's number is never capped. Both fail on main.
Deno.test('the loop cap leaves a person repeating himself alone, and never stops the founder', async () => {
  const w = db();
  const same = 'Hello, is anyone there? I asked about my aluminium windows quote';
  const at = (min: number) => new Date(Date.now() - min * 60_000).toISOString();
  for (const [id, m] of [[1, 40], [2, 30], [3, 20]] as const) {
    w.rows.push({ id, wa_from: A, created_at: at(m), inbound: same, reply: 'Our reply ' + id, sent: true, replied_at: at(m - 0.5), meta: { stage: 'handled' } });
  }
  const t = turnFor(w.arrive(A, same));
  assertEquals((await loopHeld(t, deps(w.admin, '0'))).held, false, 'a person repeating himself minutes apart is answered');
  // a responder: the same words back within seconds of each of our replies -> held
  const m = db();
  const auto = 'Hello, is anyone there? I asked about my aluminium windows quote';
  m.rows.push({ id: 1, wa_from: A, created_at: at(50), inbound: 'Do you supply glass?', reply: 'Yes...', sent: true, replied_at: at(49.9), meta: { stage: 'handled' } });
  for (const [id, sec] of [[2, 49.85], [3, 39.85], [4, 29.85]] as const) {
    m.rows.push({ id, wa_from: A, created_at: at(sec), inbound: auto, reply: 'Reply ' + id, sent: true, replied_at: at(sec - 10), meta: { stage: 'handled' } });
  }
  const mt = turnFor(m.arrive(A, auto, { created_at: new Date(Date.now()).toISOString() }));
  // each repeat lands within seconds of our reply before it; the last of our replies went 5 s before this message
  m.rows[m.rows.length - 2].replied_at = new Date(Date.now() - 5_000).toISOString();
  assertEquals((await loopHeld(mt, deps(m.admin, '0'))).held, true, 'a repeat seconds after each reply is a machine');
  // the founder's number: never held, even by an auto-reply phrase
  const f = db();
  const phrase = 'Thank you for contacting us. We have received your message and our team will get back to you shortly.';
  for (const [id, min] of [[1, 40], [2, 30], [3, 20]] as const) f.rows.push({ id, wa_from: A, created_at: at(min), inbound: phrase, reply: 'r', sent: true, replied_at: at(min - 1), meta: { stage: 'handled' } });
  const ft = turnFor(f.arrive(A, phrase));
  assertEquals((await loopHeld(ft, { ...deps(f.admin, '0'), isFounder: () => Promise.resolve(true) })).held, false, 'the founder is never capped');
  assertEquals((await loopHeld(ft, deps(f.admin, '0'))).held, true, 'control: the same history from anyone else is held');
});

// Review of 12 Nov 2026: the current message was stamped at the decision (after the 4-7 s burst wait), not at its arrival, so a
// repeat that came 10 s after our reply was read as 15+ s and taken for a person. Fails on 1e8378c59.
Deno.test('the loop cap reads the current message at its arrival, not at the end of the burst wait', async () => {
  const m = db();
  const at = (ms: number) => new Date(Date.now() - ms).toISOString();
  const auto = 'Hello, is anyone there? I asked about my aluminium windows quote';
  m.rows.push({ id: 1, wa_from: A, created_at: at(40 * 60_000), inbound: 'Do you supply glass?', reply: 'Yes...', sent: true, replied_at: at(39 * 60_000), meta: { stage: 'handled' } });
  m.rows.push({ id: 2, wa_from: A, created_at: at(39 * 60_000 - 3_000), inbound: auto, reply: 'r2', sent: true, replied_at: at(30 * 60_000), meta: { stage: 'handled' } });
  m.rows.push({ id: 3, wa_from: A, created_at: at(30 * 60_000 - 3_000), inbound: auto, reply: 'r3', sent: true, replied_at: at(20 * 60_000), meta: { stage: 'handled' } });
  m.rows.push({ id: 4, wa_from: A, created_at: at(20 * 60_000 - 3_000), inbound: auto, reply: 'r4', sent: true, replied_at: at(17_000), meta: { stage: 'handled' } });
  // the repeat arrived 10 s after our last reply (7 s ago); the gate decides now, after the burst wait
  const t = turnFor(m.arrive(A, auto, { created_at: at(7_000) }));
  assertEquals((await loopHeld(t, deps(m.admin, '0'))).held, true, 'a repeat 10 s after our reply is a machine');
});

// Re-check of 12 Nov 2026, R13: "ok good, thanks" took 19.8 s (a reading and a reply) to answer "You're welcome." A thanks-only message
// ends the turn recorded, with no model call and no reply; a question, a bare "ok" or the founder is answered as before. Fails on
// dc9a17b75 (no thanksOnly).
Deno.test('a thank-you only: recorded, no model, no reply; anything more is answered as before', async () => {
  const { thanksOnly } = await import('./burst.ts');
  for (const m of ['ok good, thanks', 'Thanks!', 'thank you so much 🙏', 'شكرًا لكم', 'مشكور', '👍']) assert(thanksOnly(m), m);
  for (const m of ['ok', 'thanks, and how many quotes will I see?', 'no thanks', 'Thanks for the quote of AED 500, can you do 450?', '6']) assert(!thanksOnly(m), m);
  const w = db();
  const inserted: Record<string, unknown>[] = [];
  const t = turnFor(w.arrive(A, 'ok good, thanks'), { waInsert: (_r: string, row: Record<string, unknown>) => { inserted.push(row); return Promise.resolve({}); } } as Partial<WaTurn>);
  const r = await turnGate(t, deps(w.admin, '0'));
  assert(r instanceof Response, 'the turn ends at the gate');
  assertEquals([(inserted[0].meta as Record<string, unknown>).no_autoreply_reason, inserted[0].reply], ['closing_courtesy', '']);
  const f = db();
  const ft = turnFor(f.arrive(A, 'thanks'), { waInsert: () => Promise.resolve({}) } as Partial<WaTurn>);
  assertEquals(await turnGate(ft, { ...deps(f.admin, '0'), isFounder: () => Promise.resolve(true) }), undefined, 'the founder is answered');
});

// Review of branch B (12 Nov 2026), item 12: "great, thanks" right after an OFFER of ours ("Shall I send it to suppliers?") is an
// answer and must be read; only after a message that asked nothing is a thank-you left unanswered. Fails on c4a467389.
Deno.test('a thank-you after our question is read as their answer; after a message that asked nothing it needs no reply', async () => {
  const at = (s: number) => new Date(Date.now() - s * 1000).toISOString();
  const offer = db();
  offer.rows.push({ id: 1, wa_from: A, created_at: at(60), inbound: 'I need 12 windows', reply: 'Your request is ready. Shall I send it to suppliers?', sent: true, replied_at: at(50), meta: { stage: 'handled' } });
  const t1 = turnFor(offer.arrive(A, 'great, thanks'), { waInsert: () => Promise.resolve({}) } as Partial<WaTurn>);
  assertEquals(await turnGate(t1, deps(offer.admin, '0')), undefined, 'answered: it accepts our offer');
  const told = db();
  told.rows.push({ id: 1, wa_from: A, created_at: at(60), inbound: 'how much is the fee?', reply: 'The reveal fee is 3% of the quote you choose.', sent: true, replied_at: at(50), meta: { stage: 'handled' } });
  const t2 = turnFor(told.arrive(A, 'great, thanks'), { waInsert: () => Promise.resolve({}) } as Partial<WaTurn>);
  assert((await turnGate(t2, deps(told.admin, '0'))) instanceof Response, 'a thank-you after a statement needs no reply');
});
