// supportReply() with a STUBBED model (founder instruction 781; the model hold stays on). No network, no paid call.
import { assert, assertEquals, assertMatch } from 'jsr:@std/assert';
import type { LlmReply, Phase, ThinkDeps } from './think.ts';
import { briefFiles, jobQuery, PORTAL_INTAKE, portalGuide, supportReply } from './support_reply.ts';

function stub(o: { gate?: unknown; synth?: (string | LlmReply)[]; corpus?: unknown[]; verify?: string | null }) {
  const calls: { phase: Phase; system: string; input: string }[] = []; const rpcs: string[] = [];
  const synth = [...(o.synth ?? [])];
  const deps: ThinkDeps = {
    gate: () => Promise.resolve((o.gate ?? { allowed: false, rule: 'route_not_registered' }) as never),
    llm: (phase, system, input) => {
      calls.push({ phase, system, input });
      if (phase === 'decompose') return Promise.resolve({ content: JSON.stringify({ steps: [{ id: 's1', goal: 'the rule', query: 'non-response refund rule' }], facts: [], high_stakes: false }), model: 'stub' });
      // the widget's answers are always independently checked now (12 Oct 2026): the reviewer agrees here
      if (phase === 'verify') return Promise.resolve({ content: o.verify === undefined ? JSON.stringify({ verdict: 'agree', problems: [] }) : o.verify, model: 'stub/other' });
      const n = synth.shift();
      return Promise.resolve(typeof n === 'string' ? { content: n, model: 'stub/qwen' } : (n ?? { content: null, error: 'circuit_open' }));
    },
    embed: () => Promise.resolve([0.1, 0.2]),
    rpc: (fn) => {
      rpcs.push(fn);
      if (fn === 'fn_support_corpus_search') return Promise.resolve({ data: o.corpus ?? [], error: null });
      if (fn === 'fn_case_recall') return Promise.resolve({ data: { cases: [] }, error: null });
      if (fn === 'fn_reason_retrieve') return Promise.resolve({ data: [], error: null });
      return Promise.resolve({ data: 1, error: null });
    },
  };
  return { deps, calls, rpcs };
}
const REFUND = { content: 'Non-response: if the revealed supplier does not reply within 5 working days, the customer is refunded everything paid.', citation: 'FAQ 41' };
const ANSWER = JSON.stringify({ answer: 'If the supplier you revealed does not reply within 5 working days, everything you paid is refunded. I have passed it to our management to confirm.', reasoning: ['s1: FAQ 41 sets the 5-working-day rule'], cited: [], confidence: 0.8, asked_back: null, route: 'ceo' });

Deno.test('the gateway answers: the reply is COMPOSED, the canned road never runs, the narrowed topic is in the prompt', async () => {
  const s = stub({ synth: [ANSWER], corpus: [REFUND] });
  let canned = 0;
  // The tricky wording that leaked through the cost FAQ: it must reach the model, not a stored answer.
  const r = await supportReply(s.deps, { channel: 'widget', message: 'what does it cost me if the supplier never replies?', lang: 'en', audience: 'customer' },
    () => { canned++; return Promise.resolve('Posting is free; the reveal fee is 3%.'); });
  assertEquals(r.path, 'reasoned');
  assertEquals(canned, 0);
  assertMatch(r.reply, /5 working days/);
  assertEquals(r.seat, 'ceo');
  assertEquals(r.grounded, true, 'the corpus answered this topic');
  assert(s.rpcs.includes('fn_support_corpus_search'), 'the knowledge was narrowed before reasoning');
  assertMatch(s.calls.find((c) => c.phase === 'synthesise')!.input, /FAQ 41/);
  assertMatch(s.calls.find((c) => c.phase === 'synthesise')!.system, /"route"/);
});

Deno.test('the caller\'s own retrieval is the narrowed topic: no second corpus search', async () => {
  const s = stub({ synth: [ANSWER] });
  await supportReply(s.deps, { channel: 'whatsapp', message: 'x', lang: 'en', audience: 'customer', passages: [REFUND] }, () => Promise.resolve(null));
  assert(!s.rpcs.includes('fn_support_corpus_search'));
});

// Rulings 1195/1196 (12 Oct 2026): the caller's canned road is never sent. When the reasoned chain cannot answer, the
// reply is still written by a model (aiReply); when no model answers, it is '' and nothing is sent.
Deno.test('the chain cannot answer: a model writes the reply directly, the caller canned text is never sent', async () => {
  const s = stub({ gate: { allowed: false, rule: 'founder_hold' }, synth: [JSON.stringify({ answer: 'Hello! How can we help with your job?' })] });
  const r = await supportReply(s.deps, { channel: 'whatsapp', message: 'hi', lang: 'en', audience: 'visitor' }, () => Promise.resolve('Thanks for your message.'));
  assertEquals(r.reply, 'Hello! How can we help with your job?');
  assertEquals(r.path, 'reasoned');
  assert(!s.rpcs.includes('fn_reason_hold'), 'a reply already went out; a replay would send a second one');
});

