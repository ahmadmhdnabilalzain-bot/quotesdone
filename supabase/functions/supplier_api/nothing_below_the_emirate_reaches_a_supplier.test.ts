// Nothing below the emirate reaches a supplier before a reveal, through any door this function owns (13 Nov 2026,
// sales_engineer; founder ruling 1683: "Dubai in general is okay ... Al Barsha and Villa 15 need to be hidden when they are
// shared with the supplier"; anonymity audit A, L1 and L3).
//   deno test --no-lock --node-modules-dir=none --allow-read=. supabase/functions/supplier_api/nothing_below_the_emirate_reaches_a_supplier.test.ts
// The doors: the supplier inbox JSON (summary through supplierField, the brief through supplierBrief, the same calls inbox.ts
// makes), the inquiry PDF a supplier downloads (inquiryDocument on that row, rendered and read back), the new-inquiry e-mail
// (newInquiryBody, what customer_api matching.ts sends) and its WhatsApp twin's parameters (send_whatsapp varsFor).
// The planted corpus is the auditor's (REPORT_A L1/L3): each place is STATED by the customer (in the site key, or in an older
// row's address key) and then repeated by a careless intake model in the summary and the brief. A place the customer never
// stated anywhere is the shared text backstop's (_shared/identity_text.ts), not this test's.
// deno-lint-ignore-file no-explicit-any
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { norm } from '../_shared/anonymise.ts';
import { ADDRESS_KEYS, belowEmirate, emirateIn, keylessPlaceKeys, oneOfSeven, reducePlace, siteParts, siteSeeds, splitSite, supplierSpec, tidyWithheld } from '../_shared/site_location.ts';
import { awardedOtherBody, forSuppliers, newInquiryBody, requestSeeds, supplierBrief, supplierCopy, supplierField, textForSuppliers, type Buyer, type OwnerRead } from './what_a_supplier_receives.ts';
import { editDecision } from '../customer_api/lib/edit_summary.ts';
import { inquiryDocument, type InquiryDocRow } from '../_shared/quote_documents.ts';
import { renderPdf } from '../pdf_native/render.ts';
import { linesFromRuns, pdfPages } from '../_shared/pdf_text_positions.ts';
import { varsFor } from '../send_whatsapp/templates.ts';

