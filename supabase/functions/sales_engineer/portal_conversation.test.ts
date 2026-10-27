// What the portal conversation already holds, and the lines nobody asked for (portal_conversation.ts). No network.
// Run: deno test supabase/functions/sales_engineer/portal_conversation.test.ts
// Every case below is a sentence the deployed or branch portal seat actually wrote in the adaptive conversation bank on
// 27 Oct 2026 (runs 98aa692f, 4d74ce2d, ab519dba, 4f59f1b9), so these tests fail on a head that does not filter them.
import { assert, assertEquals } from 'jsr:@std/assert';
import { ALL_QUESTIONS_DROPPED, ENDS_WITHOUT_A_QUESTION, heldBlock, newClauseOf, heldState, MAX_QUESTIONS, reaskOf, replyFilter, sameAsk, sentencesOf, stripReply, type Turn, unaskedOf } from './portal_conversation.ts';
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

Deno.test('shape: at most MAX_QUESTIONS questions kept; the filter is fresh per answer', () => {
  const h = heldState([], 'I need two built-in wardrobes.');
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
  const b = heldBlock(heldState(AC, 'Within 2 weeks.'));
  assert(b.includes('ALREADY GIVEN BY THE CUSTOMER') && b.includes('- location: "Apartment in Al Nahda, Dubai, owned."'), b);
  assert(b.includes('QUESTIONS ALREADY ASKED') && b.includes('Is this a villa, apartment or another property?'), b);
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
  assert(src.includes('const held = heldState(turns, message);'), 'the held state is no longer computed from the whole conversation');
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
  assertEquals([r.text, r.end], ['Inverter noted.', ALL_QUESTIONS_DROPPED]);
  assertEquals(stripReply('Inverter noted. Does the balcony have a power point?', h).end, null);
  // run 143372b1, ac_undersized_en turn 4: "Inverter noted." and nothing else
  assertEquals(stripReply('Inverter noted.', h).end, ENDS_WITHOUT_A_QUESTION);
  assertEquals(stripReply('Thank you, your request is ready to send.', heldState(AC, 'Yes, that is correct.')).end, null);
  assertEquals(stripReply('نشكرك، طلبك جاهز.', heldState(AC, 'نعم، صحيح.')).end, null);
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
