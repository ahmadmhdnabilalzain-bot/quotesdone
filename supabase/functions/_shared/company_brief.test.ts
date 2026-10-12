// The company brief and the figure check (company_brief.ts). No network.
import { assert, assertEquals } from 'jsr:@std/assert';
import { briefNumbers, companyBrief, composeBrief, FAQ_CAP, moneyFiguresNotInBrief, policyProblems, takeSentences } from './company_brief.ts';

// prevented by: this test (review of #1330). A false policy sentence with no number goes back to the model too.
Deno.test('policy claims: an affirmed card fee, VAT on the fee, a refund promise or a liability admission is named; a denial passes', () => {
  for (const bad of ['A card fee is added at checkout.', 'VAT applies on the reveal fee.', 'We will refund you in full today.',
    'QuotesDone is liable for the quality of the work.', 'تُضاف رسوم البطاقة عند الدفع.', 'تُفرض ضريبة القيمة المضافة على رسوم الكشف.'])
    assertEquals(policyProblems(bad).length, 1, bad);
  for (const ok of ['No card fee is ever added.', 'There is no VAT on the reveal fee.', 'If the supplier does not respond, you are refunded everything you paid.',
    'لا تُضاف رسوم على الدفع بالبطاقة.', 'Comparing quotes is free.'])
    assertEquals(policyProblems(ok), [], ok);
});

// prevented by: this test. The published price guide (fn_price_brief) rides in the brief, so its ranges pass the
// figure check and an unpublished price still does not.
Deno.test('the published price guide is in the brief and its figures pass; an unpublished price does not', async () => {
  const rpc = (fn: string) => Promise.resolve({ data: fn === 'fn_price_brief' ? '## PUBLISHED PRICE GUIDE\n- gypsum: Gypsum false ceiling: AED 35 to 70 per sqm' : { block: 'CO' }, error: null });
  const b = await companyBrief(rpc, [], 'FACTS P', 'en', [], 10);
  assert(b.includes('Gypsum false ceiling: AED 35 to 70'));
  const known = briefNumbers(b);
  assertEquals(moneyFiguresNotInBrief('A gypsum ceiling runs about AED 35 to 70 per square metre.', known), []);
  assertEquals(moneyFiguresNotInBrief('A gypsum ceiling runs about AED 45 per square metre.', known), ['45']);
});

Deno.test('the brief cache is keyed on content: same-length facts never share a brief', async () => {
  const rpc = () => Promise.resolve({ data: { block: 'CO' }, error: null });
  const a = await companyBrief(rpc, [], 'FACTS A', 'en', [], 1);
  const b = await companyBrief(rpc, [], 'FACTS B', 'en', [], 2);
  assert(a.includes('FACTS A') && b.includes('FACTS B'));
});

const COMPANY = 'REVEAL FEE: the CUSTOMER pays 3.00% of the selected quotation value. Supplier registration is free for the first 1000, then AED 1000/year. AED 500 administrative fee; 12% per annum.';

Deno.test('the brief carries the company block, the facts, the FAQ in the asker language only, and any extra cached block', () => {
  const b = composeBrief({ company: COMPANY, facts: 'FACTS: minimum job AED 500.', lang: 'ar', blocks: ['## UAE REGULATIONS DIGEST\nCivil Defence code.'],
    faqs: [{ id: 2, question: 'كم الرسوم؟', answer: '3% فقط', language: 'ar' }, { id: 1, question: 'Fee?', answer: '3%', language: 'en' }] });
  assert(b.includes(COMPANY) && b.includes('minimum job AED 500') && b.includes('كم الرسوم؟') && !b.includes('Fee?'));
  assert(b.indexOf('PUBLISHED FAQ') < b.indexOf('UAE REGULATIONS DIGEST'), 'a second knowledge block follows the FAQ in the same cached prefix');
});

Deno.test('the FAQ section stays under its cap', () => {
  const faqs = Array.from({ length: 400 }, (_, i) => ({ id: i, question: 'Q' + i + ' '.repeat(40), answer: 'A'.repeat(200), language: 'en' }));
  const b = composeBrief({ company: '', facts: '', faqs, lang: 'en' });
  assert(b.length < FAQ_CAP + 500);
});

Deno.test('figure check: a fee or rate the brief states passes; any other money figure is named', () => {
  const known = briefNumbers(COMPANY);
  assertEquals(moneyFiguresNotInBrief('The reveal fee is 3% of the quote. Registration is AED 1,000 a year after the first 1000.', known), []);
  assertEquals(moneyFiguresNotInBrief('رسوم الكشف ٣٪ فقط، والغرامة 500 درهم.', known), []);
  assertEquals(moneyFiguresNotInBrief('The reveal fee is 2.5% and a gypsum ceiling runs AED 45 per sqm.', known), ['2.5', '45']);
  assertEquals(moneyFiguresNotInBrief('Verification takes 3 working days; MDF is 18 mm thick.', known), [], 'counts and sizes are not money');
});

Deno.test('sentences come off the front of the stream whole, the unfinished tail stays', () => {
  const { done, rest } = takeSentences('The fee is 3%. Comparing is free! Suppliers pa');
  assertEquals(done, ['The fee is 3%. ', 'Comparing is free! ']);
  assertEquals(rest, 'Suppliers pa');
  assertEquals(takeSentences('نعم، هويتك مخفية؟ ثم').done, ['نعم، هويتك مخفية؟ ']);
});
