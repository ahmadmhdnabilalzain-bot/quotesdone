// The follow-up page: GET never records, the form answers only yes/no/not_yet, and the page speaks the language
// the question was asked in. `deno test supabase/functions/customer_followup/page.test.ts`
import { assert, assertEquals } from 'jsr:@std/assert';
import { messagePage, parseAnswer, questionPage } from './page.ts';

const TOK = '11111111-2222-4333-8444-555555555555';

Deno.test('the question is a form that POSTs; showing it records nothing', () => {
  const p = questionPage({ ok: true, lang: 'en', company: 'ZZ DEMO Paints <b>', rfq_no: 42, trade: 'Painting' }, TOK);
  assert(p.includes('method="post"'));
  assert(p.includes(`action="?t=${TOK}"`));
  assert(p.includes('ZZ DEMO Paints &lt;b&gt;'), 'the company name is escaped');
  assert(p.includes('RFQ-42'));
});

Deno.test('an Arabic question is an Arabic, right-to-left page', () => {
  const p = questionPage({ ok: true, lang: 'ar', company: 'ZZ DEMO', rfq_no: 7 }, TOK);
  assert(p.includes('lang="ar" dir="rtl"'));
  assert(p.includes('هل تعاقدتم مع'));
});

Deno.test('a definite earlier answer shows "already answered", not the form', () => {
  const p = questionPage({ ok: true, lang: 'en', answered: true, hired: 'no' }, TOK);
  assert(!p.includes('<form'));
  assert(p.includes('already answered'));
});

Deno.test('the answer is only yes, no or not_yet; stars only 1-5', () => {
  assertEquals(parseAnswer(new URLSearchParams('hired=yes&stars=4&comment=+good+')), { hired: 'yes', stars: 4, comment: 'good' });
  assertEquals(parseAnswer(new URLSearchParams('hired=not_yet&stars=')), { hired: 'not_yet', stars: null, comment: null });
  assertEquals(parseAnswer(new URLSearchParams('hired=no&stars=9')), { hired: 'no', stars: null, comment: null });
  assertEquals(parseAnswer(new URLSearchParams('hired=maybe')), null);
  assertEquals(parseAnswer(new URLSearchParams('')), null);
});

Deno.test('the thank-you page is in the question language', () => {
  assert(messagePage('ar', 'thanks').includes('شكرًا لكم'));
  assert(messagePage('en', 'thanks').includes('Thank you'));
});
