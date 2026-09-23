// The one runnable check for chat_answers.ts: the three public questions and the scaffolding case
// from the 21 Sep 2026 audit, EN and AR. `deno test --allow-read supabase/functions/_shared/chat_answers.test.ts`.
//
// WHAT A QUESTION MEANS is reasoned since 23 Sep 2026 (reasoned_channels.ts, founder_instruction 886-903). Every
// case the word-matching version pinned is still pinned, at full strength, in two places: here, each case's
// REASONED meaning (the bank's expected choice) must produce exactly the answer the audit demanded; and in
// scripts/eval/reasoning_bank.json, the same cases score the real reasoning (reasoning_eval.mjs --live) and the
// engine and scorer on every one of them in CI (mock mode).
import { assertEquals, assert } from 'jsr:@std/assert@1';
import { pickFaq, quoteAnswer, notYet, langOf, type QuestionType } from './chat_answers.ts';
import { quoteOptions, SITE_OPTIONS } from './reasoned_channels.ts';

type Case = { surface: string; q: string; options?: { id: string }[]; expect: { choice: string; faq_id?: number } };
const BANK = (JSON.parse(Deno.readTextFileSync(new URL('../../../scripts/eval/reasoning_bank.json', import.meta.url))).cases as Case[]);
const cases = (surface: string) => BANK.filter((c) => c.surface === surface);

const FAQS = [
  { id: 13, question: 'How many suppliers receive my RFQ?', answer: 'a handful' },
  { id: 26, question: 'How long does the process take?', answer: '3-5 working days' },
  { id: 30, question: 'What are the platform fees?', answer: '3% reveal fee' },
  { id: 43, question: 'How many suppliers receive the same RFQ?', answer: 'supplier twin' },
  { id: 167, question: 'Refund policy', answer: 'quotes are refunded when …' },
  { id: 604, question: 'كم عدد الموردين الذين يستلمون طلبي؟', answer: 'عدد محدود' },
  { id: 609, question: 'ما هي رسوم المنصة؟', answer: 'رسوم كشف 3٪' },
  { id: 903, question: 'كم يستغرق الحصول على عروض الأسعار؟', answer: '3 إلى 5 أيام عمل' },
];
/** The widget's answer for a reasoned meaning: the FAQ for cost / count / timeline, nothing canned otherwise. */
const widgetFaq = (q: string, choice: string) => pickFaq((['cost', 'count', 'timeline'].includes(choice) ? choice : null) as QuestionType, langOf(q), FAQS);

Deno.test('the three public questions reach the FAQ that asks them, EN and AR; a fee or duration about something else reaches none', () => {
  const route = cases('shared.route_question');
  assert(route.length >= 20, 'every case the regex version pinned is in the bank: ' + route.length);
  const ids = new Set(SITE_OPTIONS.map((o) => o.id));
  for (const c of route) {
    assert(ids.has(c.expect.choice), c.q + ': the expected meaning is one the widget offers');
    assertEquals(widgetFaq(c.q, c.expect.choice)?.id ?? null, c.expect.faq_id ?? null, c.q);
  }
  // the pinned audit cases, by name
  const at = (q: string) => route.find((c) => c.q === q)!;
  assertEquals(widgetFaq('how many quotes will I get?', at('how many quotes will I get?').expect.choice)?.id, 13);
  assertEquals(widgetFaq('what does it cost?', at('what does it cost?').expect.choice)?.id, 30);
  assertEquals(widgetFaq('how long until I receive quotes?', at('how long until I receive quotes?').expect.choice)?.id, 26);
  assertEquals(at('what is the parking fee at Dubai Mall').expect.choice, 'none');
  assertEquals(at('what should a gypsum false ceiling cost per sqm in Dubai').expect.choice, 'none', 'a per-trade price belongs to the price guide');
  assertEquals(pickFaq('count', 'en', FAQS, 'supplier')?.id, 43);
  assertEquals(pickFaq(null, 'en', FAQS), null, 'no reasoned type, no canned answer');
});

