// A held Arabic comparison report becomes exactly one delivered Arabic report (PR #1574, release operator's review).
// No network, no database: compare_arabic.ts is pure over its IO, and the IO here is an in-memory waiter table and an
// outbox that honours dedupe_key the way fn_customer_support_takes_delivery does (the same key returns the first).
import { assert, assertEquals, assertMatch } from 'jsr:@std/assert';
import { finishCompareArabic, MAX_ATTEMPTS, type CompareFinishIO, type Rendered, type Waiter } from './compare_arabic.ts';

const IID = 'zz-demo-inquiry';
function rig(o: { render?: () => Rendered; email?: string | null; deliverFails?: boolean } = {}) {
  const waiters = new Map<string, Waiter>([[IID, { inquiry_id: IID, created_at: '2026-10-19T12:00:00Z', attempts: 0 }]]);
  const outbox = new Map<string, Record<string, unknown>>();
  const renders: string[] = []; const told: unknown[] = [];
  const io: CompareFinishIO = {
    waiter: (iid) => Promise.resolve(waiters.get(iid) ?? null),
    inquiry: (iid) => Promise.resolve({ id: iid, rfq_no: 'RFQ-1', customer_id: 'zz-cust' }),
    customer: () => Promise.resolve({ email: o.email === undefined ? 'zz.demo@example.invalid' : o.email }),
    render: (inq) => { renders.push(inq.id); return Promise.resolve(o.render ? o.render() : { url: 'https://example.invalid/compare.pdf', ref: 'QD-1-CMP' }); },
    deliver: (rows) => {
      if (o.deliverFails) return Promise.resolve({ ok: false, err: 'refused' });
      for (const r of rows) if (!outbox.has(String(r.dedupe_key))) outbox.set(String(r.dedupe_key), r);
      return Promise.resolve({ ok: true });
    },
    done: (iid) => { waiters.delete(iid); return Promise.resolve(); },
    tried: (iid, attempts) => { const w = waiters.get(iid); if (w) waiters.set(iid, { ...w, attempts }); return Promise.resolve(); },
    tellSalesEngineer: (_iid, last) => { told.push(last); return Promise.resolve(); },
  };
  return { io, waiters, outbox, renders, told };
}

Deno.test('a held report whose lines now exist is rendered and sent to the customer in Arabic, once per channel', async () => {
  const r = rig();
  const out = await finishCompareArabic(r.io, IID);
  assertEquals(out, { ok: true, ref: 'QD-1-CMP', sent: 2 });
  assertEquals([...r.outbox.values()].map((x) => x.channel), ['email', 'whatsapp']);
  for (const m of r.outbox.values()) {
    assertEquals([m.lang, m.to_role, m.to_email, m.requested_by, m.sender], ['ar', 'customer', 'zz.demo@example.invalid', 'customer_support', 'customer_support']);
    assertMatch(String(m.subject), /[؀-ۿ]/);
    assertMatch(String(m.body), /[؀-ۿ][\s\S]*https:\/\/example\.invalid\/compare\.pdf/);
  }
  assertEquals(r.waiters.size, 0, 'the waiter is gone once the report is handed over');
});

Deno.test('exactly once: a second run (another replay row, a retry) finds no waiter and sends nothing', async () => {
  const r = rig();
  await finishCompareArabic(r.io, IID);
  assertEquals(await finishCompareArabic(r.io, IID), { ok: false, code: 'no_waiter' });
  assertEquals([r.outbox.size, r.renders.length], [2, 1]);
});

Deno.test('exactly once: two runs racing on the same waiter queue one delivery per channel (the dedupe key is the waiter)', async () => {
  const r = rig();
  await Promise.all([finishCompareArabic(r.io, IID), finishCompareArabic(r.io, IID)]);
  assertEquals(r.outbox.size, 2, 'the same dedupe key returns the first request');
  assert([...r.outbox.keys()].every((k) => k.startsWith('compare_ar:' + IID + ':' + Date.parse('2026-10-19T12:00:00Z'))));
});

Deno.test('a line still missing: nothing is sent, nothing is counted against it, and the waiter stays for the next replay', async () => {
  const r = rig({ render: () => ({ held: true }) });
  assertEquals(await finishCompareArabic(r.io, IID), { ok: false, code: 'still_pending' });
  assertEquals([r.outbox.size, r.waiters.get(IID)?.attempts], [0, 0]);
});

Deno.test('a render that keeps failing is counted, and the sales engineer is told at the limit', async () => {
  const r = rig({ render: () => ({ error: 'pdf_failed' }) });
  for (let i = 0; i < MAX_ATTEMPTS; i++) assertEquals((await finishCompareArabic(r.io, IID)).ok, false);
  assertEquals([r.outbox.size, r.waiters.get(IID)?.attempts, r.told.length], [0, MAX_ATTEMPTS, 1]);
});

Deno.test('a refused delivery keeps the waiter, so the next replay sends it', async () => {
  const r = rig({ deliverFails: true });
  assertEquals((await finishCompareArabic(r.io, IID)).ok, false);
  assertEquals(r.waiters.get(IID)?.attempts, 1);
});

Deno.test('a customer with no address: the waiter is closed, nothing is rendered or sent', async () => {
  const r = rig({ email: null });
  assertEquals(await finishCompareArabic(r.io, IID), { ok: false, code: 'no_contact' });
  assertEquals([r.renders.length, r.outbox.size, r.waiters.size], [0, 0, 0]);
});

Deno.test('customer_api wires the finisher: the held 202 records a waiter, a report in hand clears it, the replay renders without a model', async () => {
  const src = await Deno.readTextFile(new URL('./index.ts', import.meta.url));
  assertMatch(src, /if \(!doc\.doc\) \{\s*const \{ error: wErr \} = await admin\.rpc\('fn_arabic_compare_wait', \{ p_inquiry: String\(inq\.id\), p_texts: doc\.missing \}\);/);
  assertMatch(src, /if \(j\?\.ok && j\.url && lang === 'ar'\) await admin\.from\('arabic_compare_waiter'\)\.delete\(\)\.eq\('inquiry_id', iid\);/);
  assertMatch(src, /buildComparePdf\(got\.analysis, inq, 'ar', Date\.now\(\)\)/);
  assertMatch(src, /peek\.action === 'compare_arabic_finish'[\s\S]{0,200}requireInternal\(admin, String\(peek\.__secret\), 'customer_api'\)/);
});
