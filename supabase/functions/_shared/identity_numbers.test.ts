// A TRN or licence number never reaches a customer: every scrubber masks English and Arabic formats.
// deno test --no-lock --node-modules-dir=none supabase/functions/_shared/identity_numbers.test.ts
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { findTrn, maskIdentityNumbers } from './identity_numbers.ts';
import { redactText, residualScan } from './anonymise.ts';
import { maskContacts } from './quote_documents.ts';
import { scrubIdentity } from '../drawing_boq/boq_from_text.ts';

const FORMS = [
  'TRN: 100234567890003', 'TRN 100 2345 6789 0003', 'T.R.N. 100-2345-6789-0003', 'Tax Registration Number: 100234567890003',
  'VAT No. 100234567890003', 'VAT Reg No: 100 234 567 890 003', 'رقم التسجيل الضريبي: 100234567890003', 'الرقم الضريبي ١٠٠٢٣٤٥٦٧٨٩٠٠٠٣',
  'Our registration 100234567890003 applies', 'السعر شامل الضريبة 100234567890003',
];

Deno.test('every English and Arabic TRN form is found and masked', () => {
  for (const f of FORMS) {
    assertEquals(findTrn(f), '100234567890003', f);
    const m = maskIdentityNumbers(f);
    assert(!/2345|٢٣٤٥|890003/.test(m), `${f} -> ${m}`);
  }
});

Deno.test('licence and commercial-registration numbers are masked; ordinary numbers are not', () => {
  for (const f of ['Trade Licence No. 1234567', 'Licence: CN-1234567', 'CR No. 12345', 'Commercial Registration: 998877', 'رقم الرخصة التجارية: 1234567', 'رقم السجل التجاري ٧٧٨٨٩٩']) {
    assert(!/1234567|12345|998877|٧٧٨٨٩٩/.test(maskIdentityNumbers(f)), f);
  }
  assertEquals(maskIdentityNumbers('Porcelain tiles 600x600mm, 120 sqm at AED 85'), 'Porcelain tiles 600x600mm, 120 sqm at AED 85');
  assertEquals(findTrn('Invoice total 1002345678'), null);
});

Deno.test('the scrubbers in front of the customer all take it out', () => {
  const s = 'Supply and fix tiles. TRN: 100 2345 6789 0003. Trade Licence No. 1234567.';
  for (const out of [scrubIdentity(s), maskContacts(s), redactText(s, []).text]) assert(!/2345|1234567/.test(out), out);
  assert(residualScan('VAT No. 100234567890003', []).includes('pattern:trn'));
  assert(!/٢٣٤٥/.test(maskContacts('الرقم الضريبي: ١٠٠٢٣٤٥٦٧٨٩٠٠٠٣')));
});
