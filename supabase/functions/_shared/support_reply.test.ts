// supportReply() with a STUBBED model (founder instruction 781; the model hold stays on). No network, no paid call.
import { assert, assertEquals, assertMatch } from 'jsr:@std/assert';
import type { LlmReply, Phase, ThinkDeps } from './think.ts';
import { supportReply } from './support_reply.ts';

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

Deno.test('the founder\'s hold: no model call at all, the deterministic road answers, nothing is queued', async () => {
  const s = stub({ gate: { allowed: false, rule: 'founder_hold' } });
  const r = await supportReply(s.deps, { channel: 'whatsapp', message: 'hi', lang: 'en', audience: 'visitor' }, () => Promise.resolve('Thanks for your message.'));
  assertEquals(r.path, 'fallback');
  assertEquals(r.reply, 'Thanks for your message.');
  assertEquals(s.calls.length, 0);
  assert(!s.rpcs.includes('fn_reason_hold'), 'a reply already went out; a replay would send a second one');
});

Deno.test('the gateway down mid-reply: the fallback answers', async () => {
  const s = stub({ synth: [{ content: null, error: 'circuit_open' }] });
  const r = await supportReply(s.deps, { channel: 'portal', message: 'q', lang: 'ar', audience: 'customer', seat: 'sales_engineer' }, () => Promise.resolve('شكرًا لرسالتك.'));
  assertEquals(r.path, 'fallback');
  assertEquals(r.reply, 'شكرًا لرسالتك.');
});

Deno.test('the composed reply passes the outgoing guard; an unknown route is not trusted', async () => {
  const bad = JSON.stringify({ answer: 'Our AI matches you with suppliers anonymously.', reasoning: ['s1: how it works'], cited: [], confidence: 0.7, route: 'hr' });
  const s = stub({ synth: [bad] });
  const r = await supportReply(s.deps, { channel: 'email', message: 'how does it work', lang: 'en', audience: 'customer' }, () => Promise.resolve(null));
  assertEquals(r.path, 'reasoned');
  assert(!/\bAI\b/.test(r.reply), r.reply);
  assertEquals(r.seat, null);
  assertEquals(r.grounded, false, 'no topic knowledge and nothing cited: the widget files this as a knowledge gap');
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

Deno.test('1013/7: a rewrite that is still not plain sends the canned answer, never the unreadable one', async () => {
  const s = stub({ synth: [LONG, LONG], corpus: [REFUND] });
  const r = await supportReply(s.deps, { channel: 'whatsapp', message: 'where is my quote?', lang: 'en', audience: 'customer' }, () => Promise.resolve('Thanks. Our team will reply soon.'));
  assertEquals(r.path, 'fallback');
  assertEquals(r.reply, 'Thanks. Our team will reply soon.');
  assertMatch(r.reason ?? '', /^readability: /);
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
const SHORT = JSON.stringify({ answer: 'The reveal fee is 3% of the quote you choose. No card fee is added.', reasoning: ['s1: FAQ 30'], cited: [], confidence: 0.8, route: 'customer_support' });
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
