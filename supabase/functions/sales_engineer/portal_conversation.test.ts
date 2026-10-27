// What the portal conversation already holds, and the lines nobody asked for (portal_conversation.ts). No network.
// Run: deno test supabase/functions/sales_engineer/portal_conversation.test.ts
// Every case below is a sentence the deployed or branch portal seat actually wrote in the adaptive conversation bank on
// 27 Oct 2026 (runs 98aa692f, 4d74ce2d, ab519dba, 4f59f1b9), so these tests fail on a head that does not filter them.
import { assert, assertEquals } from 'jsr:@std/assert';
import { ALL_QUESTIONS_DROPPED, ENDS_WITHOUT_A_QUESTION, heldBlock, newClauseOf, heldState, MAX_QUESTIONS, reaskOf, replyFilter, sameAsk, sentencesOf, stripReply, type Turn, unaskedOf } from './portal_conversation.ts';
import { SUMMARY_NEEDS_CONFIRM } from './portal_conversation.ts';
import { portalRules } from './portal_turn.ts';
import { answerFromBrief, type BriefCall } from '../_shared/brief_answer.ts';

const u = (content: string): Turn => ({ role: 'user', content });
const a = (content: string): Turn => ({ role: 'assistant', content });

// ac_undersized_en, run 4f59f1b9: the same question in turns 1, 2 and 3
const AC: Turn[] = [
  u('I want a 1 ton split AC for my living room, it is about 28 square metres and gets the afternoon sun.'),
  a('One ton is likely too small for 28 m² with afternoon sun. Is this a villa, apartment or another property? Does the room have an individual air conditioner, or central or district cooling?'),
  u('Apartment in Al Nahda, Dubai, owned.'),
  a('Noted: an owned apartment in Al Nahda, Dubai. Does the apartment use its own split AC or central/district cooling? Is this replacing an existing unit?'),
];

Deno.test('re-ask: a question asked before is dropped, in other words too (ac_undersized_en asked it three times)', () => {
  const h = heldState(AC, 'It is a new installation; there is no unit there now. Inverter please. Within 2 weeks.');
  assertEquals(reaskOf('Does the apartment use its own air-conditioning units, or central or district cooling?', h), 'repeats an earlier question');
  assert(sameAsk('Does the room have an individual air conditioner, or central or district cooling?', 'Does the apartment use its own air-conditioning units, or central or district cooling?'));
  // a new question passes
  assertEquals(reaskOf('Does the balcony have a power point or isolator nearby?', h), null);
});

Deno.test('re-ask: a slot the customer filled is never asked for again (property type, location, ownership, timing, budget)', () => {
  const h = heldState(AC, 'Within 2 weeks please.');
  assertEquals(reaskOf('Is this a villa or an apartment?', h), 'asks the property type again');
  assertEquals(reaskOf('Which emirate and area is the apartment in?', h), 'asks the location again');
  assertEquals(reaskOf('Do you own the apartment or rent it?', h), 'asks the ownership again');
  assertEquals(reaskOf('When do you need it installed?', h), 'asks the timing again');
  const ar = heldState([u('السلام عليكم، أريد تجديد مطبخ الفيلا بالكامل.')], 'المطبخ على شكل L تقريباً 4 في 3 متر.');
  assertEquals(reaskOf('هل هي فيلا أم شقة؟', ar), 'asks the property type again');
  assertEquals(heldState([], 'Moderate budget, not luxury.').slots.map((s) => s.slot), ['budget']);
  assertEquals(reaskOf('What budget tier suits you: economy, mid-range or premium?', heldState([], 'Moderate, not luxury.')), 'asks the budget again');
});

Deno.test('re-ask: a measured object is not asked its size again; another object, or another dimension, still is', () => {
  // wardrobe_change_of_mind_en: "Each wall is about 2 m wide with a 2.6 m ceiling" then the seat asked the depth (new: kept)
  const w = heldState([u('I need two built-in wardrobes for the bedrooms, with sliding doors.')], 'Each wall is about 2 m wide with a 2.6 m ceiling. Half hanging, half shelves.');
  assertEquals(reaskOf('What is the width and height of each wall?', w), 'asks the wall width and height again');
  assertEquals(reaskOf('What depth can each wardrobe be?', w), null);
  assertEquals(reaskOf('Would you like long or short hanging?', w), 'asks the internal layout again');
  assertEquals(reaskOf('Do you want sliding or hinged doors?', w), 'asks the door type again');
  // glass_partition_trap_en: the partition run and height were given; the DOOR width was not
  const g = heldState([u('I want frameless glass partitions for two meeting rooms.')], 'Two rooms, about 12 m of partition in total, 2.7 m high. One hinged glass door per room.');
  assertEquals(reaskOf('What are the approximate width and height of each partition?', g), 'asks the partition width and height again');
  assertEquals(reaskOf('What clear door width do you need for each door?', g), null);
  // once asked, the door width is not asked a second time
  const g2 = heldState([u('Two rooms, about 12 m of partition in total, 2.7 m high.'), a('What clear door width do you need for each door?'), u('Some sound privacy would be good.')], 'I am not sure, what do you recommend?');
  assertEquals(reaskOf('What clear width should each hinged door be?', g2), 'repeats an earlier question');
});