const BUYER: Buyer = { name: 'ZZ DEMO Omar Haddad', email: 'omar.haddad@zz-mail.example.invalid', phone: '+971550000499', project: 'ZZ DEMO Barsha Garden Villa' };
type Case = { name: string; emirate: string; spec: Record<string, unknown>; site?: string; summary: string; never: string[]; must: string[] };
// The over-redaction rows ride on every case: quantities, sizes, levels, model numbers, standards, warranty, origin, the emirate.
const BRIEF = { scope: 'Wall tiles 300x600mm about 40 m2, two Grohe Rapid SL 38772001 concealed WCs to BS EN 997', floor: 'ground floor, G+1', warranty: '2 years', origin: 'made in Italy' };
const KEEP = ['300x600mm', '40 m2', 'Grohe Rapid SL 38772001', 'BS EN 997', 'ground floor', 'G+1', '2 years', 'made in Italy'];
const CASES: Case[] = [
  { name: 'the founder\'s own example, no comma (portal kept "█ Al Barsha 2", the e-mail kept it whole)', emirate: 'Dubai', site: 'Villa 15, Al Barsha 2, near Mall of the Emirates',
    spec: { location: 'Villa 15 Al Barsha 2 Dubai', ...BRIEF, access: 'gate of Villa 15 Al Barsha 2' }, summary: 'Bathroom renovation at Villa 15 Al Barsha 2 near Mall of the Emirates, Dubai',
    never: ['Villa 15', 'Barsha', 'Mall of the Emirates'], must: ['Dubai'] },
  { name: 'Al Barsha South', emirate: 'Dubai', spec: { location: 'Al Barsha South, Dubai', ...BRIEF }, summary: 'Pool repair for a villa in Al Barsha South', never: ['Barsha'], must: [] },
  { name: 'a tower in a community', emirate: 'Dubai', spec: { location: 'Marina Gate 2 tower, Dubai Marina, Dubai', ...BRIEF }, summary: 'AC service in an apartment at Marina Gate 2 tower, Dubai Marina, Dubai',
    never: ['Marina Gate', 'Dubai Marina'], must: ['Dubai'] },
  { name: 'Arabic', emirate: 'Dubai', site: 'فيلا رقم 15، البرشاء 2، دبي', spec: { location: 'دبي', ...BRIEF }, summary: 'ترميم حمام في فيلا رقم 15 البرشاء 2', never: ['البرشاء', 'فيلا رقم 15'], must: [] },
  { name: 'coordinates and a three-word address', emirate: 'Dubai', site: '25.1123, 55.2001; ///demo.falcon.tiles', spec: { location: 'Dubai', ...BRIEF, access: 'pin 25.1123, 55.2001' },
    summary: 'Gate motor repair, pin 25.1123, 55.2001', never: ['25.1123', '55.2001', 'demo.falcon'], must: [] },
  // the three live ZZ DEMO rows: an older row, its area in the summary and in the address key, no site key (re-scrubbed at the door)
  { name: 'older row: Al Nahda', emirate: 'Sharjah', spec: { location: 'Al Nahda, Sharjah', ...BRIEF }, summary: 'Kitchen fit-out in Al Nahda, Sharjah', never: ['Nahda'], must: ['Kitchen fit-out in Sharjah'] },
  { name: 'older row: Khalifa City', emirate: 'Abu Dhabi', spec: { location: 'Khalifa City, Abu Dhabi', ...BRIEF }, summary: 'Villa renovation in Khalifa City, Abu Dhabi', never: ['Khalifa City'], must: ['Abu Dhabi'] },
  { name: 'older row: Business Bay', emirate: 'Dubai', spec: { location: 'Business Bay, Dubai', ...BRIEF, hours: 'business hours only' }, summary: 'Office partitions in Business Bay, Dubai', never: ['Business Bay'], must: ['business hours only'] },
  // an industrial area must not erase the word "industrial" from the scope (the phrase travels whole)
  { name: 'Industrial Area 13 against "industrial grade"', emirate: 'Sharjah', spec: { location: 'Industrial Area 13, Sharjah', ...BRIEF, coating: 'industrial grade epoxy 3mm' }, summary: 'Epoxy flooring for a warehouse in Industrial Area 13, Sharjah',
    never: ['Industrial Area 13'], must: ['industrial grade epoxy 3mm', 'Sharjah'] },
  // L3: the e-mail ran the buyer's name only; these left in the e-mail and were caught in the portal
  { name: 'the e-mail leaks of audit A, L3', emirate: 'Dubai', spec: { location: 'Dubai', ...BRIEF },
    summary: 'Fit-out of the ZZ DEMO Barsha Garden Villa (re:BarshaGardenVilla) for Haddad Family Office, Plot No. 373-4512, Makani 12345 67890, Apartment 1204',
    never: ['Barsha', 'BarshaGarden', 'Haddad', '373-4512', '12345 67890', 'Apartment 1204'], must: [] },
];
const low = (s: string) => s.toLowerCase();
const found = (t: string, list: string[]) => list.filter((x) => low(t).includes(low(x)));

async function doors(c: Case) {
  // create_inquiry: the exact place goes under the customer-only key, the address key keeps the emirate
  const stored = splitSite({ ...c.spec }, c.emirate, c.site);
  const seeds = requestSeeds(BUYER, stored);
  const summary = supplierField<string>(c.summary, BUYER, seeds);
  const brief = supplierBrief(stored, c.emirate, BUYER, seeds);
  const row: InquiryDocRow = { id: 'd3a0c4a1-0b0e-4c21-9f00-00000000e101', rfq_no: 160601, category: 'bathroom_renovation', emirate: c.emirate, summary: summary.value, budget: null, scope_type: 'single',
    created_at: '2026-11-13T06:00:00.000Z', spec: brief.value, boq: null, boq_withheld: false, documents: [], drawing_pages_failed: 0 };
  const pr = await renderPdf(inquiryDocument({ inquiry: row, lang: 'en', date: '13 November 2026' }).body, { fetchBytes: () => Promise.resolve(null) });
  assert(pr.ok, 'the inquiry PDF did not render');
  const pdf = linesFromRuns(await pdfPages((pr as any).bytes));
  const email = newInquiryBody({ resolved: true, buyer: BUYER, spec: stored, summary: c.summary, budget: null, extra: '', category: 'bathroom_renovation', emirate: c.emirate });
  const wa = JSON.stringify(varsFor('supplier_new_inquiry', { subject: 'New job request on QuotesDone', body: email }));
  return { stored, json: JSON.stringify(row), pdf, email, wa, withheld: summary.withheld || brief.withheld };
}

