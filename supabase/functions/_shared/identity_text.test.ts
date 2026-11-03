// identity_text.test.ts — every leak the planted-identity run measured on 3 Nov 2026 (scripts/e2e/
// identity_never_leaks_before_reveal.mjs, seed 20261103), replayed through the scrubbers that let it through, AND the
// independent review of #1838's MUST-KEEP probes: the ordinary BOQ, quotation and Q&A wording the first version of
// the shared list destroyed (some of it at save, so permanently). Both halves must hold.
// deno test --no-lock supabase/functions/_shared/identity_text.test.ts
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { identityShapesIn, knownNameRe, scrubIdentityText } from './identity_text.ts';
import { scrubIdentity as supplierScrub } from '../supplier_api/identity_scrub.ts';
import { scrubIdentity as boqScrub } from '../drawing_boq/boq_from_text.ts';
import { maskContacts, quoteDocument } from './quote_documents.ts';
import { stripContact } from '../messages_api/strip_contact.ts';
import { residualScan } from './anonymise.ts';
import * as F from './quote_documents.fixture.ts';

const NAME = 'ZZ Crescent Green AM9 Engineering Consultants LLC';
// The printed forms that reached the other side, each with the substring that must be gone.
const LEAKED: [string, string][] = [
  ['Cheque in favour of ZZ Crescent Green AM9 Engineering Consultants LLC.', 'Crescent Green AM9'],
  ['Transfer to IBAN AE09 0580 0009 6788 6290 627.', '6788'],
  ['IBAN: AE280040006055553370809', '0060555'],
  ['P. O. Box 59508', '59508'], ['PO BOX: 14446', '14446'], ['POB 21759', '21759'], ['ص.ب ٥٦١٤٣', '٥٦١٤٣'],
  ['Trade licence TL 273158', '273158'], ['T.L. No. 273158', '273158'], ['CN-9744610', '9744610'], ['D.E.D. Licence 780159', '780159'],
  // The header's own measured leak was the SIX-digit "CN-974461" (second review of #1838, 3 Nov 2026): restored.
  ['CN-974461', '974461'], ['Licence CN 1234567', '1234567'], ['CN1234567', '1234567'],
  ['Hotline (050) 000 0076', '0076'], ['Mob 971500000064', '0064'], ['+٩٧١ ٥٠ ٠٠٠ ٠٠٦١', '٠٠٦١'], ['٠٤ ٠٠٠ ٠٠٥٥', '٠٠٥٥'], ['(04) 000 0044', '0044'],
  ['Mob: 05 0000 0012', '0012'], ['04-0000012', '0000012'], ['0500000098', '0098'], ['+971 4 000 0017', '0017'],
  ['Showroom: Office 735, ZZ Palm IU8 Tower, Al Quoz Industrial Area 3, Dubai.', 'IU8 Tower'],
  ['Al Katheeb Al Akhdar Trading standard conditions apply.', 'Katheeb'],
  ['شركة النخلة الملكي للديكور ذ.م.م', 'النخلة'], ['شركة الواحة الأخضر للخدمات الفنية ذ.م.م', 'الواحة'],
  ['Prepared by: ZZ Omar Qasimi, Sales Engineer', 'Qasimi'], ['Thanks, ZZ Rashid Ketbi - quotes', 'Ketbi'], ['Site visits arranged by ZZ Majid Nuaimi.', 'Nuaimi'],
  ['المسؤول: زد زد عمر المزروعي.', 'المزروعي'],
  // ── second independent review of #1838 (3 Nov 2026): leaks the loosened list REOPENED, each measured passing ──
  // 1. a sign-off with no comma
  ['Best Regards\nAhmed Khan\nSales Manager', 'Khan'], ['Best Regards Ahmed Khan', 'Khan'], ['Kind regards Ahmed Khan, Sales Manager', 'Khan'],
  ['Thanks & Regards\nAHMED KHAN', 'KHAN'], ['Regards,\nAhmed Khan\nSales Manager', 'Khan'],
  // 2. name shapes: hyphenated, all-caps, lowercase particles
  ['Prepared by: Ahmed Al-Mansoori', 'Mansoori'], ['Prepared by: AHMED KHAN', 'KHAN'], ['Contact: Eng. Ahmed al Mansoori', 'Mansoori'],
  ['Mr. Ahmed bin Rashid', 'Rashid'], ['Prepared by: Ahmed Khan Sales Engineer', 'Khan'],
  // 4. Arabic legal names: a legal form is identity on its own; a proper noun after شركة / مؤسسة
  ['شركة النور ٢٠٠٠ للمقاولات ذ.م.م', 'النور'], ['النور للمقاولات ذ.م.م', 'النور'], ['شركة النور الذهبية', 'النور'], ['مؤسسة النور', 'النور'],
  ['وشركة النور للمقاولات', 'النور'],
  // 5. the country code in brackets
  ['Tel (+971) 50 123 4567', '4567'], ['Tel (+971) 4 123 4567', '4567'],
  // 6. all-caps Latin firms; 7. other mobile layouts
  ['AL NOOR TRADING', 'NOOR'], ['AL NOOR CONTRACTING CO.', 'NOOR'],
  ['050 12 34 567', '567'], ['050/1234567', '1234567'], ['0 5 0 1 2 3 4 5 6 7', '4 5 6 7'],
  // PRE-EXISTING GAPS closed here
  ['Lic. No. 1234567', '1234567'], ['Lic No: 654321', '654321'], ['رخصة تجارية رقم ١٢٣٤٥٦', '١٢٣٤٥٦'], ['السجل التجاري 765432', '765432'],
  ['Visit alnoor.store', 'alnoor'], ['Visit alnoor.shop today', 'alnoor'], ['Follow instagram.com/alnoortrading', 'alnoortrading'],
  ['Mail ahmed @ gmail . com', 'ahmed'], ['Mail ahmed[at]gmail[dot]com', 'ahmed'], ['Mail ahmed(at)gmail(dot)com', 'ahmed'],
  ['IBAN AE07-0331-2345-6789-0123-456', '6789'],
  ['Building 5, Al Quoz, Dubai', 'Al Quoz'], ['Villa 23, Street 14, Jumeirah 1, Dubai', 'Jumeirah'], ['مكتب ١٢، برج الخليج، دبي', 'برج الخليج'], ['Post Box 12345', '12345'],
  ['المهندس أحمد المنصوري', 'المنصوري'], ['م. أحمد المنصوري', 'المنصوري'], ['مع التحية، أحمد المنصوري', 'المنصوري'],
  ['Al Noor & Sons Trading LLC', 'Noor'], ['Saif bin Darwish Contracting', 'Saif'],
];
/** What a residual scan must flag on the RAW text (a drawing page holding these is held, never shared). */
const residualOf = (s: string) => residualScan(s, ['zz demo']);
Deno.test('every leaked shape is gone through each scrubber that let it through, and a residual scan flags the raw text', () => {
  const bad: string[] = [];
  for (const [text, gone] of LEAKED) {
    const outs = { supplier_api: supplierScrub(text, NAME, []) ?? '', drawing_boq: boqScrub(text), quote_documents: maskContacts(text, [NAME]), messages_api: stripContact(text, [NAME]) };
    for (const [who, out] of Object.entries(outs)) if (out.includes(gone)) bad.push(`${who} kept "${gone}" of ${JSON.stringify(text)}: ${JSON.stringify(out)}`);
    if (!residualOf(text).length) bad.push(`residualScan found nothing in ${JSON.stringify(text)}`);
  }
  assertEquals(bad, []);
});
Deno.test('a known name is matched whole, with its suffix, and next to Arabic; fragments only with a digit, only when asked', () => {
  const re = knownNameRe(NAME)!;
  for (const s of ['ZZ Crescent Green AM9 Engineering Consultants LLC', 'zz crescent green am9 engineering consultants', 'شركة ZZ Crescent Green AM9 Engineering Consultants للتجارة']) { re.lastIndex = 0; assert(re.test(s), s); }
  re.lastIndex = 0; assert(!re.test('the Crescent Green AM9 series'), 'no fragment unless asked');
  const fr = knownNameRe(NAME, { fragments: true })!; assert(fr.test('the Crescent Green AM9 series'), 'a fragment carrying a digit');
  const ar = knownNameRe('شركة النور للتجارة')!; assert(ar.test('من شركة النور للتجارة'));
  // "Consultants" no longer loses its "Co": the old pattern matched none of these.
  assertEquals(supplierScrub(`payable to ${NAME} only`, NAME, []), 'payable to [removed] only');
});
Deno.test('a residual Arabic-Indic or bracketed phone, an IBAN, a P.O. Box or a licence holds a drawing page', () => {
  for (const s of ['٠٤ ٠٠٠ ٠٠١٤', '(04) 000 0019', 'T.L. No. 614867', 'IBAN AE09 0580 0009 6788 6290 627', 'ص.ب ٥٦١٤٣']) assert(residualScan(s, ['zz demo']).length > 0, s);
});

