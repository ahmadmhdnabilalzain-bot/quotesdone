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
  finding: async (k) => { findings.push(k); }, sleep: (ms) => new Promise((r) => setTimeout(r, ms)), now: () => Date.now(),
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