for (const c of CASES) {
  Deno.test(`nothing below the emirate: ${c.name}`, async () => {
    const d = await doors(c);
    for (const [door, text] of [['inbox JSON', d.json], ['inquiry PDF', d.pdf], ['new-inquiry e-mail', d.email], ['WhatsApp parameters', d.wa]] as const) {
      assertEquals(found(text, c.never), [], `${door} carries: ${text.slice(0, 400)}`);
    }
    // what a supplier needs survives the same doors (the e-mail carries the summary only)
    assertEquals([...KEEP, ...c.must].filter((m) => !d.json.includes(m)), [], 'inbox JSON lost content: ' + d.json.slice(0, 600));
    assertEquals(c.must.filter((m) => !d.pdf.includes(m) && !d.email.includes(m)), []);
    assert(d.pdf.includes(c.emirate), 'the emirate is on the PDF');
    // the customer and the revealed supplier keep every word of the site
    assert(String(d.stored.site_location || '').length > 0 || !belowEmirate(c.spec.location), 'the exact site was not kept for the customer');
  });
}

Deno.test('the site key: what is a place, what is not, and what a supplier is given in its place', () => {
  assertEquals(siteParts('Villa 15, Al Barsha 2, Dubai (near Mall of the Emirates)'), ['Villa 15', 'Al Barsha 2', 'Mall of the Emirates']);
  assertEquals(siteParts('Dubai'), []);
  assertEquals(siteParts('a villa, ground floor, Abu Dhabi'), []);
  assertEquals(siteParts('Warehouse, G+1, Sharjah, UAE'), []);
  assertEquals(emirateIn('Al Barsha 2, Dubai'), 'Dubai');
  assertEquals(emirateIn('Dubai or Sharjah'), null);
  assert(siteSeeds({ location: 'Al Barsha 2, Dubai' }).includes('barsha'));
  assert(!siteSeeds({ location: 'Industrial Area 13, Sharjah' }).includes('industrial'));
  assertEquals(supplierSpec<Record<string, unknown>>({ location: 'Villa 15, Al Barsha 2', site_location: 'Villa 15, Al Barsha 2', old_supplier_terms: ['Falcon'], floor: 'G+1' }, null),
    { location: '[site details withheld]', floor: 'G+1' });
  assertEquals(splitSite({ location: 'Villa 15, Al Barsha 2, Dubai' }, 'Dubai'), { location: 'Dubai', site_location: 'Villa 15, Al Barsha 2, Dubai' });
  assertEquals(splitSite({ location: 'Dubai' }, 'Dubai', 'Villa 15, Al Barsha 2'), { location: 'Dubai', site_location: 'Villa 15, Al Barsha 2' });
});

Deno.test('the owner could not be read: the e-mail carries the trade and the emirate only', () => {
  const body = newInquiryBody({ resolved: false, buyer: { name: null }, spec: null, summary: 'Villa 15 Al Barsha 2 bathroom', budget: 'AED 20k, call Omar', extra: ' A draft bill of quantities is attached.', category: 'bathroom_renovation', emirate: 'Dubai' });
  assertEquals(body, 'A customer is requesting quotes for: Bathroom renovation work (Dubai). Log in to your QuotesDone supplier portal to quote.');
});

// ── THE INDEPENDENT REVIEW OF 13 NOV 2026 (F2 DOORS 1). Each block below failed before its fix. ─────────────────────────────