Deno.test('unasked lines: fee, turnaround, supplier process and hand-off lines are dropped unless the message asks about them', () => {
  const h = heldState(AC, 'The outdoor unit can go on the balcony, about 5 m of pipe.');
  assertEquals(unaskedOf('Quotes usually take 3–5 working days.', h), 'a line on how long it takes they did not ask about');
  assertEquals(unaskedOf('Installing each unit usually takes 1–3 days.', h), 'a line on how long it takes they did not ask about');
  assertEquals(unaskedOf('Once the brief is complete, matched suppliers send anonymised quotes.', h), 'a line on what suppliers will do they did not ask about');
  assertEquals(unaskedOf('The supplier can price the camera layout, recording system, cabling and installation from your plan.', h), 'a line on what suppliers will do they did not ask about');
  assertEquals(unaskedOf('Posting your request is free; you pay a reveal fee only when you choose a quote.', h), 'a line on the fee they did not ask about');
  assertEquals(unaskedOf("I've passed this to the fire-safety team.", h), 'a line on an internal hand-off they did not ask about');
  // expert content stays
  assertEquals(unaskedOf('For a balcony outdoor unit, request a T3-rated model for UAE heat.', h), null);
  // asked: it may be said
  assertEquals(unaskedOf('Posting your request is free; you pay a reveal fee only when you choose a quote.', heldState(AC, 'What does it cost me to use QuotesDone?')), null);
  assertEquals(unaskedOf('Quotes usually take 3–5 working days.', heldState(AC, 'How long until I get quotes?')), null);
  assertEquals(unaskedOf('Press "New request" to send it to verified suppliers.', heldState(AC, 'Yes, that is correct.')), null);
});

Deno.test('unasked lines: a greeting after the first reply, and a sentence restating one already said, are dropped', () => {
  const k = heldState([u('السلام عليكم، أريد تجديد مطبخ الفيلا بالكامل.'), a('وعليكم السلام. ما هي أبعاد المطبخ؟')], 'المطبخ 4 في 3 متر.');
  assertEquals(unaskedOf('وعليكم السلام، شكراً على التفاصيل.', k), 'a greeting after the first reply');
  assertEquals(unaskedOf('Hello! Thanks for the details.', heldState([], 'I need CCTV.')), null);
  // fire_alarm_office: the cable correction restated in every turn
  const f = heldState([u('Fire alarm for my office, normal cable is fine.'), a('Normal cable is not accepted: fire alarm circuits need fire-resistant cable approved by Civil Defence. What is the floor area?')], '400 square metres.');
  assertEquals(unaskedOf('Fire alarm circuits need fire-resistant cable approved by Civil Defence, not normal cable.', f), 'restates a sentence already said');
  // the final read-back restates on purpose
  assertEquals(unaskedOf('Here is your request: fire alarm circuits in fire-resistant cable approved by Civil Defence, 400 m².', f), null);
});

// Outside a job conversation (no trade named) the general shape holds: three questions at most. In a job conversation
// the plan's own shape applies (conversation_plan.test.ts: two, the next must-have first).
Deno.test('shape: at most MAX_QUESTIONS questions kept; the filter is fresh per answer', () => {
  const h = heldState([], 'I have a few questions before I post anything.');
  const f = replyFilter(h);
  const qs = ['What is the width of each wall?', 'What finish do you prefer?', 'Do you want drawers inside?', 'Which emirate is the villa in?'];
  assertEquals(qs.map(f), [null, null, null, `more than ${MAX_QUESTIONS} questions`]);
  assertEquals(replyFilter(h)(qs[3]), null);
});

Deno.test('stripReply: the measured ac_undersized_en turn 3 loses its re-ask and unasked lines and keeps its expert content', () => {
  const h = heldState(AC, 'It is a new installation; there is no unit there now. Inverter please. Building needs a permit. Within 2 weeks.');
  const turn3 = 'One ton is likely too small for this room. Building management confirms where the outdoor unit can go. Installing each unit usually takes 1–3 days. Quotes usually take 3–5 working days. Does the apartment use its own air-conditioning units, or central or district cooling? What minimum UAE efficiency rating would you like?';
  const r = stripReply(turn3, h);
  assertEquals(r.text, 'Building management confirms where the outdoor unit can go. What minimum UAE efficiency rating would you like?');
  assertEquals(r.dropped.map((d) => d.why), ['restates a sentence already said', 'a line on how long it takes they did not ask about', 'a line on how long it takes they did not ask about', 'repeats an earlier question']);
});

Deno.test('the model is shown what it must not ask again, in the customer\'s own words', () => {
  // a job conversation: the plan's state block (conversation_plan.stateBlock), then the questions already asked
  const b = heldBlock(heldState(AC, 'Within 2 weeks.'));
  assert(b.includes('ALREADY GIVEN BY THE CUSTOMER') && b.includes('- the emirate and area: "Apartment in Al Nahda, Dubai, owned."'), b);
  assert(b.includes('QUESTIONS ALREADY ASKED') && b.includes('Is this a villa, apartment or another property?'), b);
  // asked "Is this replacing an existing unit?" and answered only the timing: to confirm, never asked again
  assert(b.includes("TO CONFIRM AT THE SUPPLIER'S SITE VISIT") && b.includes('- what is there now'), b);
  assert(/ASK NOW: one short question about where the outdoor unit/.test(b), b);
  assertEquals(heldBlock(heldState([], 'Hello')), '');
});

Deno.test('sentencesOf splits English and Arabic and keeps a tail without a full stop', () => {
  assertEquals(sentencesOf('Noted. ما هي الأبعاد؟ And the finish'), ['Noted.', 'ما هي الأبعاد؟', 'And the finish']);
});

Deno.test('the portal rules carry the intake rule and the reply shape', () => {
  const r = portalRules();
  assert(/senior UAE estimator/.test(r) && /SHAPE OF EVERY REPLY/.test(r) && /at most two questions/.test(r), r.slice(0, 200));
});

