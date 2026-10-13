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
  assertEquals(moneyFiguresNotInBrief('A gypsum ceiling runs about AED 45 per square metre.', known), ['AED 45']);
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
  assertEquals(moneyFiguresNotInBrief('The reveal fee is 2.5% and a gypsum ceiling runs AED 45 per sqm.', known), ['AED 45', '2.5%']);
  assertEquals(moneyFiguresNotInBrief('Verification takes 3 working days; MDF is 18 mm thick.', known), [], 'counts and sizes are not money');
});

// prevented by: this test (review of #1330). A figure is its number AND its unit: a 5 stated as dirhams, a phone digit
// or an hour never lets "5%" through, and a range states both ends with the unit.
Deno.test('figure check compares the unit: AED 5 in the brief does not pass 5% in a reply', () => {
  const known = briefNumbers('Admin fee AED 5. Call +971 50 931 9355, Mon-Fri 9am-5pm. Gypsum ceiling: AED 35 to 70 per sqm. ضريبة 12٪.');
  assertEquals(moneyFiguresNotInBrief('The reveal fee is 5%.', known), ['5%']);
  assertEquals(moneyFiguresNotInBrief('The admin fee is AED 5.', known), []);
  assertEquals(moneyFiguresNotInBrief('Expect AED 35 to 70 per square metre, or 70 AED at the top.', known), []);
  assertEquals(moneyFiguresNotInBrief('من 35 إلى 70 درهم للمتر المربع.', known), []);
  assertEquals(moneyFiguresNotInBrief('Interest is 12 AED.', known), ['AED 12'], 'a percentage in the brief is not a dirham amount');
});

