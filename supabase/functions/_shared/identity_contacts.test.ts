// identity_contacts — the title-block contacts of a non-UAE consultant are removed, and the words of a
// BOQ are not. The contact strings below are SYNTHETIC (ZZ DEMO / example.invalid / 555 numbers) but
// shaped exactly like the ones measured on the 21 Sep 2026 US bid sets (founder instruction 580).
// deno test supabase/functions/_shared/identity_contacts.test.ts
import { assertEquals } from 'jsr:@std/assert@1';
import { scrubContacts } from './identity_contacts.ts';
import { scrubIdentity } from '../drawing_boq/boq_from_text.ts';
import { residualScan } from './anonymise.ts';

const GONE = ['(555) 010-7400', '555.010.8248', '555-010-1234', 'ZZDEMODESIGN.COM', 'studio.example.ae', '1039 MAIN STREET', '4209 COUNTY ROAD 24 1/2',
  '2329 115TH AVE', 'ZZTOWN, CO  80550', 'ZZVILLE, COLORADO 80504'];
const KEPT = ['16x14 (1" LNR)', 'EF-4 550 CFM', '3" SS', '1/8" = 1\'-0"', 'Gypsum board 12.5mm, 320 m2', '2 ROAD CROSSINGS', 'pipe 3.in dia',
  '01/24/2020', 'PKA-A24KA4', 'RTU1-4-H', 'SCALE: 1/4" = 1\'-0"', 'Titus TMS 24x24, 250 cfm', 'Section 23 05 00'];

Deno.test('every non-UAE contact shape is removed', () => {
  for (const t of GONE) assertEquals(scrubContacts(t).trim(), '', t);
  for (const t of GONE) assertEquals(scrubIdentity(`call ${t} now`), 'call now', t);
  // An email is removed whole: the host inside it is not taken first, leaving "info@" behind.
  assertEquals(scrubIdentity('in 3 weeks, info@zzdemo.example.ae'), 'in 3 weeks,');
});

Deno.test('BOQ and drawing vocabulary is untouched', () => {
  for (const t of KEPT) assertEquals(scrubContacts(t), t, t);
});

Deno.test('the residual scan names them, so a page still carrying one is held', () => {
  for (const t of GONE) assertEquals(residualScan(t, []).length > 0, true, t);
  for (const t of KEPT) assertEquals(residualScan(t, []), [], t);
});
