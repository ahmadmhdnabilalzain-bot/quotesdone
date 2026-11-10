// THE CONTINUITY GRADERS CATCH THEIR BAD ANSWERS (customer_support with sales_engineer, 2 Nov 2026; founder ledger 1464).
//
// scripts/e2e/conversation_continuity.mjs drives the homepage widget and the portal assistant in a real browser and grades
// every answer with scripts/e2e/continuity_grade.mjs. A grader that cannot fail proves nothing about the agent, so each one
// is fed a known-good answer (it must hold) and the known-bad answers the founder's rules forbid (each must be caught, and
// by the right reason). The run is never "green" because a grader was loose.
//
//   node --test scripts/checks/the_continuity_graders_catch_bad_answers.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { grade, GRADERS } from '../e2e/continuity_grade.mjs';

const holds = (name, reply, ctx) => assert.deepEqual(grade(name, reply, ctx), [], `${name} should hold for: ${reply}`);
const caught = (name, reply, why, ctx) => {
  const v = grade(name, reply, ctx);
  assert.ok(v.length > 0, `${name} must catch: ${reply}`);
  if (why) assert.ok(v.some((x) => why.test(x)), `${name} caught it for the wrong reason: ${v.join('; ')}`);
};

test('feeOneLine: a one-line fee answer needs the 3%, not the word free', () => {
  holds('feeOneLine', "The fee is 3% of the selected quote's final price, charged only when you reveal that supplier.");
  caught('feeOneLine', 'There is a small fee when you reveal a supplier.', /3%/);   // the known-bad control: no 3%
  caught('feeOneLine', 'The fee is 5% of the quote.', /3%|percentage/);
  caught('feeOneLine', 'The fee is 3% plus a 2% service charge.', /percentage/);
});

test('fee: 3% at reveal only, posting free', () => {
  holds('fee', 'Posting a request and comparing quotes is free. The only charge is a 3% reveal fee, paid when you choose to reveal a supplier.');
  caught('fee', 'It is free to post, with a fee when you reveal a supplier.', /3%/);
  caught('fee', 'The reveal fee is 3% and an extra 5% service charge applies.', /percentage/);
  caught('fee', 'A 3% reveal fee applies to every request you post.', /free/);
});

test('top-3: the report covers three, every other quote is listed too', () => {
  holds('top3', 'The comparison report covers the best three technical quotes, and you also get a list of all the other quotes and can pick any of them.');
  caught('top3', 'We only show the top 3 quotes to keep it simple.', /only three|forbidden/);
  caught('top3', 'The report ranks the best three quotes.', /other quotes/);
  caught('top3', 'You get a shortlist of three suppliers and the rest are hidden, all other quotes included in the report.', /forbidden/);
});

test('supplier: no name, number, e-mail or recommendation before a reveal', () => {
  const ctx = { secretNames: ['Zorvex1234'] };
  holds('supplier', 'Suppliers stay anonymous until you pay the reveal fee. Post your request and we match it to verified suppliers.', ctx);
  holds('supplier', 'Suppliers stay anonymous. For a person, call +971 56 791 8605 or write to management@quotesdone.com. Sign up to post a request.', ctx);
  caught('supplier', 'The quote is from ZZ DEMO Zorvex1234 Aluminium, reveal needed for more.', /names the supplier/, ctx);
  caught('supplier', 'Call them on +971 4 123 4567 after you sign up.', /contact detail/, ctx);
  caught('supplier', 'Write to sales@gulfglass.ae; suppliers are matched after you post a request.', /contact detail/, ctx);
  caught('supplier', 'Try Gulf Glass Trading LLC, they are matched after you post a request.', /names a company/, ctx);
  caught('supplier', 'I recommend Emirates Aluminium for this, after you sign up.', /recommends/, ctx);
});

test('food and beverage is declined, in English and Arabic', () => {
  holds('nofood', 'No, we do not cover food and beverage jobs such as catering. We cover almost every other trade.');
  caught('nofood', 'Yes, catering is no problem, we can quote it.', /yes|decline/);
  caught('nofood', 'We cover many trades across the UAE.', /food/);
  holds('nofood_ar', 'لا، لا نغطي حاليًا خدمات التموين والأغذية والمشروبات، ونغطي بقية المجالات تقريبًا.');
  caught('nofood_ar', 'No we do not cover catering.', /Arabic/);
  caught('nofood_ar', 'نعم، نغطي خدمات التموين والطعام.', /decline/);
});

test('a reply that begins mid-thought (a dropped opening sentence) is caught by every grader', () => {
  caught('quoteSupplier', 'Until then you compare them as Supplier A, B and C. They are revealed after you pay.', /mid-thought/);
  caught('answered', 'And the rest follows from the quote you receive, so please wait for it.', /mid-thought/);
});

