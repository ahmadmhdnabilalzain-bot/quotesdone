// identity_text.test.ts — every leak the planted-identity run measured on 3 Nov 2026 (scripts/e2e/
// identity_never_leaks_before_reveal.mjs, seed 20261103), replayed through the scrubbers that let it through, plus the
// BOQ and quotation wording that must come out unchanged.
// deno test --no-lock supabase/functions/_shared/identity_text.test.ts
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { knownNameRe, scrubIdentityText } from './identity_text.ts';
import { scrubIdentity as supplierScrub } from '../supplier_api/identity_scrub.ts';
import { scrubIdentity as boqScrub } from '../drawing_boq/boq_from_text.ts';
import { maskContacts } from './quote_documents.ts';
import { stripContact } from '../messages_api/strip_contact.ts';
import { residualScan } from './anonymise.ts';

const NAME = 'ZZ Crescent Green AM9 Engineering Consultants LLC';
// The printed forms that reached the other side, each with the substring that must be gone.
const LEAKED: [string, string][] = [
  ['Cheque in favour of ZZ Crescent Green AM9 Engineering Consultants LLC.', 'Crescent Green AM9'],
  ['Transfer to IBAN AE09 0580 0009 6788 6290 627.', '6788'],
  ['IBAN: AE280040006055553370809', '0060555'],
  ['P. O. Box 59508', '59508'], ['PO BOX: 14446', '14446'], ['POB 21759', '21759'], ['ص.ب ٥٦١٤٣', '٥٦١٤٣'],
  ['Trade licence TL 273158', '273158'], ['CN-974461', '974461'], ['D.E.D. Licence 780159', '780159'],
  ['Hotline (050) 000 0076', '0076'], ['Mob 971500000064', '0064'], ['+٩٧١ ٥٠ ٠٠٠ ٠٠٦١', '٠٠٦١'], ['٠٤ ٠٠٠ ٠٠٥٥', '٠٠٥٥'], ['(04) 000 0044', '0044'],
  ['Showroom: Office 735, ZZ Palm IU8 Tower, Al Quoz Industrial Area 3, Dubai.', 'IU8 Tower'],
  ['Al Katheeb Al Akhdar Trading standard conditions apply.', 'Katheeb'],
  ['شركة النخلة الملكي للديكور ذ.م.م', 'النخلة'],
  ['Prepared by: ZZ Omar Qasimi, Sales Engineer', 'Qasimi'], ['Thanks, ZZ Rashid Ketbi - quotes', 'Ketbi'],
  ['المسؤول: زد زد عمر المزروعي.', 'المزروعي'],
];
Deno.test('every leaked shape is gone through each scrubber that let it through', () => {
  for (const [text, gone] of LEAKED) {
    const outs = { supplier_api: supplierScrub(text, NAME, []) ?? '', drawing_boq: boqScrub(text), quote_documents: maskContacts(text, [NAME]), messages_api: stripContact(text, [NAME]) };
    for (const [who, out] of Object.entries(outs)) assert(!out.includes(gone), `${who} kept "${gone}" of "${text}": ${out}`);
  }
});
Deno.test('a known name is matched whole, by its core, by two consecutive words, and next to Arabic', () => {
  const re = knownNameRe(NAME)!;
  for (const s of ['ZZ Crescent Green AM9 Engineering Consultants LLC', 'zz crescent green am9', 'the Crescent Green AM9 series', 'شركة ZZ Crescent Green AM9 للتجارة']) assert(re.test(s), s), re.lastIndex = 0;
  const ar = knownNameRe('شركة النور للتجارة')!; assert(ar.test('من شركة النور للتجارة'));
  // "Consultants" no longer loses its "Co": the old pattern matched none of these.
  assertEquals(supplierScrub(`payable to ${NAME} only`, NAME, []), 'payable to [removed] only');
});
Deno.test('a residual Arabic-Indic or bracketed phone, an IBAN, a P.O. Box or a short licence holds a drawing page', () => {
  for (const s of ['٠٤ ٠٠٠ ٠٠١٤', '(04) 000 0019', 'TL 614867', 'IBAN AE09 0580 0009 6788 6290 627', 'ص.ب ٥٦١٤٣']) assert(residualScan(s, ['zz demo']).length > 0, s);
});
// What must come out unchanged: the wording a supplier prices from and a customer compares on.
const KEEP = ['Supply and install 2 TR ducted split unit 6 nos 4200.00 25200.00', 'GI ductwork with insulation 85 sqm 180.00', 'Copper piping 1/2" + 7/8" insulated 60 lm',
  '14 days from PO.', '50% advance, 50% on completion.', 'Thanks for the opportunity to quote.', 'Cooling Tower CT-1 1 nos', 'Main Building ground floor', 'Validity: 30 days',
  'Qty 0.50 Rate 1250.00', 'AED 9,971,500.00', 'FCU-1 to FCU-6, 2 TR each', 'بلاط بورسلين 600x600 الكمية 120 متر مربع', 'Room 0450 x 1200', 'Unit 6, 2 TR', 'Contact the Majlis ceiling height 3.2 m'];
Deno.test('ordinary BOQ and quotation wording is untouched', () => {
  for (const s of KEEP) assertEquals(scrubIdentityText(s).replace(/\s+/g, ' ').trim(), s, s);
});