const OWNER = (spec: Record<string, unknown>): OwnerRead => ({ resolved: true, buyer: BUYER, spec, emirate: 'Dubai', briefSource: null });
const NEVER = ['Villa 15', 'Barsha', 'Mall of the Emirates', 'Makani', '12345 67890', 'Falcon', 'Haddad'];

Deno.test('item 1: the texts e-mailed to every matched supplier (note, missing specs, clarification answer, its English replay) pass the gate', async () => {
  const spec = { location: 'Dubai', site_location: 'Villa 15, Al Barsha 2, near Mall of the Emirates' };
  const access = 'Access is via the back gate of Villa 15, Al Barsha 2, near Mall of the Emirates; Makani 12345 67890.';
  const t = forSuppliers(access, OWNER(spec));
  assertEquals(found(String(t ?? ''), NEVER), [], String(t));
  assertEquals(forSuppliers('The site is Villa 15, Al Barsha 2, near Mall of the Emirates.', OWNER(spec))?.match(/Barsha|Villa 15|Mall/) ?? null, null);
  // the owner could not be read: nothing at all goes
  assertEquals(forSuppliers('Two coats of paint, ground floor only', { resolved: false }), null);
  // the replay reads the owner itself (finishEnglish): a stub database with the request and its owner
  const rows: Record<string, unknown> = { inquiries: { customer_id: 'c1', project_id: null, spec, emirate: 'Dubai', brief_source: null }, customers: { full_name: BUYER.name, email: BUYER.email, phone: BUYER.phone } };
  const db = { from: (t: string) => ({ select: () => ({ eq: () => ({ maybeSingle: async () => ({ data: rows[t] ?? null, error: null }) }) }) }) };
  const replay = await textForSuppliers(db, 'i1', 'Please enter through Villa 15 Al Barsha 2 gate; ground floor, 2 coats of paint.');
  assertEquals(found(String(replay ?? ''), NEVER), [], String(replay));
  assert(String(replay).includes('ground floor') && String(replay).includes('2 coats of paint'), String(replay));
});

Deno.test('item 2: every checklist key that asks where is reduced, the floor stays (location_floor, property_location, access, a keyless field)', async () => {
  const cases: [Record<string, unknown>, string[], string[]][] = [
    [{ location_floor: 'Al Barsha 2, 3rd floor' }, ['Barsha'], ['3rd floor', 'Dubai']],
    [{ property_location: 'apartment, Dubai Marina, 12th floor' }, ['Marina'], ['apartment', '12th floor']],
    [{ emirate_location: 'JLT Cluster D, Dubai' }, ['JLT', 'Cluster D'], ['Dubai']],
    [{ access: 'no lift, narrow stairs, back gate of Villa 15' }, ['Villa 15'], ['no lift', 'narrow stairs', 'back gate']],
    [{ property: 'villa, 350 m2, 5 rooms, Al Barsha' }, ['Barsha'], ['villa', '350 m2', '5 rooms']],
    [{ emirate_area: 'Arabian Ranches 2, Dubai' }, ['Ranches'], ['Dubai']],
  ];
  for (const [answer, never, keep] of cases) {
    const stored = splitSite({ ...answer }, 'Dubai');
    const out = JSON.stringify(supplierBrief(stored, 'Dubai', BUYER, requestSeeds(BUYER, stored)).value);
    assertEquals(found(out, never), [], out);
    assertEquals(keep.filter((k) => !out.includes(k)), [], out);
    assert(String(stored.site_location || '').length > 0, 'the customer keeps his own words');
  }
  // a keyless "Emirate / area" question (the interview's field_N) is recorded per request and reduced like a named one
  const keys = keylessPlaceKeys([{ question: 'Area (sqm)' }, { question: 'Emirate / area' }]);
  assertEquals(keys, ['field_2']);
  const k = splitSite({ field_1: '120', field_2: 'Al Barsha 2, Dubai' }, 'Dubai', undefined, keys);
  assertEquals(JSON.stringify(supplierBrief(k, 'Dubai', BUYER, requestSeeds(BUYER, k)).value).includes('Barsha'), false);
  assert(ADDRESS_KEYS.includes('location_floor'));
});

