// interview — the deterministic intake must reach 'ready' with no model.
// deno test supabase/functions/inquiry_intake/interview.test.ts
//
// The fixture is production's category_specs row for `aluminium` as read on 14 Sep 2026 (4 of its
// 7 fields required), with the plain-language siblings the data file adds. The defect this guards:
// the keyword fallback never read an answer, so this exact category could never become 'ready'.
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { interviewStep, parseAnswer, parseMeasures, parseEmirate, parseWhen, parseBudget, buildBrief, type SpecField, type InterviewState } from './interview.ts';

const ALUMINIUM: SpecField[] = [
  { key: 'element', required: true, type: 'multiselect', options: ['Windows (sliding/casement)', 'Doors', 'Kitchen / wardrobe shutters', 'Cladding / composite panel (ACP)', 'Handrails / railing', 'Pergola / shade', 'Partitions'], question: 'What aluminium work?', question_plain_en: 'What do you need in aluminium — windows, doors, railings, cladding or something else?', question_plain_ar: 'ما الأعمال المطلوبة بالألمنيوم — نوافذ أم أبواب أم درابزين أم تكسية أم غير ذلك؟' },
  { key: 'dimensions_qty', required: true, type: 'text', options: [], question: 'Sizes (W x H mm) per unit and quantity (or total m²)?', question_plain_en: 'How many pieces, and roughly how wide and tall is each one?', question_plain_ar: 'كم قطعة تحتاج، وما العرض والارتفاع التقريبي لكل قطعة؟' },
  { key: 'system_finish', required: false, type: 'select', options: ['Powder-coated (RAL)', 'Anodized', 'Thermal-break system', 'Supplier to recommend'], question: 'System & finish preference?' },
  { key: 'glazing', required: false, type: 'select', options: ['Single glazed', 'Double glazed', 'Tinted / reflective', 'Frosted', 'No glass'], question: 'Glass infill (if any)?' },
  { key: 'scope', required: true, type: 'select', options: ['Supply and install', 'Supply only'], question: 'Scope?', question_plain_en: 'Should the supplier also install it, or only deliver it?', question_plain_ar: 'هل تريد من المورد التوريد والتركيب، أم التوريد فقط؟' },
  { key: 'location', required: true, type: 'text', options: [], question: 'Property type, emirate/area, floor, access?', question_plain_en: 'What kind of property is it, and which emirate and area?', question_plain_ar: 'ما نوع العقار، وفي أي إمارة ومنطقة؟' },
  { key: 'timeline', required: false, type: 'select', options: ['Within 2 weeks', '2-4 weeks', '1-2 months', 'Flexible'], question: 'Timeline?' },
];

function run(turns: string[], lang: 'en' | 'ar' = 'en') {
  let state: InterviewState = { details: {}, asked_key: null };
  const said: string[] = [];
  let step = null as ReturnType<typeof interviewStep> | null;
  for (const t of turns) {
    said.push(t);
    step = interviewStep(ALUMINIUM, state, t, said.join(' \n '), lang);
    state = { details: step.details, asked_key: step.next ? step.next.key : null };
  }
  return step!;
}

Deno.test('first message fills what it plainly states and asks ONE plain question next', () => {
  const s = run(['I need aluminium sliding windows for my villa in Dubai']);
  assertEquals(s.details.element, 'Windows (sliding/casement)');
  assertEquals(s.details.location, 'Dubai', 'a stated emirate fills the location key without being asked');
  assertEquals(s.readiness, { filled: 2, required: 4 });
  assert(s.next && s.next.key === 'dimensions_qty', 'next asked is the first unanswered required field');
  assertEquals(s.next!.text, 'How many pieces, and roughly how wide and tall is each one?');
  assert(!s.complete);
});