Deno.test('no model answers at all: no text, never the caller canned line', async () => {
  const s = stub({ synth: [{ content: null, error: 'circuit_open' }] });
  const r = await supportReply(s.deps, { channel: 'portal', message: 'q', lang: 'ar', audience: 'customer', seat: 'sales_engineer' }, () => Promise.resolve('شكرًا لرسالتك.'));
  assertEquals(r.path, 'fallback');
  assertEquals(r.reply, '');
});

// prevented by: this test (review of #1330). A reply the guard refuses is rewritten BY A MODEL, never patched by code.
Deno.test('a composed reply the guard refuses is rewritten by a model; an unknown route is not trusted', async () => {
  const bad = JSON.stringify({ answer: 'Our AI matches you with suppliers anonymously.', reasoning: ['s1: how it works'], cited: [], confidence: 0.7, route: 'hr' });
  const s = stub({ synth: [bad, JSON.stringify({ answer: 'Our Smart Engine matches you with suppliers anonymously.' })] });
  const r = await supportReply(s.deps, { channel: 'email', message: 'how does it work', lang: 'en', audience: 'customer' }, () => Promise.resolve(null));
  assertEquals(r.path, 'reasoned');
  assertEquals(r.reply, 'Our Smart Engine matches you with suppliers anonymously.');
  assertEquals(r.seat, null);
  assertMatch(r.reason ?? '', /^direct: guard: ai_word/);
});

// ── the plain-language gate (founder instruction 1013 item 7) ──────────────────────────────────────
const LONG = JSON.stringify({ answer: 'Pursuant to the aforementioned policy and notwithstanding any prior correspondence regarding the RFQ you submitted through the platform, the escalation of your matter will be facilitated by the relevant team within the applicable timeframe once all documentation has been received and reviewed in full by our staff.', reasoning: ['s1: FAQ 41'], cited: [], confidence: 0.8, route: 'customer_support' });

Deno.test('1013/7: a jargon-heavy, one-long-sentence reply is rewritten through the model and the plain rewrite goes out', async () => {
  const s = stub({ synth: [LONG, JSON.stringify({ answer: 'We have your request. Our team will reply within 2 working days.' })], corpus: [REFUND] });
  const r = await supportReply(s.deps, { channel: 'widget', message: 'where is my quote?', lang: 'en', audience: 'customer' }, () => Promise.resolve('canned'));
  assertEquals(r.path, 'reasoned');
  assertEquals(r.rewritten, true);
  assertEquals(r.reply, 'We have your request. Our team will reply within 2 working days.');
  assert(r.readability?.ok);
  assert(s.rpcs.includes('fn_support_reply_readability_log'), 'the score is logged for the monthly self-review');
});

Deno.test('1013/7: a rewrite that is still not plain goes to a direct model reply, never the canned answer', async () => {
  const s = stub({ synth: [LONG, LONG, JSON.stringify({ answer: 'Your quote is on its way. You will see it in My requests.' })], corpus: [REFUND] });
  const r = await supportReply(s.deps, { channel: 'whatsapp', message: 'where is my quote?', lang: 'en', audience: 'customer' }, () => Promise.resolve('Thanks. Our team will reply soon.'));
  assertEquals(r.reply, 'Your quote is on its way. You will see it in My requests.');
  assertMatch(r.reason ?? '', /^direct: readability: /);
});

Deno.test('1013/7: an Arabic customer who gets an English reply is rewritten into Arabic', async () => {
  const en = JSON.stringify({ answer: 'Your request is received. We will reply soon.', reasoning: ['s1: FAQ 41'], cited: [], confidence: 0.8, route: 'customer_support' });
  const s = stub({ synth: [en, JSON.stringify({ answer: 'وصلنا طلبك. سنرد عليك قريبًا.' })], corpus: [REFUND] });
  const r = await supportReply(s.deps, { channel: 'whatsapp', message: 'وين عرض السعر؟', lang: 'ar', audience: 'customer' }, () => Promise.resolve(null));
  assertEquals(r.rewritten, true);
  assertEquals(r.reply, 'وصلنا طلبك. سنرد عليك قريبًا.');
});