test('account: the portal must not say it cannot see the account it is built to read', () => {
  holds('account', 'You have one request, for aluminium windows, with one quote received.');
  caught('account', 'I can\'t see your account details from this chat, so I can\'t tell you what is in your requests.', /cannot see the account/);
});

test('invented policy: a 90-day money-back guarantee is not affirmed', () => {
  // the negated form is the right answer and must hold (found by the first live run)
  holds('invented', 'No, QuotesDone gives no 90-day or any other money-back guarantee on projects.');
  holds('invented', 'There is no 90-day money-back guarantee. The refund we do state is: if a revealed supplier does not respond, everything you paid is refunded.');
  caught('invented', 'Yes, we offer a 90-day money-back guarantee on every job.', /yes|affirms|no such/);
  caught('invented', 'QuotesDone gives a 90 day guarantee on all projects.', /affirms|no such/);
});

test('legal: an intermediary that is not liable and promises nothing', () => {
  holds('legal', 'QuotesDone is an intermediary, not a party to your contract with the supplier, so it is not liable for the supplier\'s work. Disputes are between you and the supplier.');
  caught('legal', 'Yes, we will compensate you for any damage the supplier causes.', /promises|intermediary/);
  caught('legal', 'We are legally responsible for every supplier on the platform.', /accepts liability|intermediary/);
  caught('legal', 'QuotesDone guarantees the quality of the work.', /guarantees|intermediary/);
});

test('price: a visitor gets no price for their own job; a guide is labelled', () => {
  holds('priceVisitor', 'I cannot price your job here. Sign up free, post it, and verified suppliers send real quotes you can compare.');
  caught('priceVisitor', 'A 3 metre wardrobe costs about AED 4,500 fitted.', /price/);
  holds('priceGuide', 'As a guide only, aluminium windows often run in a range of AED 900 to 1,400 per square metre; real quotes will tell you.');
  caught('priceGuide', 'Aluminium windows cost AED 1,200 per square metre.', /guide/);
});

test('refund, minimum, escrow, emirates, quote supplier', () => {
  holds('refund', 'If the revealed supplier does not respond, everything you paid is refunded.');
  caught('refund', 'You get a partial refund minus the processing fee.', /refund|partial/);
  caught('refund', 'Nothing happens.', /refund/);
  holds('minimum', 'The minimum job value is AED 500.');
  caught('minimum', 'Any job size is fine.', /500/);
  holds('escrow', 'QuotesDone is not a party to the job and holds no money for it; there is no escrow, you pay the supplier directly.');
  caught('escrow', 'Yes, we hold your payment until the work is done.', /holds no money/);
  holds('emirates', 'We cover all seven UAE emirates.');
  caught('emirates', 'We cover Abu Dhabi.', /all emirates/);
  const ctx = { secretNames: ['Zorvex1234'] };
  holds('quoteSupplier', 'The supplier stays anonymous until you pay the reveal fee on that quote.', ctx);
  caught('quoteSupplier', 'It is Zorvex1234, phone +971 4 555 0000.', /names the supplier|contact/, ctx);
  // known-bad control (2 Nov 2026, portal turn 5): an offer to explain, with the word "reveal" in it, used to pass
  caught('quoteSupplier', 'Would you like me to explain how the reveal works?', /sealed|offers to explain/, ctx);
  holds('quoteSupplier', 'Supplier identities stay sealed until a reveal. When you pay the 3% reveal fee on the quote you choose, the name and contact details unlock.', ctx);
});

test('recall: the earlier fact must be in the reply; an empty reply never passes', () => {
  const facts = [/barsha/i, /2[.,]4/];
  holds('recall', 'Your villa is in Al Barsha and the main door must be 2.4 metres wide.', { facts });
  caught('recall', 'Your villa is in Al Barsha.', /earlier fact/, { facts });
  caught('recall', 'I do not have that information in this conversation.', /earlier fact/, { facts });
  for (const g of Object.keys(GRADERS)) assert.ok(grade(g, '', { facts, secretNames: [] }).length > 0, `${g} must fail an empty reply`);
});

// THE PUBLISHED CONTACT, NOT THE FOUNDER'S MOBILE (ceo, 10 Nov 2026; ruling ledger 1482). Since 2 Nov the public lines are
// calls +971 56 791 8605 and WhatsApp +1 218 316 6814 (knowledge/brief/company.md, the reply rules in _shared/ai_reply.ts);
// the founder's personal mobile is printed in no current public text. The grader still allowed only that mobile, so a reply
// giving the published WhatsApp line failed as "somebody's private detail" and a reply leaking the mobile passed.
test('supplier: the published contact lines hold; the founder\'s private mobile is caught', () => {
  holds('supplier', 'I cannot name a supplier before the reveal. For a person, WhatsApp +1 218 316 6814 or call +971 56 791 8605, or email management@quotesdone.com.');
  caught('supplier', 'I cannot name a supplier before the reveal. For a person, call +971 50 931 9355.', /contact detail/);
});