// prevented by: these tests (second review of #1330). Every way a fee or rate can be written is read as a figure.
const BRIEF2 = 'The reveal fee is 3.00%. Registration is AED 1,000 a year. Admin fee AED 500. Interest 12% per annum. Fine AED 2.5.';
Deno.test('figure check: "UAE dirhams" and the Arabic abbreviation د.إ are dirham units', () => {
  const k = briefNumbers(BRIEF2);
  assertEquals(moneyFiguresNotInBrief('Registration costs 1,000 UAE dirhams a year.', k), []);
  assertEquals(moneyFiguresNotInBrief('Registration costs 2,000 UAE dirhams a year.', k), ['AED 2000']);
  assertEquals(moneyFiguresNotInBrief('رسوم إدارية قدرها 500 د.إ.', k), []);
  assertEquals(moneyFiguresNotInBrief('رسوم إدارية قدرها 700 د.إ.', k), ['AED 700']);
});
Deno.test('figure check: the Arabic decimal mark ٫ and Persian digits are read', () => {
  const k = briefNumbers(BRIEF2);
  assertEquals(moneyFiguresNotInBrief('غرامة ٢٫٥ درهم.', k), []);
  assertEquals(moneyFiguresNotInBrief('غرامة ۳٫۵ درهم.', k), ['AED 3.5']);
  assertEquals(moneyFiguresNotInBrief('رسوم الكشف ۳٪.', k), []);
  assertEquals(moneyFiguresNotInBrief('رسوم الكشف ۵٪.', k), ['5%']);
});
Deno.test('figure check: numbers in words and unit-less fees next to fee words are checked', () => {
  const k = briefNumbers(BRIEF2);
  assertEquals(moneyFiguresNotInBrief('The reveal fee is three percent.', k), []);
  assertEquals(moneyFiguresNotInBrief('The reveal fee is five per cent.', k), ['5%']);
  assertEquals(moneyFiguresNotInBrief('رسوم الكشف خمسة بالمئة.', k), ['5%']);
  assertEquals(moneyFiguresNotInBrief('رسوم الكشف ثلاثة في المئة.', k), []);
  assertEquals(moneyFiguresNotInBrief('The reveal fee is 5 on the quote you choose.', k), ['a fee of 5']);
  assertEquals(moneyFiguresNotInBrief('The admin fee is 500.', k), []);
});
// prevented by: these tests (independent review of #1330). Tens, hundreds and thousands in words, EN and AR, and the
// subscription / price / cost words, are all read as figures.
Deno.test('figure check: tens, hundreds and thousands written in words are read', () => {
  const k = briefNumbers(BRIEF2);
  assertEquals(moneyFiguresNotInBrief('The fee is thirty percent.', k), ['30%']);
  assertEquals(moneyFiguresNotInBrief('It costs fifty dirhams.', k), ['AED 50']);
  assertEquals(moneyFiguresNotInBrief('Registration is two thousand dirhams a year.', k), ['AED 2000']);
  assertEquals(moneyFiguresNotInBrief('Registration is one thousand dirhams a year.', k), []);
  assertEquals(moneyFiguresNotInBrief('The admin fee is five hundred dirhams.', k), []);
  assertEquals(moneyFiguresNotInBrief('Registration is two thousand five hundred dirhams.', k), ['AED 2500']);
  assertEquals(moneyFiguresNotInBrief('رسوم التسجيل ألف درهم سنويًا.', k), []);
  assertEquals(moneyFiguresNotInBrief('رسوم التسجيل ألفا درهم.', k).length, 0, 'an unknown spelling is not invented into a figure');
  assertEquals(moneyFiguresNotInBrief('الرسوم ثلاثين بالمئة.', k), ['30%']);
  assertEquals(moneyFiguresNotInBrief('الفائدة اثنا عشر بالمئة سنويًا.', k), []);
  assertEquals(moneyFiguresNotInBrief('رسوم إدارية قدرها خمسمائة درهم.', k), []);
  assertEquals(moneyFiguresNotInBrief('رسوم قدرها ثلاثة آلاف درهم.', k), ['AED 3000']);
  assertEquals(moneyFiguresNotInBrief('غرامة خمسة وعشرون درهمًا.', k), ['AED 25']);
  assertEquals(moneyFiguresNotInBrief('رسوم قدرها ألفين درهم.', k), ['AED 2000']);
  assertEquals(moneyFiguresNotInBrief('رسوم قدرها مئة درهم.', k), ['AED 100']);
  assertEquals(moneyFiguresNotInBrief('The cost is one million two hundred thousand dirhams.', k), ['AED 1200000']);
  assertEquals(moneyFiguresNotInBrief('التكلفة مليونان درهم.', k), ['AED 2000000']);
});
Deno.test('figure check: subscription, price and cost words carry a unit-less fee figure', () => {
  const k = briefNumbers(BRIEF2);
  assertEquals(moneyFiguresNotInBrief('The subscription is 1,200 a year.', k), ['a fee of 1200']);
  assertEquals(moneyFiguresNotInBrief('The subscription is 1,000 a year.', k), []);
  assertEquals(moneyFiguresNotInBrief('The price is 90 per sqm.', k), ['a fee of 90']);
  assertEquals(moneyFiguresNotInBrief('قيمة الاشتراك 1,200 سنويًا.', k), ['a fee of 1200']);
  assertEquals(moneyFiguresNotInBrief('تكلفة 750 للمتر.', k), ['a fee of 750']);
});

