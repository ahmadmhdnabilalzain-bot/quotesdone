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
import { settleModelTurn, replyFromState, openTurnsByKey, MAX_OPEN_TURNS, HELD_FOR_SPECS, slotAskOf, slotKeyFor, heldReasonFor, heldReply, heldQuestions, heldAsk, readHeldAnswer, intakeVoice, replyDown } from './slots.ts';
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

Deno.test('C9: a key unanswered through MAX_OPEN_TURNS turns stops being asked and the request is HELD, never ready', () => {
  const turns: any[] = [];
  let prev: Record<string, string> = {};
  let out: any = null;
  let asked = 0;
  for (let i = 0; i < 14; i++) {
    out = C9_TURN();
    const s = settleModelTurn(WATERPROOFING, prev, out, 'en', briefOf, openTurnsByKey(turns));
    prev = s.details;
    turns.push({ role: 'user', text: 'reply' }, { role: 'assistant', text: out.assistant_message, slots: { missing_keys: s.missingKeys } });
    if (out.status !== 'needs_info') { assertEquals(s.exhausted, ['issue']); assertEquals(s.missingKeys, ['issue'], 'the spec stays missing'); break; }
    asked++;
  }
  assertEquals(asked, MAX_OPEN_TURNS, 'the same question is asked MAX_OPEN_TURNS times, not 13');
  assertEquals(out.status, 'held', 'exact specs or the request is held: never released without the spec');
  assertEquals(out.brief, null);
  assertEquals(prev.issue, undefined, 'nothing is written under the unanswered key');
  assertEquals(out.assistant_message, HELD_FOR_SPECS.en);
});

Deno.test('an exhausted key is not asked again while other keys are still asked', () => {
  const out: any = C9_TURN(); delete out.brief.details.location;
  const s = settleModelTurn(WATERPROOFING, {}, out, 'en', briefOf, { issue: MAX_OPEN_TURNS, location: 1 });
  assertEquals(out.status, 'needs_info');
  assertEquals(s.missingKeys, ['issue', 'location']);
  assertEquals(out.questions, ['Location / area and emirate?'], 'the leak question is not repeated');
  assert(!out.assistant_message.includes('leak'));
});

Deno.test('a key the customer answers is kept whatever the count', () => {
  const out: any = C9_TURN(); out.brief.details.issue = 'No leak, preventive';
  const s = settleModelTurn(WATERPROOFING, {}, out, 'en', briefOf, { issue: MAX_OPEN_TURNS + 5 });
  assertEquals(s.details.issue, 'No leak, preventive');
  assertEquals(s.exhausted, []);
  assertEquals(out.status, 'ready');
});

// Stage-2 run 321d13ae (18 Oct 2026): a spec hold returned no reason and next_question.key was null
// before every ready. The reason is for our harness only; the key goes with the state's own question only.
Deno.test('held_reason is given to an @example.invalid subject only, never to a real customer', () => {
  assertEquals(heldReasonFor('held', 'qd-321d13ae-cust17@example.invalid', ['system_type']), { held_reason: 'specs_unanswered: system_type' });
  assertEquals(heldReasonFor('held', 'QD-X@EXAMPLE.INVALID', []), { held_reason: 'specs_unanswered: unknown' });
  for (const email of ['customer@gmail.com', 'a@example.invalid.ae', 'example.invalid@gmail.com', '']) {
    assertEquals(heldReasonFor('held', email, ['system_type']), {}, email);
  }
  assertEquals(heldReasonFor('needs_info', 'x@example.invalid', ['system_type']), {});
});

Deno.test('next_question.key is set only on an exact match with the slot state\'s first open question', () => {
  const sl = { details: {}, missingKeys: ['system_type', 'scope'], missing: ['What type of system?', 'Supply or install?'], complete: false, exhausted: [], held: false };
  const ask = slotAskOf(sl);
  assertEquals(ask, { key: 'system_type', text: 'What type of system?' });
  assertEquals(slotKeyFor(ask, 'What type of system?'), 'system_type');
  for (const q of ['What type of system? ', 'what type of system?', 'Which AC system do you want?', 'Supply or install?']) assertEquals(slotKeyFor(ask, q), null, q);
  assertEquals(slotKeyFor(null, 'What type of system?'), null);
  // An exhausted key is never the asked key: the next askable one is.
  assertEquals(slotAskOf({ ...sl, exhausted: ['system_type'], missing: ['Supply or install?'] }), { key: 'scope', text: 'Supply or install?' });
  assertEquals(slotAskOf({ ...sl, exhausted: ['system_type', 'scope'], missing: [] }), null);
});

