// a_customers_text_reaches_no_supplier_with_identity_corpus.test.ts — the customer's free text, planted with identity,
// through every text gate a supplier is served from (13 Nov 2026, sales_engineer; anonymity audit REPORT_A L1/L3/L4,
// founder ledger 1683: "Dubai in general is okay … Al Barsha and Villa 15 need to be hidden").
//
// The probes are auditor A's s2 driver, verbatim; before this round 18 of its 31 inputs reached a supplier through at
// least one gate (areas, villa and plot numbers, landmarks, coordinates, what3words, a phone in words or split, an
// address with spaces round its "@", the customer's name in Arabic, the current supplier's name).
// Gates: the portal inbox and the inquiry PDF (identity_scrub.inboxField, with the customer's seed terms), the
// customer's answer to a supplier question (messages_api stripContact), and the bare save scrub with the buyer's name
// (scrubIdentity — the shape every other door reaches for; the new_inquiry e-mail must move to inboxField, which F2's
// change to customer_api/lib/matching.ts does, so the probes that only a seed list can catch are not asked of it).
// deno test --no-lock supabase/functions/supplier_api/a_customers_text_reaches_no_supplier_with_identity_corpus.test.ts
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { inboxField, scrubIdentity } from './identity_scrub.ts';
import { seedTerms } from '../_shared/anonymise.ts';
import { stripContact } from '../messages_api/strip_contact.ts';

const CUST = { name: 'ZZ DEMO Omar Haddad', email: 'omar.haddad@zz-mail.example.invalid', phone: '+971550000499', project: 'ZZ DEMO Barsha Garden Villa' };
const seeds = seedTerms(CUST);
// [probe, input, what must not reach a supplier, needs the seed list]
const PROBES: [string, string, string[], boolean?][] = [
  ['name', 'Hi, I am Omar Haddad, I need my 3 bathrooms re-tiled.', ['Haddad']],
  ['name_ar', 'أنا عمر حداد وأحتاج إلى تبليط ثلاثة حمامات.', ['حداد']],
  ['company', 'Quote for Haddad Holdings LLC, our villa bathrooms.', ['Haddad']],
  ['company_noform', 'Work for Haddad Family Office, 3 bathrooms.', ['Haddad'], true],
  ['mobile_spaced', 'Call me on 055 000 0499 for the site visit.', ['0499']],
  ['mobile_dashes', 'my number 055-000-0499', ['0499']],
  ['mobile_intl', 'WhatsApp +971 55 000 0499', ['0499']],
  ['mobile_arabic_digits', 'رقمي ٠٥٥ ٠٠٠ ٠٤٩٩', ['٠٤٩٩']],
  ['mobile_words', 'call zero five five, zero zero zero, zero four nine nine', ['nine nine']],
  ['mobile_split', 'my number is 055 000 then 0499', ['0499']],
  ['email', 'mail omar.haddad@zz-mail.example.invalid', ['haddad', 'zz-mail']],
  ['email_spaces', 'mail omar.haddad @ zz-mail.example.invalid', ['haddad', 'zz-mail']],
  ['email_at_word', 'write to omarhaddad at gmail dot com', ['omarhaddad']],
  ['villa_area', 'Villa 15, Al Barsha 2, Dubai', ['Villa 15', 'Barsha']],
  ['villa_area_noemirate', 'Site is Villa 15 Al Barsha 2', ['15', 'Barsha']],
  ['area_only', 'The house is in Al Barsha 2 near Mall of the Emirates', ['Barsha', 'Mall of']],
  ['community_ar', 'الفيلا في البرشاء 2 قرب مول الإمارات، فيلا رقم 15', ['البرشاء', '15', 'مول']],
  ['plot', 'Plot No. 373-4512 in Al Barsha South', ['4512', 'Barsha']],
  ['makani', 'Makani 12345 67890', ['67890']],
  ['makani_label', 'Makani number: 1234567890', ['1234567890']],
  ['building', 'Apartment 1204, Marina Gate 2 tower, Dubai Marina', ['1204', 'Marina']],
  ['project', 'For the ZZ DEMO Barsha Garden Villa project', ['Barsha', 'Garden Villa'], true],
  ['project_glued', 're:BarshaGardenVilla tiling', ['BarshaGardenVilla'], true],
  ['consultant', 'Consultant is ZZ DEMO Cedar Engineering Consultants, Eng. Rami Khoury', ['Cedar', 'Khoury']],
  ['current_supplier', 'I already have a quote from Falcon Trading for AED 32,816, can you beat it?', ['Falcon']],
  ['link', 'Photos here: https://photos.example.invalid/omar/bath', ['photos.example']],
  ['drive_link', 'see drive.google.com/drive/folders/1AbCdEf', ['1AbCdEf']],
  ['coords', 'Location 25.1123, 55.2001', ['25.1123']],
  ['maps_link', 'https://maps.app.goo.gl/AbC123xyz', ['AbC123xyz']],
  ['w3w', 'what3words ///filled.count.soap', ['filled.count']],
  ['instagram', 'see my insta @omar.haddad.home', ['haddad']],
];
Deno.test('a customer\'s planted identity reaches no supplier through the portal, the answer or the save scrub', () => {
  const left: string[] = [];
  for (const [k, text, gone, seedOnly] of PROBES) {
    const ib = inboxField<string>(text, CUST.name, seeds, []);
    const outs: Record<string, string> = { portal: ib.withheld ? '' : String(ib.boq), answer: stripContact(text, [CUST.name], [CUST.project]) };
    if (!seedOnly) outs.save = scrubIdentity(text, CUST.name, []) ?? '';
    for (const [where, out] of Object.entries(outs)) for (const g of gone) if (out.toLowerCase().includes(g.toLowerCase())) left.push(`${k} ${where}: ${JSON.stringify(out)}`);
  }
  assertEquals(left, []);
});
Deno.test('the emirate survives every gate (ruling 1683: "Dubai in general is okay")', () => {
  for (const text of ['Villa 15, Al Barsha 2, Dubai', 'Site is Villa 15 Al Barsha 2', 'The house is in Al Barsha 2 near Mall of the Emirates']) {
    const ib = inboxField<string>(text, CUST.name, seeds, []);
    for (const out of [String(ib.boq), stripContact(text, [CUST.name], [CUST.project]), scrubIdentity(text, CUST.name, []) ?? '']) assert(out.includes('Dubai'), `${text} -> ${out}`);
  }
  assert(stripContact('الفيلا في البرشاء 2', [CUST.name]).includes('دبي'));
});

Deno.test('a stored site is reduced, not painted out: the supplier reads "in Dubai" (mutant N4: reducibleSeed ignored)', () => {
  const s2 = seedTerms({ ...CUST, address: 'Villa 15, Al Barsha 2' });
  const out = inboxField<string>('Renovation of two bathrooms at Villa 15, Al Barsha 2', CUST.name, s2, []);
  assertEquals(out.boq, 'Renovation of two bathrooms in Dubai');
});
