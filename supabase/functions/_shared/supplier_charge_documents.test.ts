// supplier_charge_documents.test.ts — the clause 33 recovery file, from the ZZ DEMO case.
// deno test --no-lock supabase/functions/_shared/supplier_charge_documents.test.ts
// The arithmetic is asserted to the fils; every document renders through the real renderer; the
// invoice, demand and claim agree on the principal; the demand gives at least the legal minimum;
// no document charges VAT; and no real party can appear (ZZ DEMO / example.invalid only).
import { assert, assertEquals, assertStringIncludes, assertThrows } from 'jsr:@std/assert@1';
import { computeCharge } from './supplier_charge.ts';
import { recoveryPack, finalDemandDocument, invoiceDocument, claimDocument, LEGAL } from './supplier_charge_documents.ts';
import { DEMO_CASE as C } from './supplier_charge.fixture.ts';
import { renderPdf } from '../pdf_native/render.ts';

Deno.test('interest: simple, daily, from the due date, on (a)+(b) only', () => {
  const base = { refunded_reveal_fee: 2367, refunded_processing_fee: 88.72, notice_date: '2026-10-09' };
  const onDue = computeCharge({ ...base, as_of: '2026-10-16' });
  assertEquals([onDue.principal, onDue.due_date, onDue.days_overdue, onDue.interest], [2705.72, '2026-10-16', 0, 0]);
  assertEquals(computeCharge({ ...base, as_of: '2026-10-10' }).interest, 0, 'no interest before the due date');
  const d32 = computeCharge({ ...base, as_of: '2026-11-17' });
  assertEquals([d32.days_overdue, d32.interest, d32.total_due], [32, 21.35, 2727.07]); // 2705.72 × 0.09 × 32 / 365 = 21.349
  const yr = computeCharge({ ...base, as_of: '2027-10-16' });
  assertEquals(yr.interest, 243.51, 'a full year is 9% of the principal, not compounded'); // 2705.72 × 0.09
  const part = computeCharge({ ...base, as_of: '2026-11-17', paid: 705.72 });
  assertEquals([part.unpaid_principal, part.interest], [2000, 15.78]);
  assertThrows(() => computeCharge({ ...base, refunded_reveal_fee: 0, as_of: '2026-11-17' }));
});

Deno.test('the pack is a demo case and can reach nobody real', () => {
  const s = JSON.stringify(recoveryPack(C));
  assertStringIncludes(C.supplier.legal_name, 'ZZ DEMO');
  assert(C.supplier.email.endsWith('.example.invalid'));
  for (const id of [C.reveal.payment_intent, C.refund.refund_id]) assert(id.includes('ZZDEMO'));
  assert(!/@(?!quotesdone\.com|[\w.-]*example\.invalid)[\w.-]+\.\w+/.test(s), 'an address outside quotesdone.com / example.invalid');
});

Deno.test('documents agree, give the legal minimum, and charge no VAT', () => {
  const inv = JSON.stringify(invoiceDocument(C, 'en'));
  assertStringIncludes(inv, 'AED 2,705.72');
  assertStringIncludes(inv, 'not registered for VAT');
  assertStringIncludes(JSON.stringify(claimDocument(C, 'en')), 'AED 2,705.72');
  assertStringIncludes(JSON.stringify(claimDocument(C, 'ar')), '2,705.72 درهم');
  assert(LEGAL.final_demand_days >= LEGAL.demand_days, 'the demand gives less than the law requires');
  // CPL Art. 144(1): the right in the notice may not be less than the right in the petition. Both
  // claim the same principal; the petition's interest is the demand's daily rate carried forward.
  const fd = finalDemandDocument(C, 'en'), po = claimDocument(C, 'en');
  const principal = (b: unknown) => JSON.stringify(b).match(/Principal due","(AED [\d,.]+)/)?.[1];
  assertEquals(principal(po), principal(fd));
  assertStringIncludes(JSON.stringify(fd), 'for each day from the date of this demand until payment in full');
  for (const lang of ['en', 'ar'] as const) {
    const fd = JSON.stringify(finalDemandDocument(C, lang));
    assertStringIncludes(fd, lang === 'ar' ? 'أمر أداء' : 'payment order');
    assertStringIncludes(fd, lang === 'ar' ? 'البند 33' : 'Clause 33');
  }
  for (const p of recoveryPack(C)) assert(!/\b5%|vat of|ضريبة القيمة المضافة بواقع/i.test(JSON.stringify(p.body)), p.name + ' charges VAT');
});

Deno.test('every document renders to a PDF', async () => {
  const pack = recoveryPack(C);
  assertEquals(pack.length, 14);
  for (const p of pack) {
    const out = await renderPdf({ ...p.body, options: { letterhead: true } }, { fetchBytes: () => Promise.resolve(null) });
    assert(out.ok, p.name + ' refused: ' + JSON.stringify(!out.ok && out.body));
    if (out.ok) { assertEquals(new TextDecoder().decode(out.bytes.slice(0, 5)), '%PDF-'); if (p.lang === 'en') assertEquals(out.meta.glyphs_dropped, 0, p.name); }
  }
});
