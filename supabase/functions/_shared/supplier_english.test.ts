import { assert, assertEquals } from 'jsr:@std/assert@1';
import { englishAnswer, finishEnglish, HELD_NOTICE, hasArabic, holdForEnglish, supplierMail, toSuppliers } from './supplier_english.ts';

Deno.test('Arabic script anywhere is caught; English, numbers and symbols are not', () => {
  assert(hasArabic('نعم، السقف 3 أمتار'));
  assert(hasArabic('Ceiling height 3 m, اللون أبيض'));
  assert(hasArabic('ﻻ')); // presentation forms
  assertEquals(hasArabic('Ceiling height 3.2 m; white RAL 9010, 60x60 tiles - 120 m²'), false);
  assertEquals(hasArabic(null), false);
  assertEquals(hasArabic(String.fromCharCode(0xfeff) + 'Yes, 3 m'), false); // a pasted byte-order mark is not Arabic
});

Deno.test('the customer is told in Arabic that the message will be passed on; the English says the same', () => {
  assert(hasArabic(HELD_NOTICE.ar));
  assertEquals(hasArabic(HELD_NOTICE.en), false);
});

Deno.test('a reasoned answer is a supplier copy only when it is English', () => {
  assertEquals(englishAnswer('Yes, the ceiling is 3 m high.'), 'Yes, the ceiling is 3 m high.');
  assertEquals(englishAnswer('"Yes, 3 m."'), 'Yes, 3 m.');
  assertEquals(englishAnswer('Yes, السقف 3 m'), null);
  assertEquals(englishAnswer(''), null);
  assertEquals(englishAnswer(undefined), null);
});

Deno.test('NO ARABIC REACHES A SUPPLIER: a supplier row carrying Arabic in its subject or body is dropped', () => {
  const rows = [
    { to_email: 'a@example.invalid', subject: 'Ok', body: 'The customer answered: "Yes, 3 m"' },
    { to_email: 'b@example.invalid', subject: 'Ok', body: 'The customer answered: "نعم، 3 أمتار"' },
    { to_email: 'c@example.invalid', subject: 'سؤال', body: 'x' },
  ];
  assertEquals(toSuppliers(rows).map((r) => r.to_email), ['a@example.invalid']);
  // Even if a caller hands the mail builder Arabic, the row it builds never passes.
  const m = supplierMail('question', { category: 'joinery', emirate: 'Dubai' }, 'Ceiling height?', 'نعم');
  assertEquals(toSuppliers([m]).length, 0);
});

// A fake client: records rpc calls and the rfq_clarification update, answers the reads the module makes.
function fakeAdmin(row: Record<string, unknown> | null) {
  const rpcs: [string, any][] = []; const updates: Record<string, unknown>[] = [];
  const q = (table: string) => {
    const self: any = {
      select: () => self, eq: () => self, not: () => self, in: () => self, is: () => self,
      update: (v: Record<string, unknown>) => { updates.push(v); return self; },
      // 13 Nov 2026: the replay reads the request's owner for the supplier gate (what_a_supplier_receives.ts readOwner)
      maybeSingle: () => Promise.resolve({ data: table === 'rfq_clarification' ? row : table === 'inquiries' ? { category: 'joinery', emirate: 'Dubai', customer_id: 'c1', spec: { site_location: 'Villa 15, Al Barsha 2' } }
        : table === 'customers' ? { full_name: 'ZZ DEMO Test Customer', email: 'zz.test@example.invalid', phone: '+971500000001' } : null, error: null }),
      then: (res: (v: unknown) => unknown) => res(
        table === 'inquiry_matches' ? { data: [{ supplier_id: 7 }, { supplier_id: 8 }], error: null }
        : table === 'leads' ? { data: [{ id: 7, email: 'z7@example.invalid' }, { id: 8, claimed_by: 'z8@example.invalid', banned: true }], error: null }
        : { data: [{ id: 1 }], error: null }),
    };
    return self;
  };
  return { rpcs, updates, admin: { from: q, rpc: (fn: string, a: any) => { rpcs.push([fn, a]); return Promise.resolve({ data: fn === 'fn_reason_hold' ? 5 : [{ notification_id: 1, handoff_id: 1 }], error: null }); } } };
}

Deno.test('the held English is filed in the sales_engineer queue, once per clarification', async () => {
  const f = fakeAdmin(null);
  await holdForEnglish(f.admin, 42, 'نعم، السقف 3 أمتار');
  const [fn, a] = f.rpcs[0];
  assertEquals([fn, a.p_seat, a.p_surface, a.p_dedupe_key, a.p_subject], ['fn_reason_hold', 'sales_engineer', 'sales_engineer.supplier_english', 'supplier_english:42', { clarification_id: 42 }]);
});

// founder ruling 1338 (27 Oct 2026): the English is e-mailed to suppliers, so it is reasoned as for a supplier — the
// public brief and the outside-audience retrieval — never with the internal brief or internal knowledge rows.
Deno.test('the supplier copy is reasoned for a supplier audience, never an internal one', async () => {
  const f = fakeAdmin(null);
  await holdForEnglish(f.admin, 43, 'نعم');
  const [, a] = f.rpcs[0];
  assertEquals(a.p_request.context.audience, 'supplier');
});

Deno.test('the replay never stores or sends an answer that is still Arabic', async () => {
  const f = fakeAdmin({ id: 42, inquiry_id: 'zz', kind: 'question', question: 'Ceiling height?', english_held_at: '2026-10-05' });
  const r = await finishEnglish(f.admin, 42, 'نعم، 3 أمتار');
  assertEquals(r.ok, false);
  assertEquals(f.updates.length, 0);
  assertEquals(f.rpcs.length, 0);
});

Deno.test('the replay stores the English and e-mails every unbanned matched supplier in English', async () => {
  const f = fakeAdmin({ id: 42, inquiry_id: 'zz', kind: 'question', question: 'Ceiling height?', english_held_at: '2026-10-05' });
  const r = await finishEnglish(f.admin, 42, 'Yes, the ceiling is 3 m.');
  assertEquals([r.ok, r.notified], [true, 1]);
  assertEquals(f.updates[0], { answer: 'Yes, the ceiling is 3 m.', english_held_at: null });
  const sent = f.rpcs.find(([fn]) => fn === 'fn_customer_support_takes_delivery')![1].p_rows;
  assertEquals(sent.map((x: any) => x.to_email), ['z7@example.invalid']);
  for (const x of sent) assertEquals(hasArabic(x.subject) || hasArabic(x.body), false);
});

Deno.test('the replay\'s English passes the supplier gate: the customer\'s site never goes out', async () => {
  const f = fakeAdmin({ id: 44, inquiry_id: 'zz', kind: 'question', question: 'Where is the site?', english_held_at: '2026-10-05' });
  const r = await finishEnglish(f.admin, 44, 'It is Villa 15, Al Barsha 2.');
  assertEquals(r.ok, true);
  const all = JSON.stringify([f.updates, f.rpcs]);
  assertEquals(/Barsha|Villa 15/.test(all), false, all);
});

Deno.test('a clarification already finished is never mailed twice', async () => {
  const f = fakeAdmin({ id: 42, inquiry_id: 'zz', kind: 'note', question: null, english_held_at: null });
  assertEquals(await finishEnglish(f.admin, 42, 'More detail.'), { ok: true, notified: 0 });
  assertEquals(f.rpcs.length, 0);
});