Deno.test('answers are parsed into the canonical keys and the interview reaches ready', () => {
  const s = run([
    'I need aluminium sliding windows for my villa',
    '6 windows, 1200 x 1500 each',
    'supply and install please',
    'Villa in Dubai Marina',
  ]);
  assert(s.complete, 'all four required keys filled');
  assertEquals(s.next, null);
  assertEquals(s.readiness, { filled: 4, required: 4 });
  assertEquals(s.details.scope, 'Supply and install');
  assertEquals(s.details.dimensions_qty, '6 windows, 1200 x 1500 each');
  assertEquals(s.details.location, 'Villa in Dubai Marina');
  const brief = buildBrief('aluminium', s.details, 'x', parseEmirate(s.details.location), 'I need aluminium sliding windows for my villa');
  assertEquals(brief.emirate, 'Dubai');
  assertEquals(brief.scope, 'Supply and install');
  assertEquals(brief.category, 'aluminium');
  for (const k of ['summary', 'category', 'scope', 'quantity', 'location', 'emirate', 'timeline', 'budget', 'details']) assert(k in brief, 'brief carries ' + k);
});

Deno.test('Arabic: questions come back in Arabic and Arabic answers fill the keys', () => {
  const s1 = run(['نحتاج نوافذ ألمنيوم لفيلا'], 'ar');
  assertEquals(s1.next!.text, 'كم قطعة تحتاج، وما العرض والارتفاع التقريبي لكل قطعة؟');
  assertEquals(s1.details.element, 'Windows (sliding/casement)', 'Arabic "نوافذ" names the English option');
  const s = run(['نحتاج نوافذ ألمنيوم لفيلا', '٦ نوافذ مقاس ١٢٠٠ × ١٥٠٠', 'توريد وتركيب', 'فيلا في الشارقة'], 'ar');
  assert(s.complete);
  assertEquals(s.details.scope, 'Supply and install');
  assertEquals(parseEmirate(s.details.location), 'Sharjah');
});

Deno.test('a vague answer is kept in the customer\'s words, never re-asked forever', () => {
  const s = run(['aluminium doors', 'not sure, normal size']);
  assertEquals(s.details.dimensions_qty, 'Not sure');
  assertEquals(s.next!.key, 'scope');
});

Deno.test('an answer to one question never answers another: no stray yes, no stray not-sure', () => {
  // Both found replaying the founder's generators request (14 Sep 2026): "Not sure - advise" about
  // the power rating read as Yes (the yes pattern contains "sure") AND matched the Not sure option of
  // the automatic-switch question, so that question was answered without ever being asked.
  const f: SpecField[] = [
    { key: 'rating', required: true, type: 'select', options: ['Up to 100 kVA', 'Not sure - advise'], question: 'kVA?' },
    { key: 'ats', required: true, type: 'select', options: ['Yes', 'No', 'Not sure'], question: 'Automatic switch?' },
  ];
  const s = interviewStep(f, { details: {}, asked_key: 'rating' }, 'not sure, advise', 'generator \n not sure, advise', 'en');
  assertEquals(s.details.rating, 'Not sure - advise');
  assertEquals(s.details.ats, undefined, 'ats is asked, not inferred');
  assertEquals(s.next!.key, 'ats');
  assertEquals(parseAnswer(f[1], 'yes please', false), null, 'a bare yes is only an answer to the question just asked');
  assertEquals(parseAnswer(f[1], 'not sure', true), 'Not sure');
});

Deno.test('parsers: units, emirates EN/AR, dates, yes/no options, budget', () => {
  assertEquals(parseMeasures('about 120 square metres')[0].text, '120 sqm');
  assertEquals(parseMeasures('٤٥ متر مربع')[0].text, '45 sqm');
  assertEquals(parseMeasures('30 lm of skirting')[0].unit, 'lm');
  assertEquals(parseMeasures('12 pcs')[0].unit, 'pcs');
  assertEquals(parseEmirate('أبوظبي'), 'Abu Dhabi');
  assertEquals(parseEmirate('near RAK'), 'Ras Al Khaimah');
  assertEquals(parseWhen('asap')!.text, 'ASAP');
  assertEquals(parseWhen('within 3 weeks')!.days, 21);
  assertEquals(parseWhen('خلال أسبوعين')!.days, 14);
  assertEquals(parseBudget('around AED 50k'), 'AED 50000');
  const illum: SpecField = { key: 'illuminated', type: 'select', options: ['Yes', 'No'], question: 'Illuminated?' };
  assertEquals(parseAnswer(illum, 'نعم', true), 'Yes');
  assertEquals(parseAnswer(illum, 'no thanks', true), 'No');
  assertEquals(parseAnswer(ALUMINIUM[6], 'in 10 days', true), 'Within 2 weeks');
  const emi: SpecField = { key: 'location', type: 'select', options: ['Dubai', 'Abu Dhabi', 'Sharjah', 'Northern Emirates', 'Not sure'], question: 'Which emirate?' };
  assertEquals(parseAnswer(emi, 'Ajman', true), 'Northern Emirates');
});