// ── MUST-KEEP (independent review of #1838, scratchpad probes probe.ts / probe_main.ts / probe_cmp.ts / probe_reveal.ts)
const KEEP = ['Supply and install 2 TR ducted split unit 6 nos 4200.00 25200.00', 'GI ductwork with insulation 85 sqm 180.00', 'Copper piping 1/2" + 7/8" insulated 60 lm',
  '14 days from PO.', '50% advance, 50% on completion.', 'Thanks for the opportunity to quote.', 'Cooling Tower CT-1 1 nos', 'Main Building ground floor', 'Validity: 30 days',
  'Qty 0.50 Rate 1250.00', 'AED 9,971,500.00', 'FCU-1 to FCU-6, 2 TR each', 'بلاط بورسلين 600x600 الكمية 120 متر مربع', 'Room 0450 x 1200', 'Unit 6, 2 TR', 'Contact the Majlis ceiling height 3.2 m',
  'Toughened glass to BS EN 12150-1, 10 mm clear', 'ASTM C1036 float glass 6 mm', 'Fire rated to DIN 4102 B1', 'Cables to BS 6724 LSZH 4C x 16 sqmm',
  'Inverter model TL-12000 1 nos', 'Product code CN-123456 ceiling tile', 'Ref TL 273158 luminaire', 'Dimmer DED 45000 series',
  'Bosch part no 0 986 452 041', 'UPVC pipe dia 050 075 110 160 mm', 'Valves DN 025 032 040 050 065 080',
  '01 25 450.00 11250.00', '03 120 4500 54000', 'Item 02 6 nos 1250.00 7500.00', 'Rev 02 dated 05.11.2026 10:30',
  'Dated 01.12.2026 1200 hrs', 'Price AED 971,500.00', 'Total 0 971 500 000', '050 mm thick insulation',
  'Project Manager Full Time On Site', 'Attention: Please note prices exclude VAT', 'Approved by MEP Consultants prior to install', 'Section 4 General Contracting works',
  'Project Duration Est. 6 Weeks', 'Delivery from Jebel Ali Industrial Area 2 warehouse', 'All works on behalf of Main Contractor Dubai Hills',
  'Unit 12, Block B, Dubai', 'Mr. Client to provide power', 'From: Ground Floor To Roof',
  'مكتب خشبي مقاس ١٢٠×٦٠ سم عدد ١٠', 'تشطيب مكتب الإدارة بالكامل', 'خرسانة جاهزة من مصنع معتمد C40', 'يتم الاستلام من قبل المهندس المشرف على المشروع',
  'المسؤول عن التركيب المقاول الرئيسي', 'تجديد مكتب في دبي مارينا مساحة ٢٠٠ متر مربع', 'شركة التأمين تتحمل التكاليف',
  'Contact: Site Office for access', 'Regards, Supply Chain Team',
  // ── second independent review of #1838 (3 Nov 2026): trade text the loosened list still ate ──
  'Acoustic Consultants approval required', 'Third Party Consultants to witness testing', 'Fire Alarm Engineering Consultants approval',
  'Kitchen Interiors package 1 lot', 'Section 5: Hotel Lobby Interiors', 'Permit issued by Dubai Municipality', 'NOC issued by Abu Dhabi Municipality',
  'Signed by Both Parties before mobilisation', 'Submitted by Tenderer Before Closing Date', 'Contact: Dubai Electricity Authority for connection',
  'BMS software licence 12500.00', 'Annual licence 15000 per year', 'عن طريق شركة معتمدة للصيانة', 'بواسطة شركة متخصصة للعزل المائي',
  // and the guards the fixes above must not break
  'Thanks for the opportunity', 'Our trading terms apply', 'General trading terms apply', 'With regards to the delivery schedule',
  'Best Regards, Supply Chain Team', 'Kind regards, QS Team', 'Prepared by: MEP CONSULTANTS', 'Attention: ALL WORKS TO BE TESTED',
  'Dated 05.06.2026 1200 hrs', 'الشركة المصنعة تقدم الضمان', 'الشركة الموردة مسؤولة عن التركيب', 'المهندس المقيم في الموقع', 'مع الشكر للتعاون',
  'طول الأنبوب ١٠ م. حسب المخطط', 'Model CN 1234567 driver', 'Item code CN-1234567 panel'];