Deno.test('item 4: a revealed supplier gets the customer and his site, never the old supplier', () => {
  const row = { summary: 'Same tiles as quoted by Falcon at AED 32,816.70. Villa 15, Al Barsha 2.', brief_source: 'quotation', emirate: 'Dubai',
    spec: { location: 'Dubai', site_location: 'Villa 15, Al Barsha 2', old_supplier_terms: ['ZZ DEMO Falcon Trading LLC', 'Falcon'] },
    boq: { boq: [{ description: 'Tiles 300x600 (RAK Ceramics)', qty: 86, unit: 'm2', basis: 'rate 1,180, amount 8,170.00' }] }, budget: null };
  const r = supplierCopy(row, { revealed: true, ownerResolved: true, buyer: BUYER });
  assertEquals((r.spec as any).site_location, 'Villa 15, Al Barsha 2');
  assertEquals('old_supplier_terms' in (r.spec as any), false);
  assertEquals(found(JSON.stringify(r.boq) + String(r.summary), ['1,180', '8,170', '32,816']), []);
});

Deno.test('M13 and M15: before a reveal the inbox row is gated, a quotation\'s BOQ rebuilt, and the customer-only keys gone', () => {
  const row = { summary: 'Bathroom tiling for Villa 15, Al Barsha 2 like the Falcon offer', brief_source: 'quotation', emirate: 'Dubai',
    spec: { location: 'Villa 15, Al Barsha 2, Dubai', site_location: 'Villa 15, Al Barsha 2', old_supplier_terms: ['Falcon'], floor: 'ground floor' },
    boq: { boq: [{ description: 'Tiles 300x600 (RAK Ceramics)', qty: 86, unit: 'm2', basis: 'rate 1,180, amount 8,170.00' }] }, budget: 'about 30k' };
  const r = supplierCopy(row, { revealed: false, ownerResolved: true, buyer: BUYER });
  const all = JSON.stringify(r);
  assertEquals(found(all, ['Barsha', 'Villa 15', 'Falcon', 'site_location', 'old_supplier_terms', '1,180', '8,170']), [], all);
  assert(all.includes('ground floor') && all.includes('300x600') && all.includes('RAK Ceramics'), all);
  const none = supplierCopy(row, { revealed: false, ownerResolved: false, buyer: BUYER });
  assertEquals([none.summary, none.spec, none.boq, none.budget], [null, null, null, null]);
});

Deno.test('M7: the inquiry PDF never prints a customer-only key, whatever reaches it', async () => {
  const row: InquiryDocRow = { id: 'd3a0c4a1-0b0e-4c21-9f00-00000000e102', category: 'painting', emirate: 'Dubai', summary: 'Repaint a villa', budget: null, scope_type: 'single',
    created_at: '2026-11-13T06:00:00.000Z', spec: { location: 'Dubai', site_location: 'Villa 15, Al Barsha 2', old_supplier_terms: ['Falcon'], site_keys: ['field_2'], coats: '2 coats' }, boq: null, boq_withheld: false, documents: [], drawing_pages_failed: 0 };
  const pr = await renderPdf(inquiryDocument({ inquiry: row, lang: 'en', date: '13 November 2026' }).body, { fetchBytes: () => Promise.resolve(null) });
  const text = linesFromRuns(await pdfPages((pr as any).bytes));
  assertEquals(found(text, ['Barsha', 'Villa 15', 'Falcon', 'field_2', 'Site location', 'Old supplier']), [], text);
  assert(text.includes('2 coats'));
});

