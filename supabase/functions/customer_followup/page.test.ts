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
  assertEquals(parseAnswer(new URLSearchParams('hired=yes&stars=4&comment=+good+')), { hired: 'yes', stars: 4, comment: 'good', contacted: null });
  assertEquals(parseAnswer(new URLSearchParams('hired=not_yet&stars=')), { hired: 'not_yet', stars: null, comment: null, contacted: null });
  assertEquals(parseAnswer(new URLSearchParams('hired=no&stars=9')), { hired: 'no', stars: null, comment: null, contacted: null });
  assertEquals(parseAnswer(new URLSearchParams('hired=maybe')), null);
  assertEquals(parseAnswer(new URLSearchParams('')), null);
});

Deno.test('the thank-you page is in the question language', () => {
  assert(messagePage('ar', 'thanks').includes('شكرًا لكم'));
  assert(messagePage('en', 'thanks').includes('Thank you'));
});

// THE CONTACT QUESTION (16 Nov 2026, AFTER_REVEAL; holes CUSTOMER.md items 1 and 2). Each fails on the page before this change.
Deno.test('working day 2 asks only whether the supplier contacted him, in plain words, in his language', () => {
  const en = questionPage({ ok: true, lang: 'en', stage: 'day_two_contact', company: 'ZZ DEMO Roofing', rfq_no: 42 }, TOK);
  assert(en.includes('name="contacted" value="yes"') && en.includes('name="contacted" value="no"') && en.includes('value="not_yet"'));
  assert(!en.includes('name="hired"'), 'working day 2 does not ask about hiring');
  assert(!en.includes('name="stars"'), 'working day 2 does not ask for a rating');
  assert(en.includes('Has ZZ DEMO Roofing contacted you yet'));
  const ar = questionPage({ ok: true, lang: 'ar', stage: 'day_two_contact', company: 'ZZ DEMO' }, TOK);
  assert(ar.includes('lang="ar" dir="rtl"') && ar.includes('هل تواصل معكم'));
});
Deno.test('working day 2: a yes stands, a no may be given again after the supplier says he called', () => {
  assert(!questionPage({ ok: true, lang: 'en', stage: 'day_two_contact', answered: true, contacted: 'yes' }, TOK).includes('<form'));
  assert(questionPage({ ok: true, lang: 'en', stage: 'day_two_contact', answered: true, contacted: 'no' }, TOK).includes('<form'));
});
Deno.test('day 3 asks the contact question FIRST, unless he already told us the supplier called', () => {
  const p = questionPage({ ok: true, lang: 'en', stage: 'day_three', company: 'ZZ DEMO' }, TOK);
  assert(p.indexOf('name="contacted"') > 0 && p.indexOf('name="contacted"') < p.indexOf('name="hired"'), 'contact comes before hiring');
  assert(p.indexOf('name="hired"') < p.indexOf('name="stars"'), 'hiring comes before the rating');
  assert(!questionPage({ ok: true, lang: 'en', stage: 'day_three', contact_known: true }, TOK).includes('name="contacted"'));
});
Deno.test('the contact word is parsed with the answer; working day 2 needs it and nothing else', () => {
  assertEquals(parseAnswer(new URLSearchParams('contacted=no&comment=never+called'), 'day_two_contact'),
    { hired: null, stars: null, comment: 'never called', contacted: 'no' });
  assertEquals(parseAnswer(new URLSearchParams('hired=yes'), 'day_two_contact'), null);
  assertEquals(parseAnswer(new URLSearchParams('contacted=no&hired=no&stars=1'), 'day_three'),
    { hired: 'no', stars: 1, comment: null, contacted: 'no' });
  assertEquals(parseAnswer(new URLSearchParams('contacted=maybe&hired=no'), 'day_three'),
    { hired: 'no', stars: null, comment: null, contacted: null });
});
Deno.test('the working-day-2 thank-you says what happens if he has not been contacted', () => {
  assert(messagePage('en', 'contact_thanks').includes('fifth working day'));
  assert(messagePage('ar', 'contact_thanks').includes('يوم العمل الخامس'));
});
