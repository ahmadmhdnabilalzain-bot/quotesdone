// THE SEAT-EXAM SWEEP GRADES BY THE CANON, AND THE SEATS' KNOWLEDGE AGREES WITH IT. ceo, 3 Nov 2026 (qualification
// matrix gap #13, row E14). Offline: no token, no database, no model.
//
// MEASURED 3 Nov 2026 before this file existed: 22 served seat-pack entries (ceo, customer_support, accountant,
// it_engineer, marketing; English and Arabic) told the seats that a silent supplier's refund is "automatic", and four
// said banks show a refund in "5 to 10" days, while the signed Customer Terms v11 clause 5 say "no refund is automatic"
// (every refund is decided on the record by the CEO seat) and "seven (7) to fourteen (14) working days"; the seat cards
// compiled from them carried the same; COMPANY_CANON.md still described ten departments and the founder approving
// refunds; and exam item customer_support-exam-84 expected "5 to 10 business days". 45 contradictions on main, 0 here.
//
// WHAT FAILS IF THE CAUSE RETURNS
//   * a served seat-pack entry, a seat card, company.md, seats.md, COMPANY_CANON.md or an exam key states a company
//     figure or rule the canon contradicts (scripts/eval/seat_exam_canon.mjs);
//   * the sweep's code grader passes an answer that contradicts the canon, passes one that misses an expected fact or
//     states a figure the seat was never given, or lets a negated statement ("no refund is automatic") fail;
//   * the judge calibration set stops being 25 good + 25 bad over real items, or the calibration rule accepts a judge
//     that flags more than one good answer or gets fewer than 48 of 50 right.
//
//   node --test scripts/checks/the_seat_exam_sweep_grades_by_the_canon.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { canonFindings, unsupportedFigures, isMoneyOrTerms } from '../eval/seat_exam_canon.mjs';
import { auditKnowledge, allItems, gradeAnswer, calibration, finalVerdicts, scoreTable, CALIBRATION } from '../eval/seat_exam_sweep.mjs';

const claims = (t) => canonFindings(t).map((f) => f.claim);

test('the seats\' knowledge, cards, briefs, canon and exam keys contradict the canon nowhere', () => {
  assert.deepEqual(auditKnowledge().map((f) => `${f.where}: ${f.claim} "${f.text}"`), []);
});

test('a contradiction of the canon is found (the control for the test above)', () => {
  assert.ok(claims('If the supplier is still silent, the customer is refunded in full automatically.').includes('automatic_refund'));
  assert.ok(claims('If the supplier does not respond within 5 working days, everything you paid is refunded automatically.').includes('automatic_refund'));
  assert.ok(claims('Banks usually show the amount within 5 to 10 working days.').includes('bank_refund_days'));
  assert.ok(claims('The founder approves every refund.').includes('founder_decides_refunds'));
  assert.ok(claims('Yes, 5% VAT is added on top of the 3% reveal fee.').includes('quotesdone_vat_registered'));
  assert.ok(claims('Stripe costs are passed to the customer as a card surcharge.').includes('card_cost_passed_to_customer'));
  assert.ok(claims('QuotesDone runs on 10 departments.').includes('departments_exist'));
  assert.ok(claims('The supplier owes an AED 250 administrative fee.').some((c) => c.startsWith('company_facts.')));
});

test('a statement the canon makes is not a contradiction', () => {
  for (const ok of [
    'Every refund is decided by the CEO seat on the record; no refund is automatic.',
    'The customer does not need to ask: if the supplier stays silent, everything paid is refunded and banks take 7 to 14 working days to show it.',
    'QuotesDone is not VAT-registered, so no VAT is charged on the reveal fee.',
    'Applies only after QuotesDone is VAT registered.',
    'An earlier note ("free until 31 July 2027") was superseded; never quote a date.',
    "Stripe's guide says customers usually see the credit in about 5-10 business days, but QuotesDone gives the Terms' 7 to 14 working days.",
    'There are six seats and no departments.',
  ]) assert.deepEqual(claims(ok), [], ok);
});