Deno.test('M9 and item 7: edit_inquiry checks only what changed, keeps the customer\'s words, and says which part cannot be sent', () => {
  const owner = { resolved: true, buyer: BUYER, spec: { location: 'Dubai', site_location: 'Unit 1204, Tower 2, Al Barsha 2' } };
  // a budget-only edit with the summary re-sent unchanged is never refused (it was a permanent 422)
  const same = 'Replace 4 split AC units, outdoor unit stand, cooling tower motor';
  const a = editDecision({ summary: same, budget: '30k' }, { summary: same }, owner);
  assert(a.ok && !('summary' in a.patch) && a.patch.budget === '30k', JSON.stringify(a));
  // a changed summary the gate can serve is stored AS WRITTEN (never "Repaint villa in █")
  const b = editDecision({ summary: 'Replace 6 split AC units on the ground floor' }, { summary: same }, owner);
  assert(b.ok && b.patch.summary === 'Replace 6 split AC units on the ground floor', JSON.stringify(b));
  // one that names the site is refused, naming the part
  const c = editDecision({ summary: 'Repaint the re:MarsaHeightsVilla unit' }, { summary: same }, { ...owner, spec: { site_location: 'Marsa Heights, Dubai' } });
  assert(!c.ok && c.status === 422 && /marsa ?heights/i.test(String((c.body as any).message)), JSON.stringify(c));
  // the emirate is one of the seven
  assert(!editDecision({ emirate: 'Dubai Marina' }, { summary: same }, owner).ok);
  assertEquals((editDecision({ emirate: 'sharjah' }, { summary: same }, owner) as any).patch.emirate, 'Sharjah');
  assertEquals(oneOfSeven('Abu Dhabi'), 'Abu Dhabi');
});

Deno.test('item 7: a site seed is the phrase with its number, never the bare premises word', () => {
  const stored = splitSite({ location: 'Unit 1204, Tower 2, Gate 3, Springs 3, Street 12, Phase 2, Cluster 4, Hall 2, Room 5, Dubai' }, 'Dubai');
  const seeds = requestSeeds(BUYER, stored);
  for (const w of ['unit', 'tower', 'gate', 'springs', 'street', 'phase', 'cluster', 'hall', 'room']) assert(!seeds.includes(w), w + ' became a seed');
  const scope = 'Split AC units 2.5 TR, cooling tower motor, outdoor unit stand, gate valve DN100, door closer to the hall and the gas room, Unit 1204 access';
  const out = String(supplierField<string>(scope, BUYER, seeds).value);
  for (const k of ['Split AC units 2.5 TR', 'cooling tower motor', 'outdoor unit stand', 'gate valve DN100', 'the hall', 'gas room']) assert(out.includes(k), out);
  assert(!out.includes('1204'), out);
});

Deno.test('M10: the not-chosen notice is gated', () => {
  const body = awardedOtherBody('Bathroom works at Villa 15, Al Barsha 2 near Mall of the Emirates', OWNER({ site_location: 'Villa 15, Al Barsha 2, near Mall of the Emirates' }));
  assertEquals(found(body, NEVER), [], body);
});

Deno.test('M11: the old supplier\'s terms are seeds at every door', () => {
  const spec = { location: 'Dubai', old_supplier_terms: ['ZZ DEMO Falcon Trading LLC', 'Falcon'] };
  const out = String(supplierField<string>('Same tiles the Falcon people offered, Falcon grey 300x600', BUYER, requestSeeds(BUYER, spec)).value);
  assert(!/falcon/i.test(out) && out.includes('300x600'), out);
});

Deno.test('the withheld place reads as a sentence', () => {
  assertEquals(tidyWithheld('Renovation of two bathrooms at [removed]', 'Dubai'), 'Renovation of two bathrooms in Dubai');
  assertEquals(tidyWithheld('Kitchen fit-out in █, Sharjah', 'Sharjah'), 'Kitchen fit-out in Sharjah');
  // the shared text backstop's place reducer leaves "at █ near Dubai" (measured on the merge with its branch, 13 Nov 2026)
  assertEquals(tidyWithheld('Renovation of two bathrooms at █ near Dubai', 'Dubai'), 'Renovation of two bathrooms in Dubai');
  assertEquals(reducePlace('Al Barsha 2, 3rd floor', 'Dubai').value, 'Dubai, 3rd floor');
});

// ── THE SECOND REVIEW OF 13 NOV 2026 (F2 DOORS 2) ────────────────────────────────────────────────────────────────────────