// ── the filter around the model (brief_answer.ts `drop`) ─────────────────────────────────────────────────────────
const sse = (chunks: string[]) => new Response(new ReadableStream({ start(c) {
  for (const t of chunks) c.enqueue(new TextEncoder().encode('data: ' + JSON.stringify({ choices: [{ delta: { content: t } }] }) + '\n\n'));
  c.enqueue(new TextEncoder().encode('data: [DONE]\n\n')); c.close();
} }), { headers: { 'content-type': 'text/event-stream', 'x-qd-model': 'anthropic/claude-sonnet-5.5' } });
const json = (o: unknown) => new Response(JSON.stringify(o), { status: 200, headers: { 'content-type': 'application/json' } });
const gw = (replies: Response[]) => { const bodies: Record<string, unknown>[] = []; return { bodies, f: ((_u: string, i: RequestInit) => { bodies.push(JSON.parse(String(i.body))); return Promise.resolve(replies.shift() ?? json({ error: 'no more' })); }) as typeof fetch }; };
const CALL = (h: ReturnType<typeof heldState>): BriefCall => ({ gateway: 'https://gw', secret: 's', fn: 'sales_engineer', agent: 'sales_engineer', taskClass: 'customer_portal_assistant',
  brief: 'brief', sys: 'rules', input: [{ role: 'user', content: h.message }], max: 900, drop: () => replyFilter(h) });

Deno.test('streamed: a re-asked question and an unasked line are never shown; the rest streams in one call', async () => {
  const h = heldState(AC, 'It is a new installation. Inverter please.');
  const g = gw([sse(['An inverter split suits a sunny room. ', 'Quotes usually take 3–5 working days. ', 'Does the apartment use its own air-conditioning units, or central or district cooling? ', 'What efficiency rating would you like?'])]);
  const shown: string[] = [];
  const r = await answerFromBrief(CALL(h), (t) => shown.push(t), g.f);
  assertEquals(shown, ['An inverter split suits a sunny room. ', 'What efficiency rating would you like?']);
  assertEquals(r.reply, 'An inverter split suits a sunny room. What efficiency rating would you like?');
  assertEquals(g.bodies.length, 1, 'dropping costs no second call');
  assertEquals(r.dropped, ['a line on how long it takes they did not ask about | Quotes usually take 3–5 working days.',
    'repeats an earlier question | Does the apartment use its own air-conditioning units, or central or district cooling?']);
});

Deno.test('streamed: an answer with nothing left after the drop is rewritten by the model, and the rewrite is filtered too', async () => {
  const h = heldState(AC, 'Inverter please.');
  const g = gw([sse(['Does the apartment use its own air-conditioning units, or central or district cooling?']),
    json({ content: 'Is this a villa or an apartment? Inverter is the right choice for a sunny room. Is there a power point on the balcony?', model: 'anthropic/claude-sonnet-5.5' })]);
  const r = await answerFromBrief(CALL(h), () => {}, g.f);
  assertEquals(r.reply, 'Inverter is the right choice for a sunny room. Is there a power point on the balcony?');
  assertEquals(r.rewrites, 1);
  assert(String((g.bodies[1].input as { content: string }[]).at(-1)!.content).includes('everything it said was dropped'));
});