test('the code grader: canon first, then facts, then figures; the judge only for what code cannot decide', () => {
  const item = { id: 't', expected_facts: ['7 to 14 working days', 'original payment method'], answer_must: [] };
  const ctx = 'Banks take 7 to 14 working days. A refund goes to the original payment method. The reveal fee is 3%.';
  assert.equal(gradeAnswer(item, 'It goes back to the original payment method; banks take 7 to 14 working days.', ctx).verdict, 'pass');
  const wrong = gradeAnswer(item, 'It goes back to the original payment method and is refunded automatically; banks take 7 to 14 working days.', ctx);
  assert.equal(wrong.verdict, 'fail'); assert.equal(wrong.reason, 'contradicts the canon');
  assert.equal(gradeAnswer(item, 'Back to the card she paid with, within a week or two.', ctx).verdict, 'judge');
  const invented = gradeAnswer(item, 'It goes back to the original payment method within 7 to 14 working days, less a 2% handling fee.', ctx);
  assert.equal(invented.verdict, 'judge'); assert.deepEqual(invented.unsupported, ['2%']);
  assert.equal(gradeAnswer(item, '', ctx).verdict, 'fail');
  assert.deepEqual(unsupportedFigures('The fee is 3% and the floor AED 1,000.', 'reveal fee 3%; liability AED 1,000'), []);
});

test('a judged miss counts only with a verdict, and a canon failure is never re-judged', () => {
  const code = [
    { id: 'a', seat: 'ceo', money_terms: true, verdict: 'pass', by: 'code' },
    { id: 'b', seat: 'ceo', money_terms: true, verdict: 'judge', by: 'code' },
    { id: 'c', seat: 'ceo', money_terms: false, verdict: 'judge', by: 'code' },
    { id: 'd', seat: 'ceo', money_terms: false, verdict: 'fail', by: 'code' },
  ];
  const f = finalVerdicts(code, { b: { pass: true, note: '' }, d: { pass: true, note: 'a judge cannot overturn code' } });
  assert.deepEqual(f.map((x) => [x.id, x.pass, x.by]), [['a', true, 'code'], ['b', true, 'judge'], ['c', false, 'unjudged'], ['d', false, 'code']]);
  const ceo = scoreTable(f).find((r) => r.seat === 'ceo');
  assert.equal(ceo.passed, 2); assert.equal(ceo.mt_passed, 2); assert.equal(ceo.meets_bar, false);
});

test('the judge calibration set and its rule', () => {
  const { cases } = JSON.parse(readFileSync(new URL(`../../${CALIBRATION}`, import.meta.url), 'utf8'));
  const items = new Map(allItems().map((i) => [i.id, i]));
  assert.equal(cases.filter((c) => c.label === 'good').length, 25);
  assert.equal(cases.filter((c) => c.label === 'bad').length, 25);
  for (const c of cases) {
    assert.ok(items.has(c.item), `${c.id}: ${c.item} is not an exam item`);
    assert.ok(c.label === 'good' ? c.planted === null : String(c.planted).length > 10, `${c.id}: a bad case names its planted error`);
  }
  assert.ok(cases.filter((c) => isMoneyOrTerms(items.get(c.item))).length >= 20, 'money/terms items are most of the set');
  const all = Object.fromEntries(cases.map((c) => [c.id, { pass: c.label === 'good' }]));
  assert.equal(calibration(cases, all).ok, true);
  const good = cases.filter((c) => c.label === 'good'), bad = cases.filter((c) => c.label === 'bad');
  assert.equal(calibration(cases, { ...all, [good[0].id]: { pass: false }, [good[1].id]: { pass: false } }).ok, false, 'two good answers flagged');
  assert.equal(calibration(cases, { ...all, [bad[0].id]: { pass: true }, [bad[1].id]: { pass: true }, [bad[2].id]: { pass: true } }).ok, false, '47 of 50');
  const { [good[0].id]: _drop, ...missing } = all;
  assert.equal(calibration(cases, missing).ok, false, 'an unanswered case');
});
