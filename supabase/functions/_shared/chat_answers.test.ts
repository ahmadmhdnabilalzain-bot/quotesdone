// The one runnable check for chat_answers.ts: the three public questions and the scaffolding case
// from the 21 Sep 2026 audit, EN and AR. `deno test supabase/functions/_shared/chat_answers.test.ts`.
import { assertEquals, assert } from 'jsr:@std/assert@1';
import { routeQuestion, pickFaq, quoteAnswer, onTopic, notYet, langOf } from './chat_answers.ts';

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

Deno.test('the three public questions route to the FAQ that asks them, EN and AR', () => {
  assertEquals(routeQuestion('how many quotes will I get?'), 'count');
  assertEquals(routeQuestion('what does it cost?'), 'cost');
  assertEquals(routeQuestion('how long until I receive quotes?'), 'timeline');
  assertEquals(routeQuestion('كم عدد عروض الأسعار التي سأحصل عليها؟'), 'count');
  assertEquals(routeQuestion('كم تكلفة الخدمة؟'), 'cost');
  assertEquals(routeQuestion('كم يستغرق الحصول على عروض الأسعار؟'), 'timeline');
  assertEquals(pickFaq('count', 'en', FAQS)?.id, 13);
  assertEquals(pickFaq('cost', 'en', FAQS)?.id, 30);
  assertEquals(pickFaq('timeline', 'en', FAQS)?.id, 26);
  assertEquals(pickFaq('count', 'ar', FAQS)?.id, 604);
  assertEquals(pickFaq('cost', 'ar', FAQS)?.id, 609);
  assertEquals(pickFaq('timeline', 'ar', FAQS)?.id, 903);
  assertEquals(pickFaq('count', 'en', FAQS, 'supplier')?.id, 43);
  // a per-trade price question belongs to the price guide, not the fee FAQ
  assertEquals(routeQuestion('what should a gypsum false ceiling cost per sqm in Dubai'), null);
  assertEquals(routeQuestion('كم تكلفة السقف الجبسي للمتر المربع في دبي'), null);
  // nothing else is routed
  assertEquals(routeQuestion('does a Dubai supplier cover Abu Dhabi as well'), null);
  // review of PR #783: a fee / duration question about something else is NOT ours to answer
  for (const q of ['what is the parking fee at Dubai Mall', 'how long is a football match',
    'كم رسوم ركن السيارة في دبي مول؟', 'كم يستغرق مباراة كرة القدم؟', 'كم تستغرق مباراة كرة القدم؟']) {
    assertEquals(routeQuestion(q), null, q);
    assertEquals(pickFaq(routeQuestion(q), langOf(q), FAQS), null, q);
  }
  // …while the same words about us still are
  assertEquals(routeQuestion('what are your fees?'), 'cost');
  assertEquals(routeQuestion('is the service free?'), 'cost');
  assertEquals(routeQuestion('how long does a supplier take to quote?'), 'timeline');
  assertEquals(routeQuestion('هل المنصة مجانية؟'), 'cost');
});

const QUOTE = {
  id: 'q1', rfq_no: 151768, inquiry_summary: 'False ceilings and gypsum cornice for a private villa in Khawaneej',
  inquiry_category: 'gypsum', supplier_label: 'Supplier A', amount: 25920, status: 'revealed',
  exclusions: 'electrical fittings painting of walls scaffolding above 4m', scope: null, warranty: null,
};

Deno.test('a question about the quote is answered from the quote line, and the threshold is compared', () => {
  const en = quoteAnswer('The quote excludes scaffolding above 4 m, but my ceilings are only 3.2 m — does that exclusion affect me?', [QUOTE], 'en');
  assert(en && en.basis === 'quote_field' && en.field === 'exclusions', JSON.stringify(en));
  assert(en.reply.includes('scaffolding above 4m'), en.reply);
  assert(en.reply.includes('3.2 m) is below the 4 m threshold') && en.reply.includes('does not apply'), en.reply);
  assert(!/\[company_faq/.test(en.reply));
  const ar = quoteAnswer('عرض السعر يستثني السقالات فوق 4 متر لكن ارتفاع الأسقف عندي 3.2 متر فقط، هل يؤثر هذا الاستثناء عليّ؟', [QUOTE], 'ar');
  assert(ar && ar.field === 'exclusions', JSON.stringify(ar));
  assert(ar.reply.includes('scaffolding above 4m') && ar.reply.includes('لا ينطبق'), ar.reply);
  // a named field the supplier left blank is answered as absent, never invented
  const w = quoteAnswer('what warranty does the quote give?', [QUOTE], 'en');
  assert(w && w.basis === 'quote_field_absent' && w.field === 'warranty' && /did not state warranty/.test(w.reply), JSON.stringify(w));
  // a question not about any quote falls through
  assertEquals(quoteAnswer('does a Dubai supplier cover Abu Dhabi as well?', [QUOTE], 'en'), null);
  assertEquals(quoteAnswer('how many quotes will I get', [], 'en'), null);
});

Deno.test('a passage sharing no substantive word with the question is off topic', () => {
  const q = 'the quote excludes scaffolding above 4 m but my ceilings are 3.2 m, does that exclusion matter';
  assert(!onTopic(q, 'Does a Dubai supplier cover Abu Dhabi as well? It depends on the supplier, and you do not have to guess.'));
  assert(onTopic(q, 'Exclusions are the items a supplier leaves out of a quotation, such as scaffolding.'));
  assert(onTopic('كم عدد الموردين', 'عدد الموردين الذين يستلمون طلبك محدود'));
  assertEquals(langOf('hello', 'ar'), 'ar');
  assertEquals(langOf('مرحبا'), 'ar');
  assert(/task #12/.test(notYet('en', 12, 'sales_engineer')) && /المهمة رقم 12/.test(notYet('ar', 12, 'sales_engineer')));
});