Deno.test('1013/7: a plain reply is not rewritten (no second model call)', async () => {
  const s = stub({ synth: [ANSWER], corpus: [REFUND] });
  const r = await supportReply(s.deps, { channel: 'widget', message: 'q', lang: 'en', audience: 'customer' }, () => Promise.resolve(null));
  assertEquals(r.rewritten, false);
  assertEquals(s.calls.filter((c) => c.phase === 'synthesise').length, 1);
});

// ── the widget sends only CHECKED text (review of #1330, 12 Oct 2026) ─────────────────────────────
// prevented by: these tests. think() returns 'answered' even when the independent check did not run or disagreed;
// on the widget such a reply must never be sent (nor cached by site_assistant): the caller's road answers.
const SHORT = JSON.stringify({ answer: 'The reveal fee is 3% of the quote you choose. No card fee is added, and no VAT is charged on it.', reasoning: ['s1: FAQ 30'], cited: [], confidence: 0.8, route: 'customer_support' });
Deno.test('widget: a reply the check did not run on goes to the fallback, not to the visitor', async () => {
  const s = stub({ gate: { allowed: true }, synth: [SHORT], corpus: [REFUND], verify: null });
  const r = await supportReply(s.deps, { channel: 'widget', message: 'how much is the reveal fee?', lang: 'en', audience: 'visitor' }, () => Promise.resolve('canned'));
  assertEquals(r.path, 'fallback');
  assertMatch(String(r.reason), /unchecked/);
});
Deno.test('widget: a reply the check disagreed with goes to the fallback, even after its correction', async () => {
  const s = stub({ gate: { allowed: true }, synth: [SHORT, SHORT], corpus: [REFUND], verify: JSON.stringify({ verdict: 'disagree', problems: ['fee wrong'] }) });
  const r = await supportReply(s.deps, { channel: 'widget', message: 'how much is the reveal fee?', lang: 'en', audience: 'visitor' }, () => Promise.resolve('canned'));
  assertEquals(r.path, 'fallback');
});
Deno.test('widget: an agreed reply goes out, marked agreed, and the trade choice rides on the same call', async () => {
  const s = stub({ gate: { allowed: true }, synth: [JSON.stringify({ ...JSON.parse(SHORT), price_trade: 'gypsum-ceilings' })], corpus: [REFUND] });
  const r = await supportReply(s.deps, { channel: 'widget', message: 'what does a gypsum ceiling cost?', lang: 'en', audience: 'visitor', priceTrades: ['gypsum-ceilings'] }, () => Promise.resolve('canned'));
  assertEquals(r.path, 'reasoned');
  assertEquals(r.verified, 'agreed');
  assertEquals(r.priceTrade, 'gypsum-ceilings');
  assertEquals(s.calls.filter((c) => c.phase === 'decompose').length, 0);
});
Deno.test('widget: the plain-language rewrite runs BEFORE the check, so the reviewer reads the text that is sent', async () => {
  const s = stub({ gate: { allowed: true }, synth: [LONG, JSON.stringify({ answer: 'We have your request. Our team will reply within 2 working days.' })], corpus: [REFUND] });
  const r = await supportReply(s.deps, { channel: 'widget', message: 'where is my quote?', lang: 'en', audience: 'customer' }, () => Promise.resolve('canned'));
  assertEquals(r.reply, 'We have your request. Our team will reply within 2 working days.');
  const order = s.calls.map((c) => c.phase);
  assert(order.lastIndexOf('synthesise') < order.indexOf('verify'));
  assertMatch(s.calls.find((c) => c.phase === 'verify')!.input, /reply within 2 working days/);
});

// prevented by: this test (ruling 1200). A message with a photo is answered by the direct model reply, image attached.
Deno.test('a photo goes to the direct model reply as an image', async () => {
  const s = stub({ synth: [JSON.stringify({ answer: 'That wall between the door and window suits a sliding wardrobe. What width is it?' })] });
  const seen: unknown[] = [];
  const deps = { ...s.deps, llm: (p: never, sys: string, input: string, o: { images?: string[] }) => { seen.push(o.images); return s.deps.llm(p, sys, input, o as never); } };
  const r = await supportReply(deps as never, { channel: 'portal', message: 'wardrobe here?', lang: 'en', audience: 'customer', seat: 'sales_engineer', images: ['data:image/jpeg;base64,AAAA'] }, () => Promise.resolve(null));
  assertEquals(r.reply, 'That wall between the door and window suits a sliding wardrobe. What width is it?');
  assertMatch(r.reason ?? '', /^direct: photo/);
  assertEquals(seen[0], ['data:image/jpeg;base64,AAAA']);
});