// THE HELD REPLY NAMES THE OPEN QUESTION (19 Oct 2026): HELD_FOR_SPECS said only "a few specifications are still open".
// The model (ruling 1196) is now given each exhausted question in the inquiry language and writes the reply; the deps
// below record what the model was GIVEN, which is the property under test. Fails on the old code: no heldReply existed.
Deno.test('a held intake: the model is given the still-open question in Arabic and its reply is what the customer sees', async () => {
  const seen: { system: string; input: string }[] = [];
  const deps = {
    gate: () => Promise.resolve(null), embed: () => Promise.resolve(null),
    rpc: () => Promise.resolve({ data: { block: 'REVEAL FEE: 3.00%.' }, error: null }),
    llm: (_p: string, system: string, input: string) => { seen.push({ system, input }); return Promise.resolve({ content: JSON.stringify({ answer: 'شكرًا لكم. ما زال سؤال واحد مفتوحًا: كم قطعة تحتاج، وما العرض والارتفاع التقريبي لكل قطعة؟ سيساعدكم مهندس المبيعات هنا.' }), model: 'm' }); },
  } as any;
  const reply = (await heldReply(deps, ALUMINIUM, ['dimensions_qty'], 'ar', 'لا أعرف', [{ role: 'user', text: 'نوافذ ألمنيوم' }])).text;
  const q = heldQuestions(ALUMINIUM, ['dimensions_qty'], 'ar')[0];
  assertEquals(q, ALUMINIUM[1].question_plain_ar);
  assert(seen[0].input.includes(q), 'the open question rides in the facts, in the inquiry language');
  assert(seen[0].system.includes('Arabic'), 'the reply is asked for in Arabic');
  assert(reply.includes('كم قطعة'), 'the customer sees the model reply naming the open question');
  assertNotEquals(reply, HELD_FOR_SPECS.ar);
});
Deno.test('a held field with no question text never sends its raw key to the model', () => {
  const fields: SpecField[] = [{ key: 'area', required: true } as SpecField, ALUMINIUM[2]];
  assertEquals(heldQuestions(fields, ['area', 'system_finish'], 'en'), ['System & finish preference?']);
  assertEquals(heldQuestions(fields, ['area'], 'ar'), []);
});
// founder_instruction 1339 (27 Oct 2026): "the engineer and customer support never replies without llm unless the server of
// open router is down". The code list (handover + open questions) is the OUTAGE fallback only; a model that answered and
// was refused, or a 4xx, gives '' and index.ts has the model say it again.
Deno.test('1339: a held intake lists the open questions in code only when OpenRouter is down', async () => {
  const deps = (llm: () => Promise<unknown>) => ({ gate: () => Promise.resolve(null), embed: () => Promise.resolve(null), rpc: () => Promise.resolve({ data: null, error: null }), llm }) as any;
  for (const error of ['gateway_http_502', 'client_timeout_30000ms']) {
    const r = await heldReply(deps(() => Promise.resolve({ content: null, error })), ALUMINIUM, ['scope'], 'en', 'x', []);
    assertEquals(r.by, 'outage_fallback', error);
    assert(r.text.startsWith(HELD_FOR_SPECS.en), r.text);
    assert(r.text.includes(ALUMINIUM[4].question_plain_en!), 'the outage fallback names the open question too');
  }
  const refused = await heldReply(deps(() => Promise.resolve({ content: JSON.stringify({ answer: 'circuit_open from openrouter' }), model: 'm' })), ALUMINIUM, ['scope'], 'en', 'x', []);
  assertEquals([refused.text, refused.by], ['', 'none'], 'model up: no code-written reply');
  const fourxx = await heldReply(deps(() => Promise.resolve({ content: null, error: 'gateway_http_400:bad request' })), ALUMINIUM, ['scope'], 'en', 'x', []);
  assertEquals(fourxx.by, 'none', 'a 4xx is not an outage');
});
Deno.test('1339: intakeVoice — the model writes the code-decided reply; the draft only when OpenRouter is down', async () => {
  const seen: string[] = [];
  const mk = (llm: (s: string, i: string) => Promise<unknown>) => ({ gate: () => Promise.resolve(null), embed: () => Promise.resolve(null),
    rpc: () => Promise.resolve({ data: null, error: null }), llm: (_p: string, s: string, i: string) => llm(s, i) }) as any;
  const draft = 'Thanks, noted. A few quick questions about materials, installation, warranty and timing. Do you need installation?';
  const up = await intakeVoice(mk((_s, i) => { seen.push(i); return Promise.resolve({ content: JSON.stringify({ answer: 'Got it. Would you like the supplier to install them as well?' }), model: 'm' }); }),
    { draft, lang: 'en', message: 'aluminium windows, villa in Dubai', conversation: [], next: { text: 'Do you need installation?', options: ['Yes', 'Supply only'] } });
  assertEquals(up, { text: 'Got it. Would you like the supplier to install them as well?', outage: false, by: 'model' });
  assert(seen[0].includes(draft) && seen[0].includes('Do you need installation?') && seen[0].includes('Yes | Supply only'), 'the draft, the one question and its options ride as facts');
  const down = await intakeVoice(mk(() => Promise.resolve({ content: null, error: 'gateway_http_503:circuit_open' })), { draft, lang: 'en', message: 'x', conversation: [] });
  assertEquals(down, { text: draft, outage: true, by: 'outage_fallback' });
  const refused = await intakeVoice(mk(() => Promise.resolve({ content: JSON.stringify({ answer: 'ai_gateway SQLSTATE error' }), model: 'm' })), { draft, lang: 'en', message: 'x', conversation: [] });
  // the refusals ride out with by 'none', so the turn filed for the re-ask names them to the model (_shared/reask.ts)
  assertEquals(refused, { text: '', outage: false, by: 'none', problems: ['it breaks the reply rule "internal"'] }, 'model up, nothing safe: no code-written reply');
});
Deno.test('1339: replyDown reads an aiReply result without an outage flag from its attempts', () => {
  assertEquals(replyDown({ reply: '', attempts: ['route:failed gateway_http_502', 'other-family:failed client_timeout_30000ms'] }), true);
  assertEquals(replyDown({ reply: '', attempts: ['deadline: no time left for another call', 'route:failed no answer'] }), true);
  assertEquals(replyDown({ reply: '', attempts: ['route:ok', 'rewrite:failed [it breaks the reply rule "internal"]'] }), false);
  assertEquals(replyDown({ reply: '', attempts: ['route:failed gateway_http_400'] }), false);
  assertEquals(replyDown({ reply: '', attempts: [] }), false);
  assertEquals(replyDown({ reply: '', outage: true, attempts: [] }), true, 'aiReply\'s own flag wins where it exists');
});

