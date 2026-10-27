// THE ASYNCHRONOUS RE-ASK (_shared/reask.ts): a turn whose every model draft was refused ends with a MODEL reply in its own
// conversation, never silence and never code text (founder ruling 1339; the independent review of #1640 at 4d5c6cfd0).
// The model is the real aiReply over a stubbed gateway, so the guards and the ladder are the production ones. No network.
// On #1640's head this file fails: reask.ts did not exist, and nothing asked a refused turn again.
import { assert, assertEquals, assertMatch } from 'jsr:@std/assert';
import { aiReply, REPLY_MODEL } from './ai_reply.ts';
import type { LlmReply, ThinkDeps } from './think.ts';
import { englishOnly, extraCheck, NOT_YOURS, priorProblems, reaskDue, reaskOne, reaskRequest, REASK_SURFACES, turnOf, type ReaskIO, type ReaskRow } from './reask.ts';
import { holdingNotice, HOLDING_NOTICE, type DeliveryIO } from './reasoned_delivery.ts';

const COMPANY = 'REVEAL FEE: the customer pays 3.00% of the selected quotation value. No card fee is added.';
function model(answers: (string | null)[]) {
  const calls: { input: string; o: Record<string, unknown> }[] = [];
  const deps = {
    gate: () => Promise.resolve(null),
    llm: (_p: string, _s: string, input: string, o: Record<string, unknown>) => {
      calls.push({ input, o });
      const a = answers.shift();
      return Promise.resolve((a == null ? { content: null, error: 'gateway_http_503' } : { content: a, model: o.counterpartModel ? 'other-family' : 'route' }) as LlmReply);
    },
    embed: () => Promise.resolve(null),
    rpc: (fn: string) => Promise.resolve({ data: fn === 'fn_company_context' ? { block: COMPANY } : null, error: null }),
  } as unknown as ThinkDeps;
  return { deps, calls };
}
const A = (answer: string) => JSON.stringify({ answer });

function io(answers: (string | null)[], over: Partial<ReaskIO> = {}) {
  const m = model(answers);
  const log: string[] = [];
  const x: ReaskIO = {
    write: (r) => aiReply(m.deps, r),
    lookup: (rule, ids) => Promise.resolve({ data: ids.map((id) => ({ [rule.key]: id, source_kind: id === 'gen' ? 'generated' : 'document', tags: [], source_ids: [], runtime_index_eligible: true })), error: null }),
    gate: () => Promise.resolve([]),
    sending: (id) => { log.push('sending ' + id); return Promise.resolve(true); },
    whatsapp: (p, _q, t) => { log.push('wa ' + p + ' ' + t); return Promise.resolve({ delivered: true, via: 'whatsapp_text' }); },
    quoteReview: (r, t) => { log.push('qr ' + r + ' ' + t); return Promise.resolve({ ok: true }); },
    portal: (id, t) => { log.push('portal ' + id + ' ' + t); return Promise.resolve({ ok: true }); },
    intake: (id, tid, t) => { log.push('intake ' + id + ' ' + tid + ' ' + t); return Promise.resolve({ ok: true }); },
    ...over,
  };
  return { x, log, calls: m.calls };
}
const portalRow = (o: Partial<ReaskRow> = {}): ReaskRow => ({
  id: 41, seat: 'sales_engineer', surface: 'sales_engineer.portal_unwritten', attempts: 1, subject: { channel: 'portal', log_id: 900 },
  request: { reask: { message: 'What thickness should a wardrobe shelf be?', audience: 'customer', lang: 'en', problems: ['the figure 450 (the brief states no such fee, price or rate)'],
    own_facts: '', passages: [{ title: 'Shelves', content: 'Shelves over 800 mm span need 25 mm board.', corpus: 'company_faq', record_id: 'f1' },
      { title: 'Model-written guide', content: 'GENERATED-SECRET typical cost ranges', corpus: 'kb_chunks', record_id: 'gen' }] } },
  result: { reask_problems: ['a sentence is longer than 25 words; split it'] }, ...o,
});
const GOOD = 'Use 18 mm board for spans up to 800 mm, and 25 mm board above that. Which span do your shelves have?';

Deno.test('a refused portal turn ends with the MODEL\'s reply in that turn\'s own row: asked again differently, never silent', async () => {
  const { x, log, calls } = io([A(GOOD)]);
  const out = await reaskOne(portalRow(), x);
  assertEquals([out.delivered, out.via], [true, 'portal']);
  assertEquals(log, ['sending 41', 'portal 900 ' + GOOD], 'marked sending first, then the model\'s words into row 900, nothing else');
  // asked DIFFERENTLY: another family first, high effort, and every earlier refusal named in the prompt
  assertEquals(calls[0].o.counterpartModel, REPLY_MODEL);
  assertEquals(calls[0].o.effort, 'high');
  assertMatch(calls[0].input, /AN EARLIER ANSWER TO THIS MESSAGE COULD NOT BE SENT[\s\S]*the figure 450[\s\S]*longer than 25 words/);
});