// prevented by: these tests (ledger 1200, 27 Oct 2026). The portal takes a job brief like a senior estimator: the intake
// rule reaches the answering model on BOTH roads (the reasoned chain and the direct reply), never in the retrieval query;
// the plan is handed over (no planning call), its query carries the job, and every portal answer is independently checked.
Deno.test('portal: the intake rule rides in the case, the plan is handed over with the job in its query, and the answer is checked', async () => {
  const s = stub({ gate: { allowed: true }, synth: [JSON.stringify({ answer: 'Sliding doors suit a studio. What is the depth you can spare, and do you want a mirror on one door?', reasoning: ['s1: a studio wardrobe needs its depth and door finish'], cited: [], confidence: 0.8, asked_back: null, route: 'sales_engineer' })], corpus: [] });
  const conversation = [{ role: 'customer' as const, text: 'I want a custom wardrobe for my studio.' }, { role: 'seat' as const, text: 'What width is the wall, and sliding or hinged doors?' }];
  const r = await supportReply(s.deps, { channel: 'portal', message: 'Sliding doors, handle-less.', lang: 'en', audience: 'customer', seat: 'sales_engineer', conversation,
    passages: [{ content: 'Wardrobe spec checklist: carcass board, door type, internal layout', citation: 'pack:joinery' }] }, () => Promise.resolve(null));
  assertEquals(r.path, 'reasoned');
  const phases = s.calls.map((c) => c.phase);
  assert(!phases.includes('decompose'), 'the plan is handed over: no planning call');
  assert(phases.includes('verify'), 'every portal answer is independently checked');
  const synth = s.calls.find((c) => c.phase === 'synthesise')!;
  assertMatch(synth.system, /senior UAE estimator/);
  assertMatch(synth.system, /Never ask again for anything they already stated/);
  assertMatch(synth.system, /wrong, unsafe, or not accepted in the UAE/);
  // the trade playbooks (knowledge/brief/conversation) reach the answering call: the founder's wardrobe example among them
  assertMatch(synth.system, /Conversation playbook: Joinery and furniture/);
  assertMatch(synth.system, /Founder's example: wardrobe for a studio/);
  assertMatch(synth.system, /How you hold a conversation/);
  assert(!/senior UAE estimator|Conversation playbook/.test(synth.input), 'neither rides in the payload (question, case) that is embedded or stored');
});

Deno.test('portal: a photo turn is answered by the direct reply with the same intake rule', async () => {
  const s = stub({ synth: [JSON.stringify({ answer: 'I can see the wall beside the window. What is its width and ceiling height?' })] });
  await supportReply(s.deps, { channel: 'portal', message: 'wardrobe here?', lang: 'en', audience: 'customer', seat: 'sales_engineer', images: ['data:image/png;base64,AAAA'] }, () => Promise.resolve(null));
  assertMatch(s.calls[0].system, /senior UAE estimator/);
});

Deno.test('the widget and WhatsApp do not get the portal intake rule (ruling 1249: the homepage holds no job conversation)', async () => {
  const s = stub({ gate: { allowed: true }, synth: [ANSWER], corpus: [REFUND] });
  await supportReply(s.deps, { channel: 'whatsapp', message: 'what does it cost?', lang: 'en', audience: 'customer' }, () => Promise.resolve(null));
  assert(!s.calls.some((c) => /senior UAE estimator/.test(c.input) || /senior UAE estimator/.test(c.system)));
});

Deno.test('portalGuide: the intake rule, the method and all ten trade playbooks from the compiled brief, nothing else', () => {
  const g = portalGuide();
  assert(g.startsWith(PORTAL_INTAKE));
  assertEquals((g.match(/^# Conversation playbook:/gm) ?? []).length, 10);
  assert(!g.includes('company brief for the customer-facing agents'), 'company.md already rides as the settled facts');
  assertEquals(briefFiles('<<<FILE knowledge/brief/a.md>>>\nA\n<<<FILE knowledge/brief/conversation/b.md>>>\nB\n', /conversation\//), ['B']);
});

Deno.test('jobQuery: the job and this message; the message alone on the first turn; never past 500 characters', () => {
  assertEquals(jobQuery({ message: 'Sliding doors.', conversation: [{ role: 'customer', text: 'A wardrobe for my studio.' }, { role: 'seat', text: 'Which doors?' }] }), 'A wardrobe for my studio.\nSliding doors.');
  assertEquals(jobQuery({ message: 'A wardrobe for my studio.', conversation: [] }), 'A wardrobe for my studio.');
  assertEquals(jobQuery({ message: 'x'.repeat(900), conversation: [{ role: 'customer', text: 'y'.repeat(900) }] }).length, 500);
});
