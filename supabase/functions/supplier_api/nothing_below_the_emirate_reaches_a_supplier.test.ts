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
import { belowEmirate, emirateIn, siteParts, siteSeeds, splitSite, supplierSpec } from '../_shared/site_location.ts';
import { newInquiryBody, requestSeeds, supplierBrief, supplierField, type Buyer } from './what_a_supplier_receives.ts';
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
  assertEquals(body, 'A customer is requesting quotes for: bathroom_renovation (Dubai). Log in to your QuotesDone supplier portal to quote.');
});