// 40 access answers as customers write them (the reviewer measured 31 of 40 losing what a supplier prices by, all 5 Arabic).
// Those with no place must reach the supplier word for word; those with a premises number lose only that.
const ACCESS_PLAIN = ['service lift available', 'work only after 6 pm', 'building management NOC required', 'no parking for trucks', 'goods lift max 1.5 tons',
  'crane access from street side', 'height restriction 2.5m at entrance', 'stairs only, no lift', 'security pass needed for each worker', 'working hours 8 am to 5 pm, Saturday to Thursday',
  'no noisy work on Fridays', 'loading bay at the back, 3m wide', 'basement parking clearance 2.1m', 'occupied villa, family at home', 'access through the garden, no vehicle access',
  'pool area reachable only by hand', 'freight elevator 2,000 kg, book 24 hours ahead', 'site office on ground floor', 'trucks up to 10 tons allowed', 'night work allowed after 10 pm',
  'mall rules: deliveries before 9 am only', 'permit from the community management needed', 'tower rules: no drilling after 6 pm', 'water and power available on site', 'narrow road, small truck only',
  'scaffolding allowed on the facade', 'roof access by internal staircase', 'gate code given on the day', 'pets in the house, please close doors', 'tenant must be informed 48 hours before',
  'لا يوجد مصعد', 'العمل بعد الساعة 6 مساء فقط', 'يوجد مصعد خدمة', 'ممنوع وقوف الشاحنات', 'يلزم تصريح من إدارة المبنى'];
const ACCESS_PLACED: [string, string[], string[]][] = [
  ['use the back gate of Villa 15', ['Villa 15'], ['back gate']],
  ['deliveries to Gate 3 only, max 3 tons', ['Gate 3'], ['deliveries', 'max 3 tons']],
  ['Unit 1204 is on the 12th floor, service lift available', ['1204'], ['12th floor', 'service lift available']],
  ['pin 25.1123, 55.2001; crane needed', ['25.1123', '55.2001'], ['crane needed']],
  ['المدخل من فيلا رقم 15، لا يوجد مصعد', ['فيلا رقم 15'], ['لا يوجد مصعد']],
];
Deno.test('item 1 (second review): 40 access answers keep everything a supplier prices by and lose only a premises number', () => {
  assertEquals(ACCESS_PLAIN.length + ACCESS_PLACED.length, 40);
  let lost = 0, leaked = 0;
  for (const key of ['access', 'access_constraints', 'emirate_access']) {
    for (const a of ACCESS_PLAIN) {
      const stored = splitSite({ [key]: a, location: 'Dubai' }, 'Dubai');
      const out = (supplierBrief(stored, 'Dubai', BUYER, requestSeeds(BUYER, stored)).value as any)?.[key];
      if (out !== a) { lost++; console.log('LOST', key, JSON.stringify(a), '->', JSON.stringify(out)); }
      assert(!siteSeeds(stored).some((sd) => norm(a).includes(sd)), 'an access answer became a seed: ' + a);
    }
    for (const [a, never, keep] of ACCESS_PLACED) {
      const stored = splitSite({ [key]: a, location: 'Dubai' }, 'Dubai');
      const out = String((supplierBrief(stored, 'Dubai', BUYER, requestSeeds(BUYER, stored)).value as any)?.[key] ?? '');
      if (found(out, never).length) { leaked++; console.log('LEAKED', key, out); }
      if (keep.some((k) => !out.includes(k))) { lost++; console.log('LOST', key, JSON.stringify(a), '->', JSON.stringify(out)); }
      assert(String(stored.site_location).includes(never[0]), 'the customer keeps the place he wrote');
    }
  }
  assertEquals([lost, leaked], [0, 0]);
});

Deno.test('item 3 (second review): an edit with no emirate (the form sends null or empty) is no change, never a refusal', () => {
  const owner = { resolved: true, buyer: BUYER, spec: { location: 'Dubai' } };
  for (const em of [null, '', undefined]) {
    const d = editDecision({ summary: 'Kitchen refit', budget: null, emirate: em }, { summary: 'Kitchen' }, owner);
    assert(d.ok && !('emirate' in d.patch) && d.patch.summary === 'Kitchen refit', JSON.stringify(d));
  }
});