// ── HELD WITH 0 QUESTIONS (27 Oct 2026, founder ledger 580, run 6dd2316c) ─────────────────────────────────────
// Production agent_runs, inquiry_intake, 27 Oct 07:52-07:54 UTC: a ZZ DEMO customer's HVAC drawing intake asked 4, 4
// and 3 questions, then answered status=held with questions=0 on seven turns in a row; create_inquiry answered 428.
// The fixtures below are the hvac checklist as production holds it (category_specs, read 27 Oct 2026) and a model
// that files only `scope` from the customer's messages, which is what the run's readiness 50-80 shows. Fails on the
// old code: the held branch set questions=[] and missing=[], and heldAsk / readHeldAnswer did not exist.
const HVAC: SpecField[] = [
  { key: 'system_type', type: 'select', required: true, question: 'What type of AC system?', options: ['Wall/floor split', 'Ducted (concealed) split', 'Cassette', 'VRF/VRV', 'Chiller (air/water-cooled)', 'Package unit', 'FAHU/AHU (fresh air)', 'Not sure - need site survey'], question_plain_en: 'What kind of air conditioning — wall split units, hidden ducted, ceiling cassettes, a central system, or should the supplier survey and advise?' },
  { key: 'application_area', type: 'text', required: true, question: 'What is the space used for, and roughly what area?', question_plain_en: 'What is the space used for, and roughly how big is it?' },
  { key: 'new_or_replace', type: 'select', required: true, question: 'Is this new, replacement, or a service/repair?', options: ['New installation', 'Replacement of existing', 'Extension of existing', 'Service / repair / maintenance'], question_plain_en: 'Is this a new installation, replacing old units, adding more, or a repair?' },
  { key: 'scope', type: 'select', required: true, question: 'Scope?', options: ['Supply only', 'Supply and install', 'Turnkey (incl. ducting, MEP drawings, testing & commissioning)'], question_plain_en: 'Should the supplier only deliver, install, or do everything including ducts and testing?' },
  { key: 'location', type: 'text', required: true, question: 'Which emirate/area, floor level, and condenser location?', question_plain_en: 'Which emirate and area, which floor, and where can the outdoor unit go — roof, wall or ground?' },
];
const HVAC_TURN = () => ({ category: 'hvac', status: 'needs_info', claims_ready: false, readiness: 60, assistant_message: 'What kind of system is it?', questions: ['What kind of system is it?', 'How big is the space?', 'New or replacement?', 'Where is it?'],
  brief: { details: { scope: 'Supply and install' } as Record<string, string> } });