// prevented by: this test (zero tolerance, 12 Oct 2026). A stated reveal fee also says no card fee and no VAT.
Deno.test('a stated reveal fee must say no card fee and no VAT; a reply without the fee is not asked to', async () => {
  const { revealFeeIncomplete } = await import('./company_brief.ts');
  assertEquals(revealFeeIncomplete('The reveal fee is 3% of the quote. No card fee is added and no VAT is charged on it.'), []);
  assertEquals(revealFeeIncomplete('The reveal fee is 3% of the quote.').length, 2);
  assertEquals(revealFeeIncomplete('The reveal fee is 3%. No card fee is added.'), ['it states the 3% fee without saying, in so many words, that no VAT is charged on it']);
  // the bare words are not enough: the card and the VAT must each be NEGATED
  assertEquals(revealFeeIncomplete('The reveal fee is 3%. You can pay by card. VAT rules apply in the UAE.').length, 2);
  assertEquals(revealFeeIncomplete('The fee is 3% and it is not charged a card fee; there is no VAT on the fee.'), []);
  assertEquals(revealFeeIncomplete('Pay 3% without card fees. No VAT is charged on it.'), []);
  assertEquals(revealFeeIncomplete('رسوم 3٪ بدون رسوم بطاقة، ولا ضريبة قيمة مضافة على الرسوم.'), []);
  assertEquals(revealFeeIncomplete('رسوم 3٪ وتدفع بالبطاقة، وتطبق الضريبة.').length, 2);
  // ANY 3% FEE statement triggers it, with or without the word "reveal"
  assertEquals(revealFeeIncomplete('Our fee is 3% of the chosen quote.').length, 2);
  assertEquals(revealFeeIncomplete('تدفعون رسومًا قدرها ثلاثة بالمئة من قيمة العرض المختار.').length, 2);
  // ...but not a quote's own 3% terms, a 3% slope, or the non-response charge (review of #1356)
  assertEquals(revealFeeIncomplete('The supplier offers a 3% discount on the quote.'), []);
  assertEquals(revealFeeIncomplete('Their quote holds a 3% retention charge until handover.'), []);
  assertEquals(revealFeeIncomplete('Lay the screed to a 3% slope toward the drain.'), []);
  assertEquals(revealFeeIncomplete('A supplier that ignores a paid reveal owes the 3% fee refunded to the customer, an AED 500 admin fee and 12% interest.'), []);
  assertEquals(revealFeeIncomplete('خصم 3٪ على عرض السعر من المورد.'), []);
  // whole words only: "ميل" inside العميل does not exempt a reveal-fee sentence; a refund is no exemption (review of #1356)
  assertEquals(revealFeeIncomplete('رسوم الكشف 3% يدفعها العميل.').length, 2);
  assertEquals(revealFeeIncomplete('The 3% reveal fee is refunded if the supplier does not respond.').length, 2);
  assertEquals(revealFeeIncomplete('تطبيق ميل بنسبة 3٪ للتصريف ضمن رسوم العمل.'), [], 'a 3% slope (ميل) is still exempt as a whole word');
  // the negation must be OF the card fee / the VAT, not anywhere in the sentence
  assertEquals(revealFeeIncomplete('The reveal fee is 3%. The VAT certificate is not required. Never share your card details.').length, 2);
  assertEquals(revealFeeIncomplete('رسوم الكشف 3٪ من قيمة العرض، ولا يُضاف أي مبلغ عند الدفع بالبطاقة، ولا تُفرض ضريبة القيمة المضافة على رسوم الكشف.'), []);
  assertEquals(revealFeeIncomplete('رسوم الكشف ثلاثة بالمئة من قيمة العرض.').length, 2);
  assertEquals(revealFeeIncomplete('Verification takes up to 3 working days.'), []);
});

Deno.test('figure check: "AED 1,000 - 5 working days" is not a range; a range with units on both sides is', () => {
  const k = briefNumbers(BRIEF2);
  assertEquals(moneyFiguresNotInBrief('Registration is AED 1,000 - 5 working days to verify.', k), []);
  assertEquals(moneyFiguresNotInBrief('Expect AED 1,000 - 2,000.', k), ['AED 2000']);
});

Deno.test('sentences come off the front of the stream whole, the unfinished tail stays', () => {
  const { done, rest } = takeSentences('The fee is 3%. Comparing is free! Suppliers pa');
  assertEquals(done, ['The fee is 3%. ', 'Comparing is free! ']);
  assertEquals(rest, 'Suppliers pa');
  assertEquals(takeSentences('نعم، هويتك مخفية؟ ثم').done, ['نعم، هويتك مخفية؟ ']);
});

