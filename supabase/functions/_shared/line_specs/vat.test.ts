// The ex-VAT price: determined exactly, or not at all.
// deno test --no-lock --node-modules-dir=none supabase/functions/_shared/line_specs/vat.test.ts
import { assertEquals } from 'jsr:@std/assert@1';
import { readVat } from './vat.ts';

const ex = (i: Parameters<typeof readVat>[0]) => { const r = readVat(i); return [r.treatment, r.price_ex_vat]; };

Deno.test('stated treatments give the ex-VAT price', () => {
  assertEquals(ex({ amount: 10500, text: 'Total AED 10,500 excluding VAT' }), ['exclusive', 10500]);
  assertEquals(ex({ amount: 10500, text: 'السعر غير شامل الضريبة' }), ['exclusive', 10500]);
  assertEquals(ex({ amount: 10500, text: 'Prices + VAT' }), ['exclusive', 10500]);
  assertEquals(ex({ amount: 11025, text: 'Total inclusive of 5% VAT' }), ['inclusive', 10500]);
  assertEquals(ex({ amount: 11025, vat_amount: 525, text: 'Including VAT' }), ['inclusive', 10500]);
  assertEquals(ex({ amount: 11655, subtotal: 11100, vat_amount: 555 }), ['exclusive', 11100]);
  assertEquals(ex({ amount: 9000, text: 'We are not VAT registered' }), ['not_registered', 9000]);
  assertEquals(ex({ amount: 9000, text: 'غير مسجلين في ضريبة القيمة المضافة' }).slice(1), [null]);
  assertEquals(ex({ amount: 9000, text: 'غير مسجل في الضريبة' }), ['not_registered', 9000]);
  assertEquals(ex({ amount: 9000, price_ex_vat: 8571.43 }), ['confirmed_on_portal', 8571.43]);
});

Deno.test('silence or an inclusive price with no amount or rate is not a price: the quote will be held', () => {
  assertEquals(ex({ amount: 10500, text: 'Total AED 10,500' }), ['not_stated', null]);
  assertEquals(ex({ amount: 11025, text: 'Price includes VAT' }), ['inclusive', null]);
});

Deno.test('the supplier TRN is captured for the record', () => {
  assertEquals(readVat({ amount: 1, text: 'TRN 100 2345 6789 0003, excl VAT' }).trn, '100234567890003');
});

// ZERO-RATED AND EXEMPT ARE STATED ANSWERS, NOT SILENCE (sales_engineer, 13 Nov 2026, workflow audit build item 10)
Deno.test('zero-rated and exempt are read as stated: the price as written is the ex-VAT price, never held as not stated', () => {
  for (const text of ['This supply is zero-rated.', 'VAT 0% applies to these exports', 'Total AED 12,000 (0% VAT)']) {
    const v = readVat({ amount: 12000, text });
    assertEquals([v.treatment, v.price_ex_vat], ['zero_rated', 12000], text);
  }
  for (const text of ['The supply is exempt from VAT.', 'VAT-exempt supply of residential building', 'Exempt supply under Article 46']) {
    const v = readVat({ amount: 9000, text });
    assertEquals([v.treatment, v.price_ex_vat], ['exempt', 9000], text);
  }
  // a document named "VAT exemption certificate" is not the supply's treatment
  assertEquals(readVat({ amount: 9000, text: 'We can provide VAT exemption certificates on request.' }).treatment, 'not_stated');
  // the supplier's own answer on the portal is kept
  assertEquals(readVat({ amount: 5000, stated: 'exempt' }).treatment, 'exempt');
  // a VAT amount actually added is not zero-rated, whatever else the text says
  assertEquals(readVat({ amount: 1050, subtotal: 1000, vat_amount: 50, text: 'some lines zero-rated' }).treatment, 'exclusive');
});