// stripContact writes Arabic-Indic digits as Latin ones before it reads numbers; that is the same figure, not damage.
const latin = (s: string) => s.replace(/[٠-٩]/g, (c) => String(c.charCodeAt(0) - 0x660)).replace(/\s+/g, ' ').trim();
const kept = (s: string, out: string) => latin(out) === latin(s);
Deno.test('MUST-KEEP: ordinary BOQ, quotation and Arabic wording is untouched by the shared list, by every scrubber and by the residual scan', () => {
  const bad: string[] = [];
  for (const s of KEEP) {
    const outs = { shared: scrubIdentityText(s, '[X]'), supplier_api: supplierScrub(s, null, []) ?? '', drawing_boq: boqScrub(s), quote_documents: maskContacts(s, [], 'en'), messages_api: stripContact(s, []) };
    for (const [who, out] of Object.entries(outs)) if (!kept(s, out)) bad.push(`${who}: "${s}" -> "${out}"`);
    // The residual's shared-list half never holds a page for trade wording (its older GENERIC_ID half is unchanged here).
    const shapes = identityShapesIn(s);
    if (shapes.length) bad.push(`residual shared-list half: "${s}" -> ${shapes.join(',')}`);
  }
  assertEquals(bad, []);
});
Deno.test("MUST-KEEP: a trade-named firm's own trade wording survives its own name scrub (saved permanently)", () => {
  const NAMES: [string, string][] = [
    ['Dubai Building Materials Trading LLC', 'All building materials supplied by contractor; building materials list attached'],
    ['Al Ain Ready Mix Concrete LLC', 'Ready mix concrete C40 pump placed 120 cum'],
    ['Al Safa Fire Safety Equipment LLC', 'Fire safety equipment as per civil defence; fire safety signage'],
    ['Modern Aluminium & Glass Works LLC', 'Aluminium, glass partitions 40 sqm; aluminium glass doors'],
    ['Gulf Steel Works LLC', 'Steel works to structural drawings; gulf steel sections'],
    ['Star Interior Decoration LLC', 'Interior decoration package; star rating'],
    ['Green Building Solutions LLC', 'Green building certification support'],
    ['Cool Air Conditioning Contracting LLC', 'Air conditioning works 2 TR ducted split; air conditioning maintenance'],
    ['Premium Joinery Works', 'premium joinery finish to all doors'],
  ];
  for (const [n, s] of NAMES) assertEquals(supplierScrub(s, n, []), s, n);
  // Across suppliers in the comparison: another supplier's name never strips this one's scope.
  const names = ['Cool Air Conditioning Contracting LLC', 'Al Waha Fire Safety Systems LLC', 'Blue Ocean Building Materials Trading'];
  for (const s of ['Supplier B: supply and install air conditioning units, 6 nos ducted split', 'Fire safety systems to civil defence approval', 'Building materials by others']) assertEquals(maskContacts(s, names, 'en'), s);
});
Deno.test('MUST-KEEP: a project name is removed only whole from a Q&A answer, its ordinary words stay', () => {
  assertEquals(stripContact('The kitchen cabinets are 3.2 m long; villa has two floors; renovation starts in January.', ['Ahmed Khan'], ['Villa Kitchen Renovation']),
    'The kitchen cabinets are 3.2 m long; villa has two floors; renovation starts in January.');
  assertEquals(stripContact('Yes the office fit out includes the pantry; fit out works at night only.', ['Sara Ali'], ['Marina Office Fit Out']), 'Yes the office fit out includes the pantry; fit out works at night only.');
  assert(!stripContact('Site is ZZ Dune Heights Villa 2, see you there', ['ZZ DEMO Omar Ketbi'], ['ZZ Dune Heights Villa 2']).includes('Dune Heights'));
});
Deno.test('MUST-KEEP: a REVEALED quotation names its supplier on the party chip (EN and AR)', () => {
  const q0 = F.QUOTES[0] as unknown as { items: never[] };
  for (const name of ['Al Waha Al Thahabi Trading LLC', 'Gulf Cool Air Conditioning Contracting LLC', 'Bright Star Technical Services LLC', 'شركة النخلة الملكية للديكور ذ.م.م']) {
    for (const lang of ['en', 'ar'] as const) {
      const { body } = F.reasoned((arTexts) => ({ ...quoteDocument({ quote: q0 as never, inquiry: F.INQUIRY as never, items: q0.items ?? [], letter: 'A', lang, partyName: name, maskNames: [], arTexts }) }));
      // deno-lint-ignore no-explicit-any
      const party = ((body as any).blocks as any[]).find((b) => b.t === 'party');
      assertEquals(party?.chip, name, `${lang} ${name}`);
    }
  }
});
