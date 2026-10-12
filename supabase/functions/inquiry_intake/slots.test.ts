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
import { settleModelTurn, replyFromState, openTurnsByKey, MAX_OPEN_TURNS, UNANSWERED } from './slots.ts';
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

// ── FROM THE RUN'S TRANSCRIPTS (Desktop/QuotesDone Sandbox Test 2026-10/intake/, 11 files) ─────────
// The customer lines below are copied verbatim from C1_aluminium.json, C7_glass.json and
// C10_elevators.json. The model replies are fixtures in the contract the prompt now asks for.
import { requirementsFromModel, stampTurn } from './slots.ts';
import { requirementsStep } from '../_shared/intake_requirements.ts';
const NOW = new Date('2026-10-07T00:00:00Z');

Deno.test('(1) "within six weeks" is captured as the needed-by date and never asked again (EN, C1 turn 3)', () => {
  // C1 turn 3: "Supply and install, within six weeks, ground and first floor."
  const req = requirementsFromModel('aluminium', { installation: 'yes', required_by: { days: 42, text: 'within six weeks' } }, NOW);
  assertEquals(req.required_by, { v: 'date', date: '2026-11-18', text: 'within six weeks' });
  assertEquals(req.installation, { v: 'yes' });
  const st = requirementsStep('aluminium', req, null, '', {}, 'en', NOW);
  assert(!st.remaining.includes('By when do you need it done or delivered? Tap one, or type a date.'));
});

Deno.test('(1) "خلال ستة أسابيع" is captured the same way (AR, C10 turn 3)', () => {
  // C10 turn 3: "التوريد والتركيب، خلال ستة أسابيع."
  const req = requirementsFromModel('elevators', { installation: 'yes', required_by: { days: 42, text: 'خلال ستة أسابيع' } }, NOW);
  assertEquals(req.required_by?.date, '2026-11-18');
  const st = requirementsStep('elevators', req, null, '', {}, 'ar', NOW);
  assert(!st.remaining.includes('متى تحتاج إلى إنجاز العمل أو استلامه؟ اختر أحد الخيارات، أو اكتب التاريخ.'));
});

Deno.test('(2) "not sure / standard" for a material is ACCEPTED as a standard-spec answer, not re-asked (EN C1 + AR C10)', () => {
  // C1 turn 4: "Brand: Technal; grade: not sure, standard commercial."; turn 6: "...profile system?: standard specification, please assume typical values"
  const en = requirementsFromModel('aluminium', { 'material.profile': 'not_sure', 'material.glass': 'not_sure' }, NOW);
  assertEquals(en['material.glass'], { v: 'no_preference', note: 'Not sure: supplier to propose the standard specification' });
  const stEn = requirementsStep('aluminium', en, null, '', {}, 'en', NOW);
  assert(!stEn.remaining.some((q) => q.startsWith('Any preference for the')), 'no material question is left once "not sure" is recorded');
  // C10 turn 4: "المواصفات: غير متأكد من العلامة التجارية، درجة تجارية قياسية."
  const ar = requirementsFromModel('elevators', { 'material.cabin_finish': 'not_sure' }, NOW);
  const stAr = requirementsStep('elevators', ar, null, '', {}, 'ar', NOW);
  assert(!stAr.remaining.includes('هل لديك تفضيل في تشطيب الكابينة؟ اختر أحد الخيارات، أو اكتب ما تفضّله.'));
  // a value outside the closed list is not recorded
  assertEquals(requirementsFromModel('aluminium', { 'material.profile': 'titanium', required_by: 'soon' }, NOW), {});
});