/** One turn exactly as index.ts runs it on the model path: read the held answer, settle, ask what the hold waits on. */
function hvacTurn(prevBrief: any, text: string, turns: any[], modelOut: any = HVAC_TURN()) {
  const prev = prevBrief?.details || {};
  const heldKey = prevBrief?.asked_on_hold === true ? String(prevBrief.asked_key || '') : '';
  const heldVal = heldKey && !(heldKey in prev) ? readHeldAnswer(HVAC, heldKey, text) : null;
  const s = settleModelTurn(HVAC, heldVal ? { ...prev, [heldKey]: heldVal } : prev, modelOut, 'en', briefOf, openTurnsByKey(turns));
  const ask = s.held ? heldAsk(HVAC, s.exhausted, 'en') : null;
  turns.push({ role: 'user', text }, { role: 'assistant', text: modelOut.assistant_message, slots: { missing_keys: s.missingKeys } });
  return { s, out: modelOut, ask, brief: { details: s.details, ...(ask ? { asked_key: ask.key, asked_on_hold: true } : {}) } };
}

Deno.test('ledger 580: a held intake always asks the specific open specs (never questions=0)', () => {
  const turns: any[] = []; let brief: any = {}; let t: any = null;
  for (let i = 0; i < MAX_OPEN_TURNS + 1; i++) { t = hvacTurn(brief, 'As per the attached drawings.', turns); brief = t.brief; }
  assertEquals(t.out.status, 'held', 'the hold itself stays: exact specs or nothing goes to a supplier');
  assertEquals(t.s.exhausted, ['system_type', 'application_area', 'new_or_replace', 'location']);
  assertEquals(t.out.questions.length, 4, 'every open spec is asked');
  assertEquals(t.out.questions, heldQuestions(HVAC, t.s.exhausted, 'en'));
  assertEquals(t.out.missing, t.out.questions, 'missing names the same specs, so remaining_questions is not empty');
  assertEquals(t.ask?.key, 'system_type', 'next_question names the first open spec');
  assert(t.s.missingKeys.includes(t.ask!.key), 'and it is a key the hold is waiting on');
  assertEquals(t.ask?.options?.length, 8, 'with the checklist options to tap');
});

