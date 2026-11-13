// identity_keeps_trade_text_corpus.test.ts — THE CODE LAYER IS THE HIGH-PRECISION BACKSTOP (coordinator's principle, 13 Nov
// 2026): a rule that removes a legitimate technical word from a quotation or a BOQ is a defect as serious as a leak.
// MEASURED: the first version of the anonymity fix round changed 114 of these 411 sentences ("Manual [removed]", "Dubai
// blue", "█ Studs", "Liebherr [removed] Crane"), and main's inbox gate already changed 35 of them ("█ bedrooms", "█ lanes").
// Every sentence crosses every gate unchanged: the shared list, the supplier's save, the customer's documents, the Q&A and
// the supplier's inbox (with a customer's seed terms). Names are ZZ DEMO only.
// deno test --no-lock supabase/functions/_shared/identity_keeps_trade_text_corpus.test.ts
import { assertEquals } from 'jsr:@std/assert@1';
import { AR, EN } from './identity_keeps_trade_text.fixtures.ts';
import { scrubIdentityText } from './identity_text.ts';
import { maskContacts } from './quote_documents.ts';
import { inboxField, scrubIdentity } from '../supplier_api/identity_scrub.ts';
import { stripContact } from '../messages_api/strip_contact.ts';

const SUPPLIER = 'ZZ DEMO Orbit Trading LLC', BUYER = 'ZZ DEMO Omar Haddad';
const norm = (s: string) => String(s ?? '').replace(/\s+/g, ' ').trim().replace(/[٠-٩]/g, (c) => String(c.charCodeAt(0) - 0x660));
const gates = (s: string): Record<string, string> => ({
  shared: scrubIdentityText(s, '[X]'), save: scrubIdentity(s, SUPPLIER, []) ?? '', door: maskContacts(s, [SUPPLIER], 'en'), qa: stripContact(s, [BUYER]),
  inbox: (inboxField(s, BUYER, ['zz demo omar haddad', 'omar haddad', 'haddad'], []) as { boq: string | null }).boq ?? '<WITHHELD>',
});
// What each '#arguable' row does, decided (ruling 1683 and the coordinator's two rulings of 13 Nov 2026): a delivery term
// and a list of areas served pass; "ex works <area>" is the supplier's own location and crosses as its emirate; a building
// or a road named alone, with no other place beside it, is left to the second reader.
const ARGUABLE: Record<string, string | null> = {
  'Ex works Jebel Ali Free Zone': 'Ex works, Dubai', 'Installation across Abu Dhabi and Al Ain': null, 'Delivery to Abu Dhabi, Al Ain and the Western Region': null,
  'Ex-stock Jebel Ali warehouse': 'Ex-stock Dubai warehouse', 'Shipped from Khalifa Port': null, 'Mashreq tower fit-out': null, 'Clock Tower fit-out': null, 'Mohammed Bin Rashid Road works': null,
  'Jebel Ali Free Zone company': 'Dubai company',
};
Deno.test('421 legitimate trade sentences cross every gate unchanged (the arguable ones as decided)', () => {
  const bad: string[] = [];
  for (const raw of [...EN, ...AR]) {
    const s = raw.replace(/\s*#arguable$/, '');
    // A bare community name alone with no cue ("ديرة") is the second reader's (identity_places.ts header).
    if (s === 'ديرة') continue;
    if (raw.endsWith('#arguable')) { const want = ARGUABLE[s] ?? s, out = scrubIdentityText(s, '[X]'); if (norm(out) !== norm(want)) bad.push(`arguable: ${JSON.stringify(s)} -> ${JSON.stringify(out)}`); continue; }
    for (const [gate, out] of Object.entries(gates(s))) if (norm(out) !== norm(s)) bad.push(`${gate}: ${JSON.stringify(s)} -> ${JSON.stringify(out)}`);
  }
  assertEquals(bad, []);
});
// A supplier's own quotation scrubbed with its own name: only the name's own words may go (review of 13 Nov 2026: 14 of 24
// names took "Electrical", "Thermostat", "UPS", "ST-37", "DC-12V", "Construction" from their own quotation).
const QUOTE = `Item 1: LED panel light 600x600 40 W, 20 nos. Best quality, fast delivery.
Item 2: Steel works as per drawing. Fast fix anchors M10. Smart home automation panel. Royal blue tiles. Gulf standard.
Item 3: ABC fire extinguisher 6 kg ABC dry powder; ABC-2024 type. Falcon grey RAL 7012 finish. Concealed piping, Concealed Cistern. Electrical Panel, Electrical works.
Item 4: Ceramic tiles; Granite countertop; Thermal insulation 50 mm, Thermostat digital. Precision AC unit. Stainless Steel sink; Standard finish; Construction water; Technical submittal; Hydrostatic test.
Item 5: PP-R pipes PN20; UPS warranty 2 years; GI-pipe 2 inch; ST-37 steel; DC-12V driver. Light Fittings; Brightness 3000 lm; Marshalling Box; Christmas lights; Standish fixings.
Warranty 2 years. Country of origin: Germany. Services: installation, testing and commissioning.`;
const NAMES = ['Electra Electromechanical LLC', 'Ceramic World Trading', 'Concept Interiors LLC', 'Precision Engineering LLC', 'Thermo Tech LLC', 'Stainless Solutions LLC',
  'Standard Fixings LLC', 'Unique Power Systems LLC', 'Pipe Plus Trading', 'Gulf Insulation LLC', 'Dubai Cable Company', 'Granite House Trading', 'Construct Ltd', 'Hydrotech LLC',
  'Brightway Lighting LLC'].map((n) => 'ZZ DEMO ' + n);
Deno.test('a supplier\'s own name takes nothing but itself out of its own quotation (save and door)', () => {
  const bad: string[] = [];
  for (const n of NAMES) for (const [gate, out] of [['save', scrubIdentity(QUOTE, n, []) ?? ''], ['door', maskContacts(QUOTE, [n], 'en')]] as const) if (norm(out) !== norm(QUOTE)) bad.push(`${gate} ${n}: ${out.split(/\s+/).filter((w) => !QUOTE.includes(w)).join(' ')}`);
  assertEquals(bad, []);
});
