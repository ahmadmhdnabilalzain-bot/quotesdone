// slots — the model path keeps what the customer stated and never says "ready" while the row is not.
// deno test supabase/functions/inquiry_intake/slots.test.ts
//
// Replays stage-2 run fe7ba9c4 (7 Oct 2026): C1's FIRST message names the element and the location,
// and the row stayed needs_info with missing=[element, location] and brief.details={} for ten turns
// while the assistant said the request was ready to share. The model replies below are FIXTURES in the
// shape openai/gpt-6-luna returned on that run (status/readiness/missing as ai_qa_log and the stage-2
// report recorded them; the run did not keep raw completions), so no model is called in CI.
// Fails on the old code: there, a needs_info turn persisted `prevBrief.details || {}` and the model's
// own status, missing and sentence, so every assertion on details, missing and the reply breaks.
import { assert, assertEquals, assertNotEquals } from 'jsr:@std/assert@1';
import { settleModelTurn, replyFromState } from './slots.ts';
import type { SpecField } from './interview.ts';

// production category_specs.fields for `aluminium`, required flags and keys as read on 7 Oct 2026
const ALUMINIUM: SpecField[] = [
  { key: 'element', required: true, question: 'What aluminium work?', question_plain_en: 'What do you need in aluminium — windows, doors, railings, cladding or something else?', question_plain_ar: 'ما الأعمال المطلوبة بالألمنيوم — نوافذ أم أبواب أم درابزين أم تكسية أم غير ذلك؟' },
  { key: 'dimensions_qty', required: true, question: 'Sizes and quantity?', question_plain_en: 'How many pieces, and roughly how wide and tall is each one?', question_plain_ar: 'كم قطعة تحتاج، وما العرض والارتفاع التقريبي لكل قطعة؟' },
  { key: 'system_finish', required: false, question: 'System & finish preference?' },
  { key: 'glazing', required: false, question: 'Glass infill (if any)?' },
  { key: 'scope', required: true, question: 'Scope?', question_plain_en: 'Should the supplier also install it, or only deliver it?', question_plain_ar: 'هل تريد من المورد التوريد والتركيب، أم التوريد فقط؟' },
  { key: 'location', required: true, question: 'Property type, emirate/area?', question_plain_en: 'What kind of property is it, and which emirate and area?', question_plain_ar: 'ما نوع العقار، وفي أي إمارة ومنطقة؟' },
  { key: 'timeline', required: false, question: 'Timeline?' },
];
const briefOf = (d: Record<string, string>) => ({ summary: 'from slots', details: d });

// C1, turn 1: "Aluminium Works for a villa in Dubai. Line 1: aluminium windows x 20. Line 2: aluminium doors x 10. Line 3: ..."
const C1_TURN1 = () => ({
  category: 'aluminium', status: 'needs_info', readiness: 55,
  assistant_message: 'Thanks — I have the villa location in Dubai. Should the supplier also install the windows and doors?',
  questions: ['Should the supplier also install them, or only deliver?'],
  missing: ['element', 'location'], // what the run recorded: the model listing stated keys as missing
  brief: { summary: '', location: 'Villa, Dubai', details: { element: 'Windows (sliding/casement), Doors', dimensions_qty: 'Line 1: windows x 20; Line 2: doors x 10; Line 3: x 5' } },
});

Deno.test('C1 turn 1: element and location are captured from the first message and leave missing', () => {
  const out: any = C1_TURN1();
  const s = settleModelTurn(ALUMINIUM, {}, out, 'en', briefOf);
  assertEquals(s.details.element, 'Windows (sliding/casement), Doors');
  assertEquals(s.details.location, 'Villa, Dubai', 'a checklist key at the top of the brief is a slot too');
  assert(!s.missingKeys.includes('element') && !s.missingKeys.includes('location'));
  assertEquals(s.missingKeys, ['scope'], 'only what the customer has not said is missing');
  assertEquals(out.status, 'needs_info');
  assertEquals(out.missing, ['Should the supplier also install it, or only deliver it?']);
});

Deno.test('C1: turn-1 slots survive a later turn the model answers without them, and missing becomes empty', () => {
  const t1: any = C1_TURN1();
  const s1 = settleModelTurn(ALUMINIUM, {}, t1, 'en', briefOf);
  // turn 3 "Supply and install, within six weeks": the model extracts only what this turn added
  const t3: any = { category: 'aluminium', status: 'needs_info', assistant_message: 'Noted.', questions: ['Which brand?'], missing: ['element', 'location'], brief: { details: { scope: 'Supply and install', timeline: 'within six weeks' } } };
  const s3 = settleModelTurn(ALUMINIUM, s1.details, t3, 'en', briefOf);
  assertEquals(s3.missingKeys, []);
  assertEquals(t3.missing, []);
  assertEquals(t3.status, 'ready', 'every required slot filled: the row is ready whatever the model voted');
  assertEquals(t3.brief.details.element, 'Windows (sliding/casement), Doors');
  assertEquals(t3.brief.details.location, 'Villa, Dubai');
  assertEquals(t3.assistant_message, replyFromState('ready', null, 'en'), 'the model wrote for needs_info; the reply is the state\'s');
});

Deno.test('"ready" is never said while the row is needs_info (model voted ready, slots incomplete)', () => {
  const out: any = { category: 'aluminium', status: 'ready', assistant_message: 'The request is ready to share with suppliers.', questions: [], brief: { details: { element: 'Windows' } } };
  settleModelTurn(ALUMINIUM, {}, out, 'en', briefOf);
  assertEquals(out.status, 'needs_info');
  assertNotEquals(out.assistant_message, 'The request is ready to share with suppliers.');
  assertEquals(out.assistant_message, replyFromState('needs_info', 'How many pieces, and roughly how wide and tall is each one?', 'en'));
});

Deno.test('"ready" is never said while needs_info (model said needs_info but asked nothing — the run\'s shape)', () => {
  const out: any = { category: 'aluminium', status: 'needs_info', assistant_message: 'The request is ready to share with suppliers.', questions: [], missing: ['element', 'location'], brief: null };
  const s = settleModelTurn(ALUMINIUM, { element: 'Windows', dimensions_qty: '20', location: 'Dubai' }, out, 'en', briefOf);
  assertEquals(s.missingKeys, ['scope']);
  assertEquals(out.status, 'needs_info');
  assertEquals(out.assistant_message, 'Thanks, noted. Should the supplier also install it, or only deliver it?');
});

Deno.test('Arabic: turn-1 slots captured, missing asked in Arabic, reply never "ready" while needs_info', () => {
  const out: any = { category: 'aluminium', status: 'ready', assistant_message: 'الطلب جاهز للإرسال إلى الموردين.', questions: [],
    brief: { location: 'فيلا في دبي', details: { element: 'نوافذ ألمنيوم', dimensions_qty: 'البند الأول عدد 20، البند الثاني عدد 10' } } };
  const s = settleModelTurn(ALUMINIUM, {}, out, 'ar', briefOf);
  assertEquals(s.details.location, 'فيلا في دبي');
  assertEquals(s.missingKeys, ['scope']);
  assertEquals(out.status, 'needs_info');
  assertEquals(out.missing, ['هل تريد من المورد التوريد والتركيب، أم التوريد فقط؟']);
  assertEquals(out.assistant_message, 'شكرًا، دوّنت ذلك. هل تريد من المورد التوريد والتركيب، أم التوريد فقط؟');
});
