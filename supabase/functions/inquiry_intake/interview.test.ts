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
