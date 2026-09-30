// supplier_charge_documents.test.ts — the clause 33 recovery file, from the ZZ DEMO case.
// deno test --no-lock supabase/functions/_shared/supplier_charge_documents.test.ts
// The arithmetic is asserted to the fils; every document renders through the real renderer; the
// invoice, demand and claim agree on the principal; the demand gives at least the legal minimum;
// no document charges VAT; and no real party can appear (ZZ DEMO / example.invalid only).
import { assert, assertEquals, assertStringIncludes, assertThrows } from 'jsr:@std/assert@1';
import { computeCharge, adminFeeAed, termsAt } from './supplier_charge.ts';
import { recoveryPack, finalDemandDocument, invoiceDocument, claimDocument, LEGAL, signingRecord, sha256Hex } from './supplier_charge_documents.ts';
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
  // A payment on the day it is due stops interest on that part from that day.
  const onTime = computeCharge({ ...base, as_of: '2026-11-17', payments: [{ date: '2026-10-16', amount: 705.72 }] });
  assertEquals([onTime.unpaid_principal, onTime.interest], [2000, 15.78]); // 2000 × 0.09 × 32 / 365
  // Mid-period part-payment: 2705.72 for 10 days, then 2000 for 22 days.
  const mid = computeCharge({ ...base, as_of: '2026-11-17', payments: [{ date: '2026-10-26', amount: 705.72 }] });
  assertEquals([mid.paid, mid.unpaid_principal, mid.interest], [705.72, 2000, 17.52]); // 6.672 + 10.849 = 17.521
  // Paid in full mid-period: the principal is gone, the interest accrued to that day remains.
  const full = computeCharge({ ...base, as_of: '2026-11-17', payments: [{ date: '2026-10-26', amount: 2705.72 }] });
  assertEquals([full.unpaid_principal, full.interest, full.total_due], [0, 6.67, 6.67]);
  // A payment dated after as_of is not yet counted.
  assertEquals(computeCharge({ ...base, as_of: '2026-10-20', payments: [{ date: '2026-11-01', amount: 100 }] }).paid, 0);
  assertThrows(() => computeCharge({ ...base, refunded_reveal_fee: 0, as_of: '2026-11-17' }));
});