const GLASS: SpecField[] = [
  { key: 'element', required: true, question: 'Glass application?' },
  { key: 'dimensions_qty', required: true, question: 'Sizes and quantity?' },
  { key: 'glazing_performance', required: true, question: 'Glass type / performance?' },
  { key: 'scope', required: true, question: 'Scope?' },
  { key: 'location', required: true, question: 'Location?', question_plain_en: 'What kind of property is it, and which emirate and area?' },
  { key: 'timeline', required: false, question: 'Timeline?' },
];
Deno.test('(3) C7\'s location "villa in Umm Al Quwain, ground and first floor" is captured and kept', () => {
  // C7 turn 1: "Glass & Glazing for a villa in Umm Al Quwain. Line 1: double glazed units x 20. Line 2: tempered glass x 10. Line 3: laminated glass x 5."
  const t1: any = { category: 'glass', status: 'needs_info', questions: ['What is the glass for?'], brief: { location: 'Villa in Umm Al Quwain', details: { dimensions_qty: 'Line 1 x 20; Line 2 x 10; Line 3 x 5', glazing_performance: 'Double glazed units; tempered; laminated' } } };
  const s1 = settleModelTurn(GLASS, {}, t1, 'en', briefOf);
  // C7 turn 3: "Supply and install, within six weeks, ground and first floor."
  const t3: any = { category: 'glass', status: 'needs_info', questions: ['What is the glass for?'], brief: { details: { scope: 'Supply and install', location: 'Villa in Umm Al Quwain, ground and first floor', timeline: 'within six weeks' } } };
  const s3 = settleModelTurn(GLASS, s1.details, t3, 'en', briefOf);
  assertEquals(s3.details.location, 'Villa in Umm Al Quwain, ground and first floor');
  assertEquals(s3.details.timeline, 'within six weeks');
  assertEquals(s3.missingKeys, ['element'], 'only the glass application, which C7 never stated, is left');
});

Deno.test('(4) every assistant turn carries the slots recorded with it', () => {
  const turns: any[] = [{ role: 'user', text: 'x' }, { role: 'assistant', text: 'a1' }, { role: 'user', text: 'y' }, { role: 'assistant', text: 'a2' }];
  stampTurn(turns, { status: 'needs_info', details: { location: 'Dubai' }, req_answers: { installation: { v: 'yes' } }, missing: ['scope'] });
  assertEquals(turns[3].slots.details, { location: 'Dubai' });
  assertEquals(turns[3].slots.status, 'needs_info');
  assert(typeof turns[3].slots.at === 'string');
  assertEquals(turns[1].slots, undefined, 'an earlier turn keeps the snapshot of its own time');
});

// ── REVIEW OF #1277: every reply agrees with the row, from structured fields ──────────────────────
const C1_T5_EN = 'The request is ready to share with suppliers.'; // C1 turn 5 verbatim, beside needs_info
const C10_AR_READY = 'الطلب جاهز للإرسال إلى الموردين.';
Deno.test('a follow-up that still claims ready (claims_ready=true) is replaced while not ready — EN', () => {
  const out: any = { category: 'aluminium', status: 'needs_info', claims_ready: true, assistant_message: C1_T5_EN + ' Which floor is it on?', questions: ['Which floor?'], brief: { details: { element: 'Windows' } } };
  settleModelTurn(ALUMINIUM, {}, out, 'en', briefOf);
  assertEquals(out.status, 'needs_info');
  assertEquals(out.assistant_message, 'Thanks, noted. How many pieces, and roughly how wide and tall is each one?');
});
Deno.test('a follow-up that still claims ready (claims_ready=true) is replaced while not ready — AR', () => {
  const out: any = { category: 'aluminium', status: 'needs_info', claims_ready: true, assistant_message: C10_AR_READY, questions: ['؟'], brief: { details: { element: 'نوافذ', dimensions_qty: '20', location: 'دبي' } } };
  settleModelTurn(ALUMINIUM, {}, out, 'ar', briefOf);
  assertEquals(out.assistant_message, 'شكرًا، دوّنت ذلك. هل تريد من المورد التوريد والتركيب، أم التوريد فقط؟');
});
Deno.test('an honest needs_info question (claims_ready=false, asks something) is the model\'s own words', () => {
  const msg = 'Thanks — should the supplier also install the windows?';
  const out: any = { category: 'aluminium', status: 'needs_info', claims_ready: false, assistant_message: msg, questions: ['Install too?'], brief: { details: { element: 'Windows', dimensions_qty: '20', location: 'Dubai' } } };
  settleModelTurn(ALUMINIUM, {}, out, 'en', briefOf);
  assertEquals(out.assistant_message, msg);
});
Deno.test('ready always tells the customer to press Send to suppliers — EN and AR', () => {
  const full = { element: 'Windows', dimensions_qty: '20', scope: 'Supply and install', location: 'Dubai' };
  const en: any = { category: 'aluminium', status: 'ready', claims_ready: true, assistant_message: 'All set!', brief: { details: full } };
  settleModelTurn(ALUMINIUM, {}, en, 'en', briefOf);
  assertEquals(en.status, 'ready');
  assert(en.assistant_message.includes('press Send to suppliers'));
  const ar: any = { category: 'aluminium', status: 'ready', claims_ready: true, assistant_message: 'تم', brief: { details: full } };
  settleModelTurn(ALUMINIUM, {}, ar, 'ar', briefOf);
  assert(ar.assistant_message.includes('«أرسل إلى الموردين»'));
});