// Customer audit 21 Sep 2026, finding 8: the intake ignored what the customer wrote. Production's
// category_specs `scope` and `property_area` rows for `electrical`, read 21 Sep 2026.
const ELEC_SCOPE: SpecField = { key: 'scope', type: 'multiselect', required: true, options: ['New wiring (first fix)', 'Rewiring', 'DB board supply & install', 'Lighting', 'Power sockets', 'Data & TV points', 'AC power points', 'DEWA new connection', 'DEWA load upgrade', 'Testing & certification only'], question: 'What electrical work?' };
const ELEC_AREA: SpecField = { key: 'property_area', type: 'text', required: true, options: [], question: 'Property type, built-up area (m²) and number of rooms/zones?' };
const AUDIT_MSG = 'Electrical works for a ZZ DEMO 4-bedroom villa in Khalifa City A, Abu Dhabi. Supply and install 500 m of 4 mm2 copper cable (BS EN 50525, LSZH) and 3 x 12-way DB boards with MCBs (IEC 61439, Schneider or ABB), plus 60 double sockets and 24 switches (MK Logic or Legrand). Installation and 2-year warranty required. Site is ready for first fix; work must finish by 30 November 2026.';

Deno.test('finding 8b: a multiselect scope keeps every work the customer named, not just one', () => {
  // Measured before the fix: "DB board supply & install" alone; the cable (first fix) and sockets were dropped.
  assertEquals(parseAnswer(ELEC_SCOPE, AUDIT_MSG, false), 'New wiring (first fix), DB board supply & install, Power sockets');
  assertEquals(parseAnswer(ELEC_SCOPE, 'I need the lighting and the DB board changed', true), 'DB board supply & install, Lighting');
  assertEquals(parseAnswer(ELEC_SCOPE, 'a new AC connection', false), null, 'generic words (new, connection) pick nothing');
});

Deno.test('finding 8c: a paragraph answers a "how big" question with its measure sentence; quantity is a measure or empty', () => {
  const reply = 'It is a 4-bedroom villa, about 450 m2 built-up, 9 rooms. Three-phase supply. As I said: MK Logic or Legrand for switches and sockets, Schneider or ABB DBs, supplier to install, 2-year warranty minimum, finished by 30 November 2026.';
  assertEquals(parseAnswer(ELEC_AREA, reply, true), 'It is a 4-bedroom villa, about 450 m2 built-up, 9 rooms.');
  const brief = buildBrief('electrical', { property_area: 'It is a 4-bedroom villa, about 450 m2 built-up, 9 rooms.', scope: 'Power sockets' }, AUDIT_MSG, 'Abu Dhabi', AUDIT_MSG);
  assertEquals(brief.quantity, '450 sqm', 'the number, not the prose');
  assertEquals(buildBrief('electrical', { property_area: 'a villa, not sure how big' }, 'x', null, 'x').quantity, '', 'no measure stated: empty, never prose');
  assertEquals(buildBrief('aluminium', { dimensions_qty: '40 windows, 1200 x 1500 mm' }, 'x', null, 'x').quantity, '40 windows, 1200 x 1500 mm', 'a count with its size is kept whole');
});

Deno.test('finding 8d: the summary is the customer\'s full description, not its first 160 characters', () => {
  const brief = buildBrief('electrical', {}, AUDIT_MSG, 'Abu Dhabi', AUDIT_MSG);
  assertEquals(brief.summary, AUDIT_MSG);
  assert(brief.summary.includes('24 switches (MK Logic or Legrand)'), 'measured before the fix: cut at "3 x 12-way D"');
});