Deno.test('customerSafe RUNS AGAIN on the re-ask: a model-written record never reaches the prompt (kbChunkIsCustomerFacing)', async () => {
  const r = await reaskRequest(portalRow(), io([]).x.lookup);
  assertMatch(String(r.facts), /25 mm board/);
  assert(!String(r.facts).includes('GENERATED-SECRET'), 'a generated kb_chunks row reached the re-ask prompt');
  assertEquals(r.plainText, undefined, 'aiReply reads JSON: plainText would make every answer read empty');
  assertEquals(r.otherFamilyFirst, true);
});

Deno.test('every guard holds the re-asked words: a refused re-ask sends NOTHING and keeps its problems for the next ask', async () => {
  // the figure check, then the plain-language gate (a 40-word sentence), then the AI word: nothing passes, no sentence salvageable
  const long = 'This shelf answer is one very long sentence that keeps going and going with words about boards and spans and screws and edges and finishes and colours and handles and hinges and rails and more words';
  const { x, log } = io([A('The reveal fee is 5%.'), A(long), A('Our AI says 5%.'), A('The fee is 7%.')]);
  const out = await reaskOne(portalRow(), x);
  assertEquals(out.delivered, false);
  assertEquals(out.outage, false, 'the model answered: not an outage, so nothing code-written may go');
  assert((out.problems ?? []).length > 0, 'the refusals are kept for the next ask');
  assertEquals(log, [], 'nothing was sent: no code text, no unguarded words');
});

Deno.test('the portal\'s own rules run on the re-ask: plain language, no JSON wrapping, the reply guard', () => {
  const c = extraCheck('sales_engineer.portal_unwritten', 'customer', 'en');
  assert(c('{"answer":"Use 18 mm board."}').some((p) => /JSON/.test(p)));
  assert(c('Our AI recommends 18 mm board.').some((p) => /reply rule/.test(p)));
  assertEquals(c('Use 18 mm board.'), []);
  assertEquals(englishOnly('Use 18 mm board.'), []);
  assert(englishOnly('استخدم لوح 18 مم').length === 1, 'a supplier is always answered in English');
});

Deno.test('OpenRouter down on the re-ask: the attempt is an outage, nothing is sent from here (no code text)', async () => {
  const { x, log } = io([null, null, null, null]);
  const out = await reaskOne(portalRow(), x);
  assertEquals([out.delivered, out.outage], [false, true]);
  assertEquals(log, []);
});

Deno.test('WhatsApp, the supplier thread and the request chat: each answer goes back into its own conversation', async () => {
  const wa: ReaskRow = { id: 1, seat: 'customer_support', surface: 'wa_inbound.unwritten_reply', attempts: 1, subject: { channel: 'whatsapp', phone: 'whatsapp:+971500000009' },
    request: { reask: { message: 'Do you cover Ajman?', facts: 'WHAT HAS HAPPENED: nothing yet', audience: 'customer', lang: 'en', problems: ['it defers or says it does not know (answer what can be said now)'] } } };
  const w = io([A('Yes, we cover Ajman. What do you need built there?')]);
  assertEquals((await reaskOne(wa, w.x)).delivered, true);
  assertEquals(w.log[1], 'wa whatsapp:+971500000009 Yes, we cover Ajman. What do you need built there?');

  const qr: ReaskRow = { id: 2, seat: 'sales_engineer', surface: 'supplier_api.quote_review_unwritten', attempts: 1, subject: { channel: 'portal', review_id: 'rv-1', supplier_id: 5 },
    request: { reask: { message: 'هل السعر يشمل التركيب؟', facts: 'The quotation omits installation.', audience: 'supplier', lang: 'en' } } };
  const q = io([A('هل تريد إضافة التركيب؟'), A('Your quotation does not include installation. Please add it as a separate line.')]);
  const qo = await reaskOne(qr, q.x);
  assertEquals(qo.delivered, true);
  assertEquals(q.log[1], 'qr rv-1 Your quotation does not include installation. Please add it as a separate line.', 'a supplier answer in Arabic was refused and rewritten in English');

  const ik: ReaskRow = { id: 3, seat: 'sales_engineer', surface: 'inquiry_intake.unwritten_reply', attempts: 1, subject: { channel: 'request_chat', intake_id: 'in-1', turn_id: 'tid_abc123' },
    request: { reask: { message: 'I need a fire alarm for my ground floor', facts: 'WHAT TO SAY: we are identifying the right trade', audience: 'customer', lang: 'en' } } };
  const i = io([A('Thank you. We are confirming the right trade for your fire alarm and will continue here shortly.')]);
  assertEquals((await reaskOne(ik, i.x)).via, 'request_chat');
  assertEquals(i.log[1], 'intake in-1 tid_abc123 Thank you. We are confirming the right trade for your fire alarm and will continue here shortly.');
  assertEquals(REASK_SURFACES.length, 4);
});