// ── run f4294be8 (12 Oct 2026): C9 was asked "Is there a leak now…" on 13 turns and never reached ready ──
// production category_specs.fields for `waterproofing`, required keys as read on 12 Oct 2026
const WATERPROOFING: SpecField[] = [
  { key: 'area', required: true, question: 'Which area needs waterproofing?' },
  { key: 'issue', required: true, question: 'Existing leak, or new / preventive?', question_plain_en: 'Is there a leak now, or is this to prevent one?', question_plain_ar: 'هل يوجد تسرب حالياً، أم هي وقاية من التسرب؟' },
  { key: 'area_sqm', required: true, question: 'Approximate area (sqm)?' },
  { key: 'supply_install', required: true, question: 'Supply + application, or application only?' },
  { key: 'location', required: true, question: 'Location / area and emirate?' },
];
// Every turn the customer replies; the model extracts the other four keys and never `issue`.
const C9_TURN = () => ({ category: 'waterproofing', status: 'needs_info', claims_ready: false, assistant_message: 'Is there an active leak, or is this a preventive replacement?', questions: ['Is there an active leak, or is this a preventive replacement?'],
  brief: { details: { area: 'Bedrooms; balconies; facade', area_sqm: '90.9', supply_install: 'Supply + application', location: 'Villa in Abu Dhabi' } as Record<string, string> } });

Deno.test('C9: a key left open through MAX_OPEN_TURNS answered turns is settled, and the request goes ready', () => {
  const turns: any[] = [];
  let prev: Record<string, string> = {};
  let out: any = null;
  let asked = 0;
  for (let i = 0; i < 14; i++) {
    out = C9_TURN();
    const s = settleModelTurn(WATERPROOFING, prev, out, 'en', briefOf, openTurnsByKey(turns));
    prev = s.details;
    turns.push({ role: 'user', text: 'reply' }, { role: 'assistant', text: out.assistant_message, slots: { missing_keys: s.missingKeys } });
    if (out.status === 'ready') break;
    asked++;
  }
  assertEquals(asked, MAX_OPEN_TURNS, 'the same question is asked MAX_OPEN_TURNS times, not 13');
  assertEquals(out.status, 'ready');
  assertEquals(out.brief.details.issue, UNANSWERED.en, 'recorded as a supplier decision, not an invented fact');
  assertEquals(out.provenance.issue, 'unanswered');
});

Deno.test('a key the customer answers is never settled as unanswered, whatever the count', () => {
  const out: any = C9_TURN(); out.brief.details.issue = 'No leak, preventive';
  const s = settleModelTurn(WATERPROOFING, {}, out, 'en', briefOf, { issue: MAX_OPEN_TURNS + 5 });
  assertEquals(s.details.issue, 'No leak, preventive');
  assertEquals(s.settledUnanswered, []);
});