Deno.test('ledger 580: the held specs, answered one by one, take the intake to ready', () => {
  const turns: any[] = []; let brief: any = {}; let t: any = null;
  for (let i = 0; i < MAX_OPEN_TURNS + 1; i++) { t = hvacTurn(brief, 'As per the attached drawings.', turns); brief = t.brief; }
  const said: Record<string, string> = { system_type: 'Package unit', application_area: 'Offices and storage, about 1,200 square metres', new_or_replace: 'New installation', location: 'Dubai, Al Quoz, ground floor; outdoor units on the roof' };
  const asked: string[] = [];
  for (let i = 0; i < 6 && t.out.status !== 'ready'; i++) {
    assert(t.ask, `turn ${i}: a held turn always has a question`);
    asked.push(t.ask.key);
    // The model still files nothing new: the code reads the answer to the question asked.
    t = hvacTurn(brief, said[t.ask.key], turns); brief = t.brief;
  }
  assertEquals(asked, ['system_type', 'application_area', 'new_or_replace', 'location']);
  assertEquals(t.out.status, 'ready');
  assertEquals(t.s.details.system_type, 'Package unit');
  assertEquals(t.s.details.new_or_replace, 'New installation');
  assertEquals(t.s.details.location, said.location);
});

Deno.test('a held answer is read by code: an option, the customer\'s words, never a bare not-sure', () => {
  assertEquals(readHeldAnswer(HVAC, 'system_type', 'Package unit'), 'Package unit');
  assertEquals(readHeldAnswer(HVAC, 'new_or_replace', 'a replacement of the existing units'), 'Replacement of existing');
  assertEquals(readHeldAnswer(HVAC, 'new_or_replace', 'replacing the old ones'), 'replacing the old ones', 'no option named: their own words answer the question asked');
  assertEquals(readHeldAnswer(HVAC, 'system_type', 'not sure'), 'Not sure - need site survey', 'a not-sure option the trade lists is a spec');
  assertEquals(readHeldAnswer(HVAC, 'application_area', 'not sure'), null, 'a bare not sure fills nothing: the spec stays held');
  assertEquals(readHeldAnswer(HVAC, 'location', 'Sharjah, first floor, roof'), 'Sharjah, first floor, roof');
  assertEquals(readHeldAnswer(HVAC, 'location', ''), null);
  assertEquals(readHeldAnswer(HVAC, null, 'Package unit'), null);
  assertEquals(readHeldAnswer(HVAC, 'no_such_key', 'Package unit'), null);
});

// Independent review of #1641 (27 Oct 2026): the run that made the hold answered "As per the attached drawings." three
// times; the fourth must not become system_type. Fails on the first version of readHeldAnswer, which stored it.
Deno.test('a held answer that only defers, or says nothing, fills nothing (the spec stays held)', () => {
  for (const [key, said] of [
    ['system_type', 'As per the attached drawings.'], ['system_type', 'see drawing'], ['application_area', 'as per drawings'],
    ['location', 'refer to the attached plan'], ['application_area', 'ok'], ['location', 'any'], ['system_type', 'standard'],
    ['application_area', "I don't know"], ['location', 'no idea'], ['application_area', 'not sure yet'], ['application_area', '?'],
    ['location', 'حسب المخطط'], ['application_area', 'لا أعرف'], ['location', 'مرفق'], ['system_type', 'tbd'],
  ] as const) assertEquals(readHeldAnswer(HVAC, key, said), null, `${key} <- "${said}"`);
  // a real answer still counts, including one that mentions the drawing among its facts
  assertEquals(readHeldAnswer(HVAC, 'application_area', 'Offices, about 1,200 m2 as shown on the drawing'), 'Offices, about 1,200 m2 as shown on the drawing');
  assertEquals(readHeldAnswer(HVAC, 'system_type', 'not sure'), 'Not sure - need site survey', 'a listed option is still the trade\'s own spec');
});

Deno.test('heldAsk is in checklist order and skips a field with no question text', () => {
  assertEquals(heldAsk(HVAC, ['location', 'new_or_replace'], 'en')?.key, 'new_or_replace');
  assertEquals(heldAsk(HVAC, ['location'], 'en'), { key: 'location', text: HVAC[4].question_plain_en!, options: null });
  assertEquals(heldAsk([{ key: 'area', required: true } as SpecField], ['area'], 'en'), { key: 'area', text: 'area', options: null });
  assertEquals(heldAsk(HVAC, [], 'en'), null);
});