const QUOTE = {
  id: 'q1', rfq_no: 151768, inquiry_summary: 'False ceilings and gypsum cornice for a private villa in Khawaneej',
  inquiry_category: 'gypsum', supplier_label: 'Supplier A', amount: 25920, status: 'revealed',
  exclusions: 'electrical fittings painting of walls scaffolding above 4m', scope: null, warranty: null,
};
const choiceOf = (q: string) => cases('shared.quote_answer').find((c) => c.q === q)!.expect.choice;

Deno.test('a question about the quote is answered from the quote line, and the threshold is compared', () => {
  const qEn = 'The quote excludes scaffolding above 4 m, but my ceilings are only 3.2 m — does that exclusion affect me?';
  // The options the portal offers for this quote carry the applies / does-not-apply pair (one metre figure each side).
  const offered = quoteOptions([QUOTE], qEn).map((o) => o.id);
  for (const c of cases('shared.quote_answer')) assert(offered.includes(c.expect.choice), c.q + ': ' + c.expect.choice + ' is offered');
  const en = quoteAnswer(choiceOf(qEn), [QUOTE], 'en', qEn);
  assert(en && en.basis === 'quote_field' && en.field === 'exclusions', JSON.stringify(en));
  assert(en.reply.includes('scaffolding above 4m'), en.reply);
  assert(en.reply.includes('3.2 m) is below the 4 m threshold') && en.reply.includes('does not apply'), en.reply);
  assert(!/\[company_faq/.test(en.reply));
  const qAr = 'عرض السعر يستثني السقالات فوق 4 متر لكن ارتفاع الأسقف عندي 3.2 متر فقط، هل يؤثر هذا الاستثناء عليّ؟';
  const ar = quoteAnswer(choiceOf(qAr), [QUOTE], 'ar', qAr);
  assert(ar && ar.field === 'exclusions', JSON.stringify(ar));
  assert(ar.reply.includes('scaffolding above 4m') && ar.reply.includes('لا ينطبق'), ar.reply);
  // a named field the supplier left blank is answered as absent, never invented
  const w = quoteAnswer(choiceOf('what warranty does the quote give?'), [QUOTE], 'en');
  assert(w && w.basis === 'quote_field_absent' && w.field === 'warranty' && /did not state warranty/.test(w.reply), JSON.stringify(w));
  // a question not about any quote falls through
  assertEquals(quoteAnswer(choiceOf('does a Dubai supplier cover Abu Dhabi as well?'), [QUOTE], 'en'), null);
  assertEquals(quoteAnswer('q:0:exclusions', [], 'en'), null);
  // held (null) or an id we never offered: nothing is answered on a guess
  assertEquals(quoteAnswer(null, [QUOTE], 'en'), null);
  assertEquals(quoteAnswer('q:0:not_a_field', [QUOTE], 'en'), null);
  assertEquals(quoteAnswer('q:7:exclusions', [QUOTE], 'en'), null);
});

Deno.test('a passage that does not answer the question is off topic; one that does is chosen, EN and AR', () => {
  const p = cases('sales_engineer.on_topic');
  assertEquals(p.length, 3);
  assertEquals(p[0].expect.choice, 'none', 'the Dubai-coverage passage does not answer the exclusion question');
  assertEquals(p[1].expect.choice, 'kb:1', 'the exclusions passage does');
  assertEquals(p[2].expect.choice, 'kb:0', 'Arabic: the supplier-count passage answers the supplier-count question');
  for (const c of p) assert(c.options!.some((o) => o.id === c.expect.choice));
  assertEquals(langOf('hello', 'ar'), 'ar');
  assertEquals(langOf('مرحبا'), 'ar');
  assert(/task #12/.test(notYet('en', 12, 'sales_engineer')) && /المهمة رقم 12/.test(notYet('ar', 12, 'sales_engineer')));
});
