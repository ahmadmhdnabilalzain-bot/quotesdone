// interview — the intake's state machine: a tapped option, the REASONED reading of what the customer
// stated, and the held path. No word matching decides an answer (decision point interview.answers).
// deno test supabase/functions/inquiry_intake/interview.test.ts
//
// The fixture is production's category_specs row for `aluminium` as read on 14 Sep 2026 (4 of its
// 7 fields required), with the plain-language siblings the data file adds.
import { assert, assertEquals } from 'jsr:@std/assert@1';
import { interviewStep, parseMeasures, parseBudget, buildBrief, type SpecField, type InterviewState } from './interview.ts';

const ALUMINIUM: SpecField[] = [
  { key: 'element', required: true, type: 'multiselect', options: ['Windows (sliding/casement)', 'Doors', 'Kitchen / wardrobe shutters', 'Cladding / composite panel (ACP)', 'Handrails / railing', 'Pergola / shade', 'Partitions'], question: 'What aluminium work?', question_plain_en: 'What do you need in aluminium — windows, doors, railings, cladding or something else?', question_plain_ar: 'ما الأعمال المطلوبة بالألمنيوم — نوافذ أم أبواب أم درابزين أم تكسية أم غير ذلك؟' },
  { key: 'dimensions_qty', required: true, type: 'text', options: [], question: 'Sizes (W x H mm) per unit and quantity (or total m²)?', question_plain_en: 'How many pieces, and roughly how wide and tall is each one?', question_plain_ar: 'كم قطعة تحتاج، وما العرض والارتفاع التقريبي لكل قطعة؟' },
  { key: 'system_finish', required: false, type: 'select', options: ['Powder-coated (RAL)', 'Anodized', 'Thermal-break system', 'Supplier to recommend'], question: 'System & finish preference?' },
  { key: 'scope', required: true, type: 'select', options: ['Supply and install', 'Supply only'], question: 'Scope?', question_plain_en: 'Should the supplier also install it, or only deliver it?', question_plain_ar: 'هل تريد من المورد التوريد والتركيب، أم التوريد فقط؟' },
  { key: 'location', required: true, type: 'text', options: [], question: 'Property type, emirate/area, floor, access?', question_plain_en: 'What kind of property is it, and which emirate and area?', question_plain_ar: 'ما نوع العقار، وفي أي إمارة ومنطقة؟' },
];
const START: InterviewState = { details: {}, asked_key: null };
const said = (value: string) => ({ value, evidence: value });

Deno.test('the reasoned reading fills what the customer stated, in their own words, and asks ONE question next', () => {
  const s = interviewStep(ALUMINIUM, START, { stated: { dimensions_qty: said('40 windows, 1200 x 1500 mm'), location: said('villa in Dubai Marina') }, answer: 'x' }, 'en');
  assertEquals(s.details, { dimensions_qty: '40 windows, 1200 x 1500 mm', location: 'villa in Dubai Marina' });
  assertEquals(s.next?.key, 'element');
  assertEquals(s.next?.options?.length, 7);
  assertEquals(s.readiness, { filled: 2, required: 4 });
  assert(!s.held);
});

Deno.test('a TAPPED option answers the question it was offered with — and only that question, only with its own options', () => {
  const asked: InterviewState = { details: {}, asked_key: 'scope' };
  assertEquals(interviewStep(ALUMINIUM, asked, { choice: { key: 'scope', option: 'Supply only' }, stated: {} }, 'en').details.scope, 'Supply only');
  // an option of another question, or an option that is not one of this question's, is not an answer
  assertEquals(interviewStep(ALUMINIUM, asked, { choice: { key: 'element', option: 'Doors' }, stated: {} }, 'en').details, {});
  assertEquals(interviewStep(ALUMINIUM, asked, { choice: { key: 'scope', option: 'Supply and fix' }, stated: {} }, 'en').details, {});
});