Deno.test('a span over 29 February counts the leap day, on a 365-day year', () => {
  // notice 21 Feb 2028 → due 28 Feb 2028; to 1 Mar 2028 is 2 days (28→29, 29→1).
  const c = computeCharge({ refunded_reveal_fee: 2367, refunded_processing_fee: 88.72, notice_date: '2028-02-21', as_of: '2028-03-01' });
  assertEquals([c.due_date, c.days_overdue, c.interest], ['2028-02-28', 2, 1.33]); // 2705.72 × 0.09 × 2 / 365 = 1.334
  // A payment on 29 Feb splits the span: one day on the full principal, one on the remainder.
  const p = computeCharge({ refunded_reveal_fee: 2367, refunded_processing_fee: 88.72, notice_date: '2028-02-21', as_of: '2028-03-01', payments: [{ date: '2028-02-29', amount: 1705.72 }] });
  assertEquals([p.unpaid_principal, p.interest], [1000, 0.91]); // 0.667 + 0.247 = 0.914
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
  assertStringIncludes(inv, 'AED 2,617.00');
  assert(!inv.includes('card processing fee refunded'), 'a reveal with no card fee shows no card-fee line');
  assertStringIncludes(inv, 'not registered for VAT');
  assertStringIncludes(JSON.stringify(claimDocument(C, 'en')), 'AED 2,617.00');
  assertStringIncludes(JSON.stringify(claimDocument(C, 'ar')), '2,617.00 درهم');
  assert(LEGAL.final_demand_days >= LEGAL.demand_days, 'the demand gives less than the law requires');
  // Art 340(1) is quoted in the official wording of each language, never a translation made here.
  assertStringIncludes(JSON.stringify(claimDocument(C, 'ar')), 'يجوز للمتعاقدين أن يُحددا مقدمًا قيمة التعويض بالنص عليها في العقد أو في اتفاق لاحق، مع مراعاة أحكام القانون.');
  assertStringIncludes(JSON.stringify(claimDocument(C, 'en')), 'The contracting parties may pre-determine the amount of compensation by stipulating it in the contract or in a subsequent agreement, subject to the provisions of the law.');
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

Deno.test('every recovery document but the guide is signed, and each signing is recorded with its hash', async () => {
  const pack = recoveryPack(C);
  for (const p of pack) assertEquals(!!p.body.options.sign && !!p.body.options.stamp, p.name !== '4c_filing_guide', p.name);
  assert(!/2883503/.test(JSON.stringify(pack)), 'a register number the licence does not print');
  const bytes = new TextEncoder().encode('%PDF-1.7 demo');
  const inv = pack.find((p) => p.name === '1_invoice' && p.lang === 'en')!;
  const rec = await signingRecord(C, inv, bytes, 1, { signature: new Uint8Array([1]), stamp: null });
  assert(rec);
  assertEquals([rec.document, rec.ref, rec.agreement_version, rec.issued, rec.signature_asset, rec.stamp_asset_sha256], ['1_invoice', C.invoice.number, C.acceptance.version, C.invoice.date, 'brand/qd_signature.png', null]);
  assertEquals(rec.pdf_sha256, await sha256Hex(bytes));
  assertEquals(rec.pdf_sha256.length, 64);
  assertEquals(await signingRecord(C, pack.find((p) => p.name === '4c_filing_guide')!, bytes, 1), null);
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

Deno.test('the clause 33(b) fee is the one the supplier had signed at the reveal, never retroactive (v13, 23 Sep 2026)', () => {
  assertEquals(adminFeeAed('v12', '2026-09-14T10:00:00Z', '2026-10-01T10:00:00Z'), 250);
  assertEquals(adminFeeAed('v13', '2026-09-24T10:00:00Z', '2026-10-01T10:00:00Z'), 500);
  assertEquals(adminFeeAed('v13', '2026-10-02T10:00:00Z', '2026-10-01T10:00:00Z'), 250, 'accepted after the reveal');
  assertEquals(adminFeeAed('v13', null, '2026-10-01T10:00:00Z'), 250, 'unknown acceptance time');
  assertEquals(adminFeeAed(null, null, null), 250);
  const c = computeCharge({ refunded_reveal_fee: 300, refunded_processing_fee: 10, notice_date: '2026-10-01', as_of: '2026-10-08', admin_fee_aed: 500 });
  assertEquals(c.admin_fee, 500); assertEquals(c.principal, 810);
  assertThrows(() => computeCharge({ refunded_reveal_fee: 300, refunded_processing_fee: 10, notice_date: '2026-10-01', as_of: '2026-10-08', admin_fee_aed: 999 }));
});

Deno.test('v14 (24 Sep 2026): the processor fee at cost, only for a supplier who accepted v14 before the reveal', () => {
  const rev = '2026-10-01T10:00:00Z';
  assertEquals(termsAt('v14', '2026-09-25T10:00:00Z', rev), { version: 14, admin_fee: 500, rate_pa: 0.09, processor_fee_owed: true });
  assertEquals(termsAt('v13', '2026-09-24T10:00:00Z', rev), { version: 13, admin_fee: 500, rate_pa: 0.09, processor_fee_owed: false });
  assertEquals(termsAt('v14', '2026-10-02T10:00:00Z', rev).rate_pa, 0.09, 'accepted after the reveal: never retroactive');
  assertEquals(termsAt('v14', null, rev).processor_fee_owed, false, 'unknown acceptance time: the lowest terms');
  // a full year on (300 + 8.95 + 500): v14 writes 12%, but 9% is the lawful maximum and the rate charged
  // (founder ruling, 30 Sep 2026): 808.95 x 9% = 72.81 (to the fils), never compounded
  const c = computeCharge({ refunded_reveal_fee: 300, refunded_processing_fee: 0, unrecovered_processor_fee: 8.95, notice_date: '2026-10-01', as_of: '2027-10-08', admin_fee_aed: 500, rate_pa: 0.12 });
  assertEquals(c.principal, 808.95); assertEquals(c.interest, 72.81); assertEquals(c.rate_pa, 0.09);
  assertThrows(() => computeCharge({ refunded_reveal_fee: 300, refunded_processing_fee: 0, notice_date: '2026-10-01', as_of: '2026-10-08', rate_pa: 0.18 }), Error, 'no signed version');
  // the documents follow the signed version: v14 letters (b) processor fee, (c) admin, (d) interest at 9%
  const v14 = { ...C, acceptance: { ...C.acceptance, version: 'v14', accepted_at: '2026-09-25T10:00:00Z' }, reveal: { ...C.reveal, paid_at: '2026-10-01T10:00:00Z' }, refund: { ...C.refund, unrecovered_processor_fee: 8.95 } };
  const inv = JSON.stringify(invoiceDocument(v14, 'en'));
  assertStringIncludes(inv, 'Processor fee QuotesDone could not recover (b)');
  assertStringIncludes(JSON.stringify(finalDemandDocument(v14, 'en')), 'Interest (d) at 9% p.a.');
  const old = JSON.stringify(invoiceDocument(C, 'en'));
  assert(!old.includes('Processor fee'), 'a pre-v14 supplier is never charged the processor fee');
});
