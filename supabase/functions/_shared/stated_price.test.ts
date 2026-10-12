// Rulings 1207/1208: the price exactly as stated, and the fee taken on the after-discount ex-VAT figure.
import { assertEquals } from 'jsr:@std/assert@1';
import { statedPrice, storedPrice, priceStated, vatStated, feeBasisLine, readDiscount, feeBaseOf, NOT_RESPONSIBLE } from './stated_price.ts';
import { revealCharge } from './reveal_fee.ts';

Deno.test('discount + VAT: 2,000 less 300 = 1,700, VAT 85 -> fee on 1,700', () => {
  const p = statedPrice({ amount: 1785, subtotal: 2000, discount_amount: 300, vat_amount: 85, text: 'VAT 5%' });
  assertEquals([p.gross_amount, p.discount_amount, p.price_ex_vat, p.fee_base, p.treatment], [2000, 300, 1700, 1700, 'exclusive']);
  assertEquals(revealCharge(p.fee_base!, 0.03).base_fee, 51);
});
Deno.test('discount as a rate, VAT-inclusive total after discount', () => {
  const p = statedPrice({ amount: 2100, gross_amount: 2333.33, discount_pct: 10, text: 'Total after discount AED 2,100 inclusive of 5% VAT' });
  assertEquals(p.treatment, 'inclusive');
  assertEquals(p.fee_base, 2000);
});
Deno.test('VAT-inclusive only (no discount): fee on the price excluding VAT', () => {
  const p = statedPrice({ amount: 1050, vat_amount: 50, text: 'Total AED 1,050 including VAT' });
  assertEquals([p.treatment, p.fee_base, p.discount_amount], ['inclusive', 1000, null]);
});
Deno.test('no VAT (not registered): fee on the stated price', () => {
  const p = statedPrice({ amount: 1700, text: 'We are not VAT registered.' });
  assertEquals([p.treatment, p.fee_base], ['not_registered', 1700]);
});
Deno.test('discount only: the only total written is before the discount -> never the gross', () => {
  const p = statedPrice({ amount: 2000, text: 'Total AED 2,000. Special discount AED 300. Prices exclude VAT.' });
  assertEquals([p.gross_amount, p.discount_amount, p.total_as_stated, p.fee_base], [2000, 300, 1700, 1700]);
});
Deno.test('readDiscount reads an amount, a rate, and Arabic', () => {
  assertEquals(readDiscount('Less: discount (15%)')?.pct, 15);
  assertEquals(readDiscount('Discount: AED 1,250.50')?.amount, 1250.5);
  assertEquals(readDiscount('خصم 300 درهم')?.amount, 300);
  assertEquals(readDiscount('no reduction offered'), null);
});
Deno.test('the customer reads "AED 2,000, after discount AED 1,700", the VAT as stated and the fee basis', () => {
  const q = { quote_amount: 1700, price_ex_vat: 1700, gross_amount: 2000, discount_amount: 300, vat_treatment: 'exclusive', vat_amount: 85 };
  assertEquals(priceStated(q, 'en'), 'AED 2,000, after discount AED 1,700');
  assertEquals(priceStated(q, 'ar'), '2,000 درهم، وبعد الخصم 1,700 درهم');
  assertEquals(vatStated(q, 'en'), 'The supplier adds VAT of AED 85: total including VAT AED 1,785, as stated.');
  assertEquals(feeBasisLine(feeBaseOf(q), 0.03, 'en'), 'Our fee: 3% of AED 1,700 = AED 51; no card fee, no VAT on our fee.');
  assertEquals(priceStated({ quote_amount: 900 }, 'en'), 'AED 900');
  assertEquals(NOT_RESPONSIBLE.ar.includes('ًا'), true);
});
Deno.test('a conditional discount is a payment term, never a cut in the fee base', () => {
  assertEquals(readDiscount('Payment: 2% discount for payment within 7 days.'), null);
  const p = statedPrice({ amount: 2000, text: 'Total AED 2,000 excluding VAT. Early payment discount 5% if paid in advance.' });
  assertEquals([p.fee_base, p.discount_amount], [2000, null]);
});
Deno.test('storedPrice: quote_amount (the column revealCharge reads) is the after-discount ex-VAT price', () => {
  const s = storedPrice(statedPrice({ amount: 1785, subtotal: 2000, discount_amount: 300, vat_amount: 85 }), 1785);
  assertEquals([s.quote_amount, s.price_ex_vat, s.gross_amount, s.discount_amount, s.amount_as_stated], [1700, 1700, 2000, 300, 1785]);
  // VAT basis not stated: held for it, and still never the gross
  const h = storedPrice(statedPrice({ amount: 2000, text: 'Total AED 2,000. Discount AED 300.' }), 2000);
  assertEquals([h.price_ex_vat, h.quote_amount], [null, 1700]);
});