Deno.test('the interview reaches ready from taps and reasoned statements alone', () => {
  let st = START;
  let s = interviewStep(ALUMINIUM, st, { stated: { location: said('Dubai Marina villa') } }, 'en');
  st = { details: s.details, asked_key: s.next!.key };
  s = interviewStep(ALUMINIUM, st, { choice: { key: 'element', option: 'Doors' }, stated: {} }, 'en');
  st = { details: s.details, asked_key: s.next!.key };
  s = interviewStep(ALUMINIUM, st, { stated: { dimensions_qty: said('3 doors, 900 x 2100') } }, 'en');
  st = { details: s.details, asked_key: s.next!.key };
  s = interviewStep(ALUMINIUM, st, { choice: { key: 'scope', option: 'Supply and install' }, stated: {} }, 'en');
  assert(s.complete);
  assertEquals(s.readiness, { filled: 4, required: 4 });
});

Deno.test('held: an open question keeps the typed reply verbatim; an option question is NOT guessed into an option', () => {
  const openQ = interviewStep(ALUMINIUM, { details: {}, asked_key: 'location' }, { stated: null, answer: 'Villa, Jumeirah, ground floor' }, 'en');
  assertEquals(openQ.details.location, 'Villa, Jumeirah, ground floor');
  assert(openQ.held);
  // "yes, install please" names the option only to a word matcher; under the hold it stays open, to tap.
  const optQ = interviewStep(ALUMINIUM, { details: {}, asked_key: 'scope' }, { stated: null, answer: 'yes, install please' }, 'en');
  assertEquals(optQ.details.scope, undefined);
  assertEquals(optQ.next?.key, 'element', 'required order: element first; scope stays open');
  assert(optQ.held);
  // held reads nothing else from the conversation either
  assertEquals(Object.keys(interviewStep(ALUMINIUM, START, { stated: null, answer: 'Windows in Dubai, 40 pcs, supply and install' }, 'en').details), []);
});

Deno.test('Arabic: the questions come back in Arabic; a reasoned Arabic statement is kept in Arabic', () => {
  const s = interviewStep(ALUMINIUM, START, { stated: { location: said('فيلا في دبي') } }, 'ar');
  assertEquals(s.details.location, 'فيلا في دبي');
  assertEquals(s.next?.text, ALUMINIUM[0].question_plain_ar);
});

Deno.test('format parsers that remain: units and money (a duration or a place is never read here)', () => {
  assertEquals(parseMeasures('about 120 square metres')[0].text, '120 sqm');
  assertEquals(parseMeasures('٤٥ متر مربع')[0].text, '45 sqm');
  assertEquals(parseMeasures('30 lm of skirting')[0].unit, 'lm');
  assertEquals(parseBudget('around AED 50k'), 'AED 50000');
  // 22 Sep 2026, replayed from production: a duct size is not a budget, and "Budget is open" names none.
  assertEquals(parseBudget('Quantities: 26x18 supply duct, EF-1. Needed by 30 November 2026. Budget is open.'), null);
  assertEquals(parseBudget('Budget: not sure, maybe use 26x18 duct'), null);
  assertEquals(parseBudget('٢٥٠ ألف درهم'), 'AED 250000');
  assertEquals(parseBudget('budget is 1.2M'), 'AED 1200000');
});

const AUDIT_MSG = 'Electrical works for a ZZ DEMO 4-bedroom villa in Khalifa City A, Abu Dhabi. Supply and install 500 m of 4 mm2 copper cable (BS EN 50525, LSZH) and 3 x 12-way DB boards with MCBs (IEC 61439, Schneider or ABB), plus 60 double sockets and 24 switches (MK Logic or Legrand). Installation and 2-year warranty required. Site is ready for first fix; work must finish by 30 November 2026.';
Deno.test('finding 8c/8d: quantity is a measure or empty; the summary is the full description; the emirate is the reasoned one', () => {
  const brief = buildBrief('electrical', { property_area: 'It is a 4-bedroom villa, about 450 m2 built-up, 9 rooms.', scope: 'Power sockets' }, AUDIT_MSG, 'Abu Dhabi', AUDIT_MSG);
  assertEquals(brief.quantity, '450 sqm', 'the number, not the prose');
  assertEquals(brief.summary, AUDIT_MSG);
  assertEquals(brief.emirate, 'Abu Dhabi');
  assertEquals(buildBrief('electrical', { property_area: 'a villa, not sure how big' }, 'x', null, 'x').quantity, '');
  // No reasoned emirate: none is read off the location's words.
  assertEquals(buildBrief('aluminium', { location: 'villa in Dubai Marina' }, 'x', null, 'x').emirate, '');
});