Deno.test('item 2 (second review): a kept answer names the part kept for the customer, and the supplier reads a fixed line only', async () => {
  const { keptNotice, SITE_KEPT_FOR_SUPPLIERS } = await import('./what_a_supplier_receives.ts');
  const n = keptNotice(['al barsha 2', 'villa 15']);
  assert(/al barsha 2/.test(n.en) && /villa 15/.test(n.en) && /al barsha 2/.test(n.ar), n.en);
  assert(/answered/.test(SITE_KEPT_FOR_SUPPLIERS) && /opens your quotation|opens a quotation/.test(SITE_KEPT_FOR_SUPPLIERS));
  assertEquals(found(SITE_KEPT_FOR_SUPPLIERS, NEVER), []);
});

// MERGE ORDER (second review, item 5): a place the customer never stated in a site key is the shared text backstop's place
// reducer's to remove. This branch must not be released without it: the assertion runs whenever the reducer is present, and
// the test says so plainly when it is not.
Deno.test('a place never stated in a site key is removed by the shared place reducer (runs once it is merged)', async (t) => {
  const { scrubIdentityText } = await import('../_shared/identity_text.ts');
  const present = scrubIdentityText('Kitchen fit-out in Al Barsha 2, Dubai', '█') !== 'Kitchen fit-out in Al Barsha 2, Dubai';
  if (!present) { console.log('SKIPPED: the shared place reducer (_shared/identity_text.ts) is not on this tree; release this branch only together with it'); t.step({ name: 'skipped: no place reducer on this tree', ignore: true, fn: () => {} }); return; }
  const owner: OwnerRead = { resolved: true, buyer: BUYER, spec: { location: 'Dubai' }, emirate: 'Dubai', briefSource: null };
  const a = String(forSuppliers('Access is via the back gate in Dubai, Al Barsha 2, near Mall of the Emirates', owner));
  const b = String(forSuppliers('Al Barsha 2, Villa 15', owner) ?? '');
  assertEquals(found(a + ' ' + b, ['Barsha', 'Mall of the Emirates', 'Villa 15']), [], a + ' | ' + b);
});

Deno.test('second review (e): the customer\'s own rates are never served to a supplier, revealed or not', () => {
  const row = { summary: 'Tiling', brief_source: 'boq', emirate: 'Dubai', spec: { location: 'Dubai', customer_rates: [{ line: 1, priced: ['rate AED 85'] }] },
    boq: { boq: [{ description: 'Tiles 600x600', qty: 86, unit: 'm2' }], customer_rates: [{ line: 1, priced: ['rate AED 85'] }] }, budget: null };
  for (const revealed of [false, true]) assertEquals(/customer_rates|AED 85/.test(JSON.stringify(supplierCopy(row, { revealed, ownerResolved: true, buyer: BUYER }))), false, 'revealed ' + revealed);
});

Deno.test('a seed that is only a place is left to the shared reducer when it says so; painted when the reducer is absent', async (t) => {
  const { seedsToPaint, placeReducerPresent } = await import('./what_a_supplier_receives.ts');
  // both cases, independent of the tree: the reducer's answer decides, and with none every seed is painted
  assertEquals(seedsToPaint(['al barsha 2', 'unit 1204', 'zz demo barsha garden villa'], (s) => s === 'al barsha 2'), ['unit 1204', 'zz demo barsha garden villa']);
  assertEquals(seedsToPaint(['al barsha 2', 'unit 1204'], null), ['al barsha 2', 'unit 1204']);
  assertEquals(seedsToPaint(['al barsha 2'], () => { throw new Error('x'); }), ['al barsha 2']);
  if (!placeReducerPresent) { console.log('SKIPPED (live half): _shared/identity_text.ts exports no reducibleSeed on this tree'); return; }
  const stored = { location: 'Dubai', site_location: 'Al Barsha 2' };
  const out = String(supplierField<string>('Renovation of two bathrooms at Al Barsha 2', BUYER, requestSeeds(BUYER, stored), [], 'Dubai').value);
  assert(/Dubai/.test(out) && !/Barsha|█/.test(out), out);
  void t;
});