Deno.test('the portal turn wires the held state into the prompt and the filter into the answer', async () => {
  const src = await Deno.readTextFile(new URL('./index.ts', import.meta.url));
  assert(src.includes('const held = heldState(turns, message, extract?.slots ?? null);'), 'the held state is no longer computed from the whole conversation and the extraction');
  assert(/extractSlots\(\{[^]*deadline: t0 \+ EXTRACT_BY_MS/.test(src), 'the extraction call is no longer bounded by the turn clock');
  assert(src.includes("(known_ ? known_ + '\\n\\n' : '')"), 'the model is no longer shown what it must not ask again');
  assert(src.includes('drop: () => replyFilter(held),'), 'the reply is no longer filtered sentence by sentence');
});

// Run 143372b1 (27 Oct 2026), the first run with the filter: two summaries lost their confirm request (dropped as a
// supplier-process line) and replies whose questions were all re-asks ended on a statement, so the conversation stalled.
Deno.test('the confirm request that closes a summary is never dropped as a process line', () => {
  const h = heldState(AC, 'Within 2 weeks.');
  assertEquals(unaskedOf('If that is correct, press "New request" to send it to verified suppliers.', h), null);
  assertEquals(unaskedOf('إذا كان الملخص صحيحاً، اضغط "طلب جديد" لإرساله إلى الموردين المعتمدين.', h), null);
  assertEquals(unaskedOf('Matched suppliers send anonymised quotes.', h), 'a line on what suppliers will do they did not ask about');
});

Deno.test('a job reply that ends without a question fails as a whole; one new question passes; a confirmed summary needs none', () => {
  const h = heldState(AC, 'Inverter please.');
  const r = stripReply('Inverter noted. Does the apartment use its own air-conditioning units, or central or district cooling?', h);
  assertEquals(r.text, 'Inverter noted.');
  assert(r.end?.startsWith(ALL_QUESTIONS_DROPPED) && r.end.includes('the next one: where the outdoor unit'), String(r.end));
  assertEquals(stripReply('Inverter noted. Does the balcony have a power point?', h).end, null);
  // run 143372b1, ac_undersized_en turn 4: "Inverter noted." and nothing else
  assert(stripReply('Inverter noted.', h).end?.startsWith('it does not ask about where the outdoor unit'));
  assertEquals(stripReply('Hello, here is how posting works.', heldState([u('How does posting work?'), a('You describe the job. Anything else?')], 'Ok, thanks.')).end, ENDS_WITHOUT_A_QUESTION);
  // a confirmed summary needs no question (in a job conversation: the yes answers a read-back code asked for)
  const SUM = a('Here is your request as I have it: a 2-ton inverter split for the living room in Al Nahda, Dubai. Is this correct?');
  assertEquals(stripReply('Thank you, your request is ready to send.', heldState([...AC, SUM], 'Yes, that is correct.')).end, null);
  assertEquals(stripReply('نشكرك، طلبك جاهز.', heldState([...AC, a('هذا ملخص طلبك: مكيف سبليت انفرتر 2 طن للصالة في النهدة، دبي. هل هذا صحيح؟')], 'نعم، صحيح.')).end, null);
  assertEquals(heldState([...AC, SUM], 'Yes, that is correct.').plan.mode, 'confirmed');
  // a first reply to a general question is not forced to ask
  assertEquals(stripReply('Posting a request is free.', heldState([], 'Is it free to post?')).end, null);
});

Deno.test('a two-part question keeps its one new part when the other part was asked before (run 143372b1, cctv_shop turn 3)', () => {
  const h = heldState([u('I need CCTV for my shop.'), a('Does the mall require its own approved installer, and do you want economy, mid-range or premium equipment?')], 'Mall management requires an approved contractor.');
  assertEquals(newClauseOf('Do you want economy, mid-range or premium equipment, and is the shop rented from the mall or owned?', h), 'Is the shop rented from the mall or owned?');
  assertEquals(replyFilter(h)('Do you want economy, mid-range or premium equipment, and is the shop rented from the mall or owned?'),
    { text: 'Is the shop rented from the mall or owned?', why: 'part of the question was asked before' });
  // both parts new: the question stands as written
  assertEquals(newClauseOf('How many cameras do you need, and do you want night vision?', h), null);
});

Deno.test('streamed: every question dropped -> the model rewrites with a new question', async () => {
  const h = heldState(AC, 'Inverter please.');
  const g = gw([sse(['Inverter noted. ', 'Does the apartment use its own air-conditioning units, or central or district cooling?']),
    json({ content: 'Inverter noted. Does the balcony have a power point or isolator nearby?', model: 'anthropic/claude-sonnet-5.5' })]);
  const r = await answerFromBrief(CALL(h), () => {}, g.f);
  assertEquals(r.reply, 'Inverter noted. Does the balcony have a power point or isolator nearby?');
  assertEquals(r.rewrites, 1);
  assert(String((g.bodies[1].input as { content: string }[]).at(-1)!.content).includes('every question it asked was already asked'));
});

Deno.test('streamed: when no rung writes a new question, the answer is still sent without the re-ask, never no answer', async () => {
  const h = heldState(AC, 'Inverter please.');
  const again = 'Inverter noted. Does the apartment use its own air-conditioning units, or central or district cooling?';
  const g = gw([sse(['Inverter noted. ', 'Does the apartment use its own air-conditioning units, or central or district cooling?']),
    json({ content: again }), json({ content: again }), json({ content: again }), json({ content: again })]);
  const r = await answerFromBrief(CALL(h), () => {}, g.f);
  assertEquals(r.reply, 'Inverter noted.');
  assert(r.attempts.at(-1)!.startsWith('kept:'), r.attempts.join(','));
});

// Run 94311f64 (27 Oct 2026, ac_replacement): the read-back ended "... is that correct?" and was dropped twice as
// "repeats an earlier question" because it restates the questions that gathered the job. A summary is never a re-ask.
Deno.test('the summary and its confirm question are never dropped as re-asks or restatements', () => {
  const h = heldState([...AC, u('It is a new installation; there is no unit there now. Within 2 weeks.'),
    a('One ton is likely too small for this room. Where will the outdoor unit go, and how long is the pipe run?')], 'On the balcony, about 5 m of pipe.');
  assertEquals(h.plan.mode, 'summary');
  const f = replyFilter(h);
  assertEquals(f('Here is the job as you told it: a new inverter split for the 28 m² living room of your owned apartment in Al Nahda, Dubai.'), null);
  assertEquals(f('One ton is likely too small for this room, so suppliers will size it at about 2 to 2.5 tons.'), null);
  assertEquals(f('It uses its own split units, not central or district cooling, is that correct?'), null);
  assertEquals(f.end(), null);
  // before the essentials are in, a restatement is still dropped, and so is an early read-back's confirm question
  const early = heldState([...AC, u('It is a new installation; there is no unit there now. Within 2 weeks.'),
    a('One ton is likely too small for this room. Does the apartment use its own air-conditioning units, or central or district cooling?')], 'Own split units.');
  assertEquals(early.plan.mode, 'ask');
  assertEquals(replyFilter(early)('One ton is likely too small for this room.'), 'restates a sentence already said');
  assertEquals(replyFilter(early)('Did I get everything right?'), 'a read-back before the essentials are in');
  assertEquals(replyFilter(h)('Did I get everything right?'), null);
  // an Arabic read-back's question: kept on the summary turn, dropped before the essentials are in
  assertEquals(replyFilter(heldState([u('أبي أصبغ السور.'), a('كم طول السور؟')], 'السور 60 متر.'))('هل الملخص صحيح؟'), 'a read-back before the essentials are in');
  assertEquals(replyFilter(heldState([u('عندي سؤال عن الموقع.'), a('تفضل، ما سؤالك؟')], 'كيف أرسل الطلب؟'))('هل الملخص صحيح؟'), null);
});

// Run 91fb819d (27 Oct 2026): two false drops found by auditing every dropped sentence in agent_runs.
Deno.test('a question about a figure they gave, and handles vs push-to-open, are not re-asks', () => {
  const p = heldState([u('I want engineered wood flooring in my apartment, about 85 square metres, and in the bathrooms too.')], 'There are ceramic tiles now.');
  assertEquals(reaskOf('Is the 85 square metres the dry areas only, or does it include the bathrooms?', p), null);
  assertEquals(reaskOf('What is the floor area of the apartment?', heldState([u('The floor is about 85 square metres.')], 'ok')), 'asks the floor area again');
  const w = heldState([u('I need two built-in wardrobes.')], 'Change the doors to hinged.');
  assertEquals(reaskOf('For the doors, would you like handles or push-to-open, and standard or premium soft-close hinges?', w), null);
  assertEquals(reaskOf('Do you want sliding or hinged doors?', w), 'asks the door type again');
  // the customer who said "handle-less" is not asked handles vs push-to-open again
  assertEquals(reaskOf('Would you like handles or push-to-open?', heldState([u('Sliding doors, handle-less.')], 'Matte white.')), 'asks the handles again');
});

// Run ecb6b6b2 (painting_ar): the room count was asked three times; list commas had split it into fragments.
Deno.test('a list inside a question is one ask: the Arabic room-count question is caught the second time', () => {
  const h = heldState([u('أبي صباغة شقتي قبل ما أسلم المفتاح.'), a('وكم عدد غرف الشقة تقريباً (استوديو أو غرفة أو غرفتان أو ثلاث)، وهل الدهان للجدران والأسقف معاً؟'),
    u('المالك يبي الجدران والأسقف أبيض.')], 'مو متأكد، شو تنصحني؟');
  // since conversation_plan: caught by the slot it targets (the room count), before any wording is compared
  assertEquals(reaskOf('كم عدد غرف الشقة تقريباً: استوديو، أو غرفة، أو غرفتان، أو ثلاث؟', h), 'asks the count again');
  // two real asks are still two clauses: one new, one repeated
  assertEquals(newClauseOf('كم عدد غرف الشقة تقريباً، ومتى موعد تسليم المفتاح؟', h), 'متى موعد تسليم المفتاح؟');
});

// ── 27 Oct 2026, evening: the three point losses left after 22 scenarios (runs 3de61aa6, ecb6b6b2; 0/22 at 95 %) ─────
// Each case is the seat's own sentence from those runs. Every assertion below fails on #1635 at 1e64a9eca, where the
// filter compared surface text and the model chose what to ask.

// cctv_villa_ar (ecb6b6b2): the camera count asked in turn 1 and again in turn 3 as كاميرا, after the areas were given
Deno.test('re-ask by slot: the Arabic camera count is caught in another word form', () => {
  const h = heldState([u('أبي كاميرات مراقبة للفيلا.'),
    a('كم عدد الكاميرات تقريبًا وأين ستوضع (المداخل، الحوش، الموقف، الأسوار)؟ وهل تريدها للمراقبة العامة فقط أم لتمييز الوجوه وقراءة لوحات السيارات؟'),
    u('خارجي بس: البوابة والحوش الخلفي ومواقف السيارات. فيلا في مردف، ملك.'),
    a('تمام، كاميرات خارجية فقط. هل تفضّل أن تُسجَّل الصور على جهاز تسجيل داخل الفيلا مع مشاهدة عن بُعد عبر الجوال؟')],
    'أبي صورة واضحة بالليل. أبي أشوف من الجوال وتسجيل شهر.');
  // asked in turn 1 (الكاميرات), answered with the areas but no number: the count is to confirm, never asked again
  assertEquals(reaskOf('كم كاميرا تريد تقريبًا (مثلًا واحدة للبوابة، اثنتان للحوش الخلفي، وواحدة للمواقف)؟', h), 'asks the count again');
  assertEquals(reaskOf('ما هي المناطق التي تريد تغطيتها؟', h), 'asks the coverage again');
  assertEquals(reaskOf('هل تريد مشاهدة التسجيل من الجوال؟', h), 'asks the recording again');
});

// painting (the room count asked again as the flat's type)
Deno.test('re-ask by slot: "how many bedrooms" is not asked again as "what type is your flat"', () => {
  const h = heldState([u('I want my apartment painted before I hand back the keys.'), a('How many bedrooms does the apartment have?'), u('Two bedrooms, about 110 square metres.')],
    'The landlord wants white walls and ceilings.');
  assertEquals(reaskOf('What type is your flat: a studio, a 1-bed or a 2-bed?', h), 'asks the count again');
});

// fire_alarm_office (3de61aa6): "Are you the tenant of the unit or the owner?" answered "no preference", then turn 5
// was the bare "Are you the tenant?"
Deno.test('re-ask by slot: a question they were unsure of is to confirm and never asked again, however short', () => {
  const h = heldState([u('We need a fire alarm system for our new office. To save money we will just use normal electrical cable for it.'),
    a("Normal electrical cable is not accepted for a fire alarm. What are the server room's length, width and ceiling height? Are you the tenant of the unit or the owner?"),
    u('Whatever Civil Defence accepts; we have no preference.'),
    a('When do you need it completed by?')], 'Before we open in 8 weeks.');
  assertEquals(reaskOf('Are you the tenant?', h), 'asks the ownership again');
  // ownership is no fire-alarm must-have, so it is not listed to confirm (run 26c1ea71), but it is listed as already asked
  assert(heldBlock(h).includes('QUESTIONS ALREADY ASKED') && heldBlock(h).includes('Are you the tenant of the unit or the owner?'), heldBlock(h));
});

// office_fitout (ecb6b6b2): the finish level (economy, mid-range or premium) asked in turn 2, skipped, asked in turn 3
Deno.test('re-ask by slot: a skipped question is to confirm, so the budget is not asked a second time in new words', () => {
  const h = heldState([u('We just leased an office and need it fitted out.'),
    a('Which area or building is it in, and roughly how large is the office in square metres?'),
    u('About 220 square metres shell and core. JLT Cluster X, Dubai.'),
    a('Which finish level do you want: economy, mid-range or premium?')], 'Move in within 3 months.');
  assertEquals(reaskOf("Is there a budget range you'd like suppliers to work to?", h), 'asks the budget again');
});

// floor_tiles, cctv_shop, boundary_wall_paint_trap_ar, ac_ducted_villa_ar, gypsum_ceiling_ar (5 of 22): the timeline
// was never asked. Code now names it as the next must-have, and a reply that asks something else instead is rewritten.
Deno.test('the timeline: code asks it when it is the next must-have, and a reply that skips it is rewritten', () => {
  const h = heldState([u('How much to replace the floor tiles in my apartment?'),
    a('What is the total floor area, or the room sizes? Should the old tiles be removed, or the new ones laid over them?'),
    u('About 70 square metres, not counting bathrooms. Existing ceramic tiles, some sound hollow. 1-bedroom apartment on Reem Island, Abu Dhabi. I own it.'),
    a('Hollow tiles must come out. What new tile do you want: porcelain or ceramic, and which size? Will you live there during the works?')],
    'Large-format porcelain 60x120, matt light grey. I am living there, so it needs to be done in phases.');
  assert(/ASK NOW: one short question about when they need it done/.test(heldBlock(h)), heldBlock(h));
  assert(stripReply('Porcelain 60x120 suits phased work. Is your budget economy, mid-range or premium?', h).end?.startsWith('it does not ask about when they need it done'));
  assertEquals(stripReply('Porcelain 60x120 suits phased work. When would you like the work done?', h).end, null);
});

// 10 of 22 stopped before the summary: the seat kept asking past the essentials. Once every must-have is in, the reply
// IS the summary: any other question is dropped, and a reply without "is this correct?" is rewritten.
Deno.test('the summary: once the must-haves are in, the reply is the summary and asks only whether it is correct', () => {
  const h = heldState([u('Hi, I want a custom wardrobe for my studio.'), a('What are the wall width and the ceiling height?'),
    u('The wall is about 2.4 m wide and the ceiling is 2.7 m.'), a('What should go inside: hanging, shelves or drawers? Sliding or hinged doors?'),
    u('Mostly hanging, plus 4 shelves and 2 drawers. Sliding doors, handle-less.'), a('Which board and colour would you like, and which emirate and area is the studio in?'),
    u('Matte white. A rented studio in JLT, Dubai.'), a('When do you need it installed?')], 'Within 4 weeks.');
  const f = replyFilter(h);
  assertEquals(f('Would you like soft-close runners on the drawers?'), 'the summary asks only whether it is correct');
  assertEquals(f('Here is your request as I have it: a matte white sliding-door wardrobe, 2.4 m wide and 2.7 m high, in your rented JLT studio.'), null);
  assertEquals(f('Is this correct?'), null);
  assertEquals(f.end(), null);
  assertEquals(stripReply('A handle-less sliding wardrobe suits a studio. Would you like soft-close runners?', h).end, SUMMARY_NEEDS_CONFIRM);
});

// ── THE FOUNDER'S RULING OF 27 OCT 2026: "the engineer and customer support never replies without llm unless the server of
// open router is down". Code decides WHAT is asked; every word the customer reads is the model's. While the model answers,
// each sentence of the reply is a sentence (or one clause) the model wrote: the filter only drops or keeps, and a reply
// with nothing usable is rewritten BY THE MODEL. No reply text exists in code; when no model answer passes the
// safeguards, nothing is sent and the panel shows its own notice (PortalShell's asst_saved), not a reply.
Deno.test('no code-written reply is reachable while the model is up: every shown sentence is the model\'s own', async () => {
  const norm = (t: string) => t.toLowerCase().replace(/[?؟.!,،"'’]/g, '').replace(/\s+/g, ' ').trim();
  const SUM = a('Here is your request as I have it: a white gloss wardrobe in Mirdif. Is this correct?');
  const cases: { h: ReturnType<typeof heldState>; outs: string[] }[] = [
    // ask mode: a re-ask is dropped, and the reply with no question left is rewritten by the model
    { h: heldState(AC, 'Inverter please.'), outs: ['Inverter noted. Does the apartment use its own air-conditioning units, or central or district cooling?', 'Inverter suits sun. Where will the outdoor unit go?'] },
    // ask mode: a two-part question keeps the model's own new clause
    { h: heldState([u('I need CCTV for my shop.'), a('Does the mall require its own approved installer, and do you want economy, mid-range or premium equipment?')], 'Mall management requires an approved contractor.'),
      outs: ['Noted. Do you want economy, mid-range or premium equipment, and which areas must the cameras cover?'] },
    // summary mode: a summary without its confirm question is rewritten by the model
    { h: heldState([u('Hi, I want a custom wardrobe for my studio.'), a('What are the wall width and the ceiling height?'), u('The wall is about 2.4 m wide and the ceiling is 2.7 m.'),
      a('What should go inside, and sliding or hinged doors?'), u('Mostly hanging, plus 4 shelves and 2 drawers. Sliding doors, handle-less.'), a('Which board and colour, and which emirate and area?'),
      u('Matte white. A rented studio in JLT, Dubai.'), a('When do you need it installed?')], 'Within 4 weeks.'),
      outs: ['A sliding wardrobe suits a studio. Would you like soft-close runners?', 'Here is your request as I have it: a matte white sliding wardrobe, 2.4 m by 2.7 m, in JLT, within 4 weeks. Is this correct?'] },
    // confirmed, and a conversation that is not a job
    { h: heldState([u('I need a wardrobe in my villa.'), SUM], 'Yes, that is correct.'), outs: ['Thank you. Press "New request" to send it to verified suppliers. Anything else?'] },
    { h: heldState([], 'How does posting work?'), outs: ['You describe the job and verified suppliers quote. What would you like done?'] },
  ];
  for (const c of cases) {
    const g = gw([sse(c.outs[0].split(/(?<=[.?]) /).map((x) => x + ' ')), ...c.outs.slice(1).map((content) => json({ content, model: 'anthropic/claude-sonnet-5.5' }))]);
    const r = await answerFromBrief(CALL(c.h), () => {}, g.f);
    assert(r.reply, 'the model answered, so there is a reply');
    const written = c.outs.map(norm).join(' | ');
    for (const sentence of sentencesOf(r.reply)) assert(written.includes(norm(sentence)), `"${sentence}" is not the model's: ${written}`);
  }
  // the model up but every answer refused: nothing is sent, never a template
  const h = heldState(AC, 'Inverter please.');
  const again = 'Does the apartment use its own air-conditioning units, or central or district cooling?';
  const g = gw([sse([again]), json({ content: again }), json({ content: again }), json({ content: again }), json({ content: again })]);
  assertEquals((await answerFromBrief(CALL(h), () => {}, g.f)).reply, '');
});

Deno.test('the portal turn returns only the model\'s answer: no reply text is written in the assist action', async () => {
  const src = await Deno.readTextFile(new URL('./index.ts', import.meta.url));
  const assist = src.slice(src.indexOf("if (action === 'assist') {"), src.indexOf('// ── CONVERSATIONS'));
  assert(assist.includes('const reply = a.reply.trim();'), 'the reply is no longer the model answer');
  assert(/return J\(\{ ok: true, seat: 'sales_engineer', answered: true, reply, /.test(assist));
  assert(/return J\(\{ ok: false, seat: 'sales_engineer', answered: false, error: 'no_answer'/.test(assist), 'the no-answer path carries no reply');
  // the only literal is the EMPTY reply of a missing credential (no model could be asked): no text
  assert(!/reply:\s*['"`][^'"`]/.test(assist), 'a literal reply text appeared in the assist action');
  const plan = await Deno.readTextFile(new URL('./conversation_plan.ts', import.meta.url));
  assert(!/reply\s*[:=]\s*['"`]/.test(plan), 'the plan module writes a reply');
});

// Run fafbabb3 (27 Oct 2026, the first 22-scenario run on the plan), kitchen_villa_ar: the sink and hob question was
// placed on no slot, so it never became "to confirm"; every rewrite that asked it was dropped (الحالي read as the existing
// condition), two turns took 54 s and the shape-only fallback sent "تمام، خلال شهرين." with no question.
Deno.test('the kitchen deadlock: the sink and hob question is the services slot, and it is never asked three times', () => {
  const past: Turn[] = [u('السلام عليكم، أريد تجديد مطبخ الفيلا بالكامل.'),
    a('ما شكل المطبخ وما أطوال الجدران؟ وهل المطلوب إزالة المطبخ القديم؟'),
    u('المطبخ على شكل L تقريباً 4 في 3 متر. المطبخ القديم يجب إزالته. فيلا ملك في البرشاء.'),
    a('ما نوع أبواب الخزائن، وأي خامة للأسطح تريد؟'),
    u('خزائن لامعة هاي جلوس، وسطح كوارتز.'),
    a('هل ستكون الأجهزة مدمجة أم منفصلة؟ وأين موقع الحوض والموقد حالياً، وهل يوجد خط غاز؟')];
  const h = heldState(past, 'أبقي الأجهزة الحالية إلا فرن مدمج جديد وشفاط.');
  // asked with the appliances and not answered: to confirm, so code moves on to the timing
  assert(h.plan.toConfirm.has('services'), [...h.plan.toConfirm].join(','));
  assertEquals(h.plan.next, 'timing');
  // a question on the open slot is not dropped for also naming what is "current"
  const k = heldState(past.slice(0, 5), 'خزائن لامعة هاي جلوس، وسطح كوارتز.');
  assertEquals(k.plan.next, 'appliances');
  assertEquals(reaskOf('هل سيبقى الحوض والموقد في مكانهما الحالي أم ستنقلهما؟', heldState(past.slice(0, 5), 'خزائن لامعة هاي جلوس، وسطح كوارتز. أبقي الأجهزة الحالية إلا فرن مدمج جديد وشفاط.')), null);
});

// Run fafbabb3, roof_waterproofing_ar: the opening's "تسريب" (a leak) was read as the existing waterproofing, so its age
// and condition, a must-have, were never asked.
Deno.test('a leak is the problem, not the existing system: the current waterproofing is still asked', () => {
  const h = heldState([], 'عندي تسريب مياه من السطح إلى غرفة النوم بعد المطر.');
  assert(h.plan.open.includes('existing'), h.plan.open.join(','));
});

// Run fafbabb3, kitchen_villa_ar: "إذا كنت غير متأكد، أنصح..." echoed the customer and read as the seat being unsure.
Deno.test('a sentence saying anyone is unsure or does not know is never shown', () => {
  const h = heldState([u('أريد تجديد مطبخ الفيلا.'), a('هل يعمل الموقد على الغاز؟')], 'مو متأكد، شو تنصحني؟');
  assertEquals(unaskedOf('إذا كنت غير متأكد، أنصح بإبقاء الموقد الحالي.', h), 'it says someone does not know or is unsure');
  assertEquals(unaskedOf("If you're not sure, I recommend keeping the hob where it is.", h), 'it says someone does not know or is unsure');
  assertEquals(unaskedOf('أنصح بإبقاء الموقد الحالي وموقعه لتجنب تعديل التوصيلات.', h), null);
});

// The 22-scenario run on the plan, roof_waterproofing_ar: "عزل حالي" and "عزل قديم" (no article) were placed on no slot,
// so after "مو متأكد" the existing waterproofing stayed the next must-have and the conversation stalled.
Deno.test('a slot is read with or without the Arabic article: حالي is الحالي', () => {
  const past: Turn[] = [u('عندي تسريب مياه من السطح إلى غرفة النوم بعد المطر.'),
    a('كم مساحة السطح تقريباً بالمتر المربع؟ وهل يوجد عزل حالي على السطح، وما عمره التقريبي؟'),
    u('السطح خرسانة مستوي تقريباً 150 متر مربع. فيلا في الشارقة.'),
    a('هل يوجد على السطح عزل قديم أو طبقة بلاط فوق الخرسانة، وما عمره إن عُرف؟')];
  const h = heldState(past, 'مو متأكد، شو تنصحني؟');
  assert(h.plan.toConfirm.has('existing'), [...h.plan.toConfirm].join(','));
  assertEquals(h.plan.next, 'system');
  assertEquals(reaskOf('هل العزل الحالي قديم؟', h), 'asks the existing condition again');
});

// LEDGER 1339 (#1640/#1647): `outage` is true only when OpenRouter was down. With the plan's filter around the model, a draft
// the filter or the checks refused is the model UP (outage false, no code text), salvage never brings a dropped re-ask
// back, and only a provider failure on every rung is an outage.
Deno.test('the plan filter and the outage rule: refused drafts are never an outage, salvage keeps the filter', async () => {
  const h = heldState(AC, 'Inverter please.');
  const again = 'Inverter noted. Does the apartment use its own air-conditioning units, or central or district cooling?';
  const up = gw([sse(['Inverter noted. ', 'Does the apartment use its own air-conditioning units, or central or district cooling?']),
    json({ content: again }), json({ content: again }), json({ content: again }), json({ content: again }), json({ content: again })]);
  const r = await answerFromBrief(CALL(h), () => {}, up.f);
  assertEquals(r.outage, false);
  assert(!/central or district cooling/.test(r.reply), 'a dropped re-ask came back through salvage: ' + r.reply);
  const down = gw([new Response('{"error":"upstream"}', { status: 503 }), new Response('{"error":"upstream"}', { status: 503 }),
    new Response('{"error":"upstream"}', { status: 503 }), new Response('{"error":"upstream"}', { status: 503 })]);
  const d = await answerFromBrief(CALL(h), () => {}, down.f);
  assertEquals([d.reply, d.outage], ['', true]);
});

// The final 22-scenario run (26c1ea71, 6cf746dea), judged: the flaws behind the points the plan itself cost.
Deno.test('run 26c1ea71: to-confirm is this job only, move-in is not a date, the area and wall words, no instruction aloud', () => {
  // fire_alarm_warehouse_ar: a finish slot an expert follow-up touched is not listed for a fire alarm
  const fa = heldState([u('عندنا مستودع جديد ونبي نظام إنذار حريق معتمد من الدفاع المدني.'), a('ما لون اللوحة والتشطيب المفضل؟')], 'مو متأكد، شو تنصحني؟');
  assert(!/finish and colour/.test(heldBlock(fa)), heldBlock(fa));
  // parquet_wet_area_trap_en: "empty until we move in" is occupancy, not the timeline
  const pq = heldState([u('I want engineered wood flooring in my apartment, about 85 square metres.')], 'The flat is empty until we move in.');
  assert(pq.plan.open.includes('timing'), pq.plan.open.join(','));
  // painting_ar: "مساحتها" is the size; the wall condition question is the existing slot; a skipped count holds the size
  const pa = heldState([u('أبي صباغة شقتي قبل ما أسلم المفتاح.'), a('كم عدد الغرف في الشقة، أو مساحتها التقريبية؟ وهل الجدران فيها شقوق أو رطوبة أو تقشر؟')], 'المالك يبي الجدران والأسقف أبيض.');
  assert(!pa.plan.open.includes('size') && !pa.plan.open.includes('existing'), pa.plan.open.join(','));
  assertEquals(reaskOf('ما مساحتها التقريبية بالمتر المربع؟', pa), 'asks the sizes again');
  // boundary_wall_paint_trap_ar: an instruction is never spoken aloud
  assertEquals(unaskedOf('ما راح أكرر التصحيح.', pa), 'it speaks an instruction aloud');
  assertEquals(unaskedOf("I won't repeat the correction.", pa), 'it speaks an instruction aloud');
  // kitchen_cabinets_en: the model is told to word the question for this job
  assert(/Word it for this job as they described it/.test(heldBlock(heldState([], 'Can I just replace my kitchen cabinet doors?'))));
});