// prevented by: this test (ruling 1207, 13 Oct 2026). A supplier's quotation is shown as stated: its discount, "VAT
// included", "+5% VAT" or card surcharge is never contradicted, and the no-card-fee / no-VAT line is never forced onto
// it. The line still belongs to OUR 3% fee, computed on the final quoted price.
Deno.test('a supplier quotation stands as stated; only our 3% fee carries the no card fee / no VAT line', async () => {
  const { revealFeeIncomplete } = await import('./company_brief.ts');
  for (const s of [
    'The supplier quoted AED 2,000, after discount AED 1,700, VAT included.',
    'The supplier\'s price is AED 1,700 +5% VAT.',
    'The supplier\'s quotation adds a card surcharge for card payments.',
    'عرض المورد 2,000 درهم، وبعد الخصم 1,700 درهم شاملة ضريبة القيمة المضافة.',
  ]) {
    assertEquals(policyProblems(s), [], s);
    assertEquals(revealFeeIncomplete(s), [], s);
  }
  const both = 'The supplier quoted AED 1,700 +5% VAT; QuotesDone is not responsible for the quotation details. Our 3% reveal fee is 3% of AED 1,700, with no card fee and no VAT.';
  assertEquals([policyProblems(both), revealFeeIncomplete(both)], [[], []]);
  // our own fee is never exempt: VAT on the reveal fee is still caught, and a bare 3% fee still needs the line
  assert(policyProblems('VAT is added to the reveal fee.').length === 1);
  // a bare fee word is OUR fee unless it is tied to the supplier (review of #1356)
  for (const s of ['The service fee includes VAT, like the quoted price.', 'رسوم المنصة تشمل ضريبة القيمة المضافة على السعر']) assertEquals(policyProblems(s).length, 1, s);
  assertEquals(policyProblems('The supplier\'s fee includes VAT, as quoted.'), []);
  assertEquals(policyProblems('The supplier charges a 5% installation fee plus VAT.'), []);
  // a supplier or quote mentioned mid-sentence shields nothing, and a "no" in another clause does not deny the claim
  for (const s of ['Suppliers pay no fee and you pay a fee with VAT.', 'To unlock a quote you pay a fee plus VAT.', 'When the supplier accepts, you pay a card fee.'])
    assert(policyProblems(s).length >= 1, s);
  assertEquals(policyProblems('يفرض المورد رسوم تركيب 5% بالإضافة إلى ضريبة القيمة المضافة.'), []);
  assertEquals(policyProblems('رسوم المورد تشمل ضريبة القيمة المضافة حسب عرض السعر.'), []);
  // عرض meaning "show" does not make a sentence about the supplier
  assertEquals(policyProblems('سنعرض لك ضريبة القيمة المضافة على الرسوم.').length, 1);
  assertEquals(revealFeeIncomplete('The supplier quoted AED 1,700. Our 3% reveal fee is AED 51.').length, 2);
});
Deno.test('ruling 1208: a fee taken before VAT is policy; VAT on our fee is still caught', () => {
  assertEquals(policyProblems('Our 3% fee is taken on the supplier\'s final price before VAT, after any discount.'), []);
  assertEquals(policyProblems('Supplier B adds VAT of AED 85 to its price, as it stated.'), []);
  assertEquals(policyProblems('VAT is added to the reveal fee.').length, 1);
  // the fee-basis phrase exempts only itself: any other VAT claim in the sentence is still caught
  for (const s of ['Our fee is taken before VAT and VAT is added to it.', 'Our 3% fee is excluding VAT, but VAT is charged on the reveal fee.'])
    assertEquals(policyProblems(s).length, 1, s);
});

// prevented by: this test (sales_engineer, 13 Oct 2026, review of #1382). Adding the knowledge block to the brief
// must not change which figures the check accepts: exactly the set main accepted before the block was added.
Deno.test('the knowledge block adds no accepted figure', async () => {
  const { BRIEF_TEXT } = await import('./brief.generated.ts');
  const { briefNumbers, composeBrief, figureSource } = await import('./company_brief.ts');
  const base = composeBrief({ company: 'REVEAL FEE: 3.00% of the quotation. VAT is not charged.', facts: '', faqs: [], lang: 'en', blocks: ['PRICE GUIDE: painting AED 8-15 per m2'] });
  const withBlock = composeBrief({ company: 'REVEAL FEE: 3.00% of the quotation. VAT is not charged.', facts: '', faqs: [], lang: 'en', blocks: ['PRICE GUIDE: painting AED 8-15 per m2', BRIEF_TEXT] });
  const a = [...briefNumbers(base)].sort(), b = [...briefNumbers(figureSource(withBlock))].sort();
  if (JSON.stringify(a) !== JSON.stringify(b)) throw new Error(`accepted figures changed: ${JSON.stringify(b.filter((x) => !a.includes(x)))}`);
});
