// The ex-VAT price: determined exactly, or not at all. The TREATMENT is what the supplier stated — the
// portal's VAT select, or their words as REASONED (decision point line_specs.options_derive_vat) — never a
// word the text happens to contain.
// deno test --no-lock --node-modules-dir=none supabase/functions/_shared/line_specs/vat.test.ts
import { assertEquals } from 'jsr:@std/assert@1';
import { readVat } from './vat.ts';

const ex = (i: Parameters<typeof readVat>[0]) => { const r = readVat(i); return [r.treatment, r.price_ex_vat]; };

Deno.test('a stated treatment gives the ex-VAT price', () => {
  assertEquals(ex({ amount: 10500, stated: 'exclusive' }), ['exclusive', 10500]);
  assertEquals(ex({ amount: 11025, stated: 'inclusive', vat_rate: 5 }), ['inclusive', 10500]);
  assertEquals(ex({ amount: 11025, vat_amount: 525, stated: 'inclusive' }), ['inclusive', 10500]);
  assertEquals(ex({ amount: 11655, subtotal: 11100, vat_amount: 555 }), ['exclusive', 11100]);
  assertEquals(ex({ amount: 9000, stated: 'not_registered' }), ['not_registered', 9000]);
  assertEquals(ex({ amount: 9000, price_ex_vat: 8571.43 }), ['confirmed_on_portal', 8571.43]);
});

Deno.test('words in the text decide nothing: each of these once set the treatment by a word list', () => {
  for (const text of ['Total AED 10,500 excluding VAT', 'السعر غير شامل الضريبة', 'Prices + VAT', 'Total inclusive of 5% VAT', 'We are not VAT registered', 'غير مسجل في الضريبة']) {
    assertEquals(ex({ amount: 10500, text }), ['not_stated', null], text);
  }
});

Deno.test('silence, or an inclusive price with no amount or rate, is not a price: the quote will be held', () => {
  assertEquals(ex({ amount: 10500 }), ['not_stated', null]);
  assertEquals(ex({ amount: 11025, stated: 'inclusive' }), ['inclusive', null]);
  assertEquals(ex({ amount: 11025, stated: 'not_stated' }), ['not_stated', null]);
});

Deno.test('the supplier TRN is captured for the record (a number format)', () => {
  assertEquals(readVat({ amount: 1, text: 'TRN 100 2345 6789 0003, excl VAT' }).trn, '100234567890003');
});