Deno.test('one reply per turn: a row another run is sending is never sent again', async () => {
  const { x, log } = io([A(GOOD)], { sending: () => Promise.resolve(false) });
  const out = await reaskOne(portalRow(), x);
  assertEquals(out.delivered, false);
  assertEquals(log, []);
});

// Review of #1657 (27 Oct 2026): two ticks can hold the same row (a 45 s re-ask plus its send outlasts the 50 s pause).
// The run that LOSES the 'sending' claim must record nothing: recorded as a failure, fn_reask_record read the WINNER's
// marker as "this send failed", failed the row and handed it to the seat while the winner was still delivering.
Deno.test('one reply per turn: the run that loses the sending claim records nothing (the winner keeps the row)', async () => {
  const rpcs: string[] = [];
  const admin = { rpc: (fn: string) => { rpcs.push(fn); return Promise.resolve({ data: fn === 'fn_reask_due' ? [portalRow()] : null, error: null }); } };
  const { x } = io([A(GOOD)], { sending: () => Promise.resolve(false) });
  const res = await reaskDue(admin, { io: x }) as { rows: { via: string; record: { status: string } }[] };
  assertEquals(rpcs, ['fn_reask_due'], 'fn_reask_record must not be called for a lost claim');
  assertEquals([res.rows[0].via, res.rows[0].record.status], [NOT_YOURS, NOT_YOURS]);
  // the winner's path still records its outcome
  const rpcs2: string[] = [];
  const admin2 = { rpc: (fn: string) => { rpcs2.push(fn); return Promise.resolve({ data: fn === 'fn_reask_due' ? [portalRow()] : { status: 'delivered' }, error: null }); } };
  await reaskDue(admin2, { io: io([A(GOOD)]).x });
  assertEquals(rpcs2, ['fn_reask_due', 'fn_reask_record']);
});

Deno.test('after the hand-off, a reviewed reply passes the same gates through the same door; a refused one is not sent', async () => {
  const reviewed = portalRow({ result: { reviewed_state: 'due', reviewed_reply: 'Use 18 mm board up to 800 mm.' } });
  const ok = io([]);
  assertEquals((await reaskOne(reviewed, ok.x)).delivered, true);
  assertEquals(ok.calls.length, 0, 'a reviewed reply is not rewritten by the model');
  const bad = io([], { gate: () => Promise.resolve(['the figure 5']) });
  const out = await reaskOne(reviewed, bad.x);
  assertEquals([out.delivered, out.reviewed, out.problems], [false, true, ['the figure 5']]);
  assertEquals(bad.log, []);
});

Deno.test('a row filed before request.reask existed is read from its question', () => {
  const legacy: ReaskRow = { id: 9, seat: 'customer_support', surface: 'wa_inbound.unwritten_reply', attempts: 0, subject: { phone: '+971500000001' },
    request: { question: 'Reply on WhatsApp.\n\nWHAT HAPPENED ON THAT TURN (facts):\nnothing\n\nMESSAGE:\nمتى يصل العرض؟', context: { audience: 'customer', language: 'ar' } } };
  const t = turnOf(legacy);
  assertEquals([t.message, t.lang, t.audience], ['متى يصل العرض؟', 'ar', 'customer']);
  assertEquals(priorProblems(legacy), []);
});

// ── the hand-off notice is the model's (founder ruling 1339; the coordinator's review of reasoned_delivery.holdingNotice) ──
function noticeIO(w: { reply: string; outage: boolean } | null) {
  const sent: string[] = [];
  const x = {
    waWindowOpen: () => Promise.resolve(true),
    sendWaText: (_p: string, b: string) => { sent.push(b); return Promise.resolve({ ok: true }); },
    ...(w ? { writeNotice: () => Promise.resolve(w) } : {}),
  } as unknown as DeliveryIO;
  return { x, sent };
}
Deno.test('the holding notice: the model writes it; the fixed line only when OpenRouter is down; nothing when the model is up and refused', async () => {
  const row = { id: 5, surface: 'wa_inbound.unwritten_reply', question: 'where is my quote?', subject: { phone: '+971500000001' } };
  const m = noticeIO({ reply: 'Thank you for waiting. A member of our team has your question and will reply in this chat.', outage: false });
  assertEquals((await holdingNotice(row, m.x)).delivered, true);
  assertEquals(m.sent, ['Thank you for waiting. A member of our team has your question and will reply in this chat.']);
  const down = noticeIO({ reply: '', outage: true });
  await holdingNotice(row, down.x);
  assertEquals(down.sent, [HOLDING_NOTICE.en], 'OpenRouter down: the fixed line');
  const up = noticeIO({ reply: '', outage: false });
  assertEquals((await holdingNotice(row, up.x)).delivered, false);
  assertEquals(up.sent, [], 'model up and refused: never the code-written line');
  const blind = noticeIO(null);
  assertEquals((await holdingNotice(row, blind.x)).delivered, false);
  assertEquals(blind.sent, [], 'no writer: a code-written notice is never sent blind');
});
