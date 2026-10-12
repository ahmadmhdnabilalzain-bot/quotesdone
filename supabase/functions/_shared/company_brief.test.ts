// The company brief and the figure check (company_brief.ts). No network.
import { assert, assertEquals } from 'jsr:@std/assert';
import { briefNumbers, composeBrief, FAQ_CAP, moneyFiguresNotInBrief, takeSentences } from './company_brief.ts';

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
