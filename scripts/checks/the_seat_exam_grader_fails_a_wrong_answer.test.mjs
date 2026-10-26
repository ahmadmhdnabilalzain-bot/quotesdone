// THE SEAT QUALIFICATION EXAM GRADER FAILS A WRONG ANSWER, AND EVERY EXAM ITEM CAN BE PASSED. it_engineer, instr 888,
// 28 Sep 2026. Offline: no token, no database.
//
// WHAT FAILS IF THE CAUSE RETURNS
//   * the grader (scripts/eval/seat_qualification_exam.mjs grade) passes an item whose entry is not in the top 5,
//     whose entry is found but the fact lies past the 1,200 characters the seat sees, whose only hit is the Arabic row,
//     or whose facts sit in a row that is NOT an expected entry. A grader that passes these reports a qualified seat
//     that holds nothing;
//   * an exam file under knowledge/exams/ carries an item that could never pass (an expected id not in the seat pack,
//     a fact not in the first 1,200 characters of the entry), has fewer than 40 items, or examines sales_engineer (on
//     hold) instead of one of the five seats.
//
//   node --test scripts/checks/the_seat_exam_grader_fails_a_wrong_answer.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { grade, validateExam, readExams, EXCERPT } from '../eval/seat_qualification_exam.mjs';
import { readPacks } from '../kb/verified_packs.mjs';

const REPO = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const item = { id: 't-1', q_en: 'When must the company register for VAT?', expected_entry_ids: ['accountant:vat'], expected_facts: ['AED 375,000'] };
const row = (id, excerpt) => ({ id, excerpt });
const good = row('accountant:vat', 'Mandatory VAT registration applies once taxable supplies exceed AED 375,000 in 12 months.');
const filler = (n) => Array.from({ length: n }, (_, i) => row(`accountant:other-${i}`, 'unrelated'));

test('a correct answer passes (the control: without it every refusal below proves nothing)', () => {
  assert.equal(grade(item, [good, ...filler(4)]).pass, true);
  assert.equal(grade(item, [...filler(4), good]).pass, true);
});

test('the expected entry at rank 6 fails', () => {
  const r = grade(item, [...filler(5), good]);
  assert.equal(r.pass, false); assert.equal(r.found, false);
});

test('the entry found but the fact missing from what the seat sees fails', () => {
  const r = grade(item, [row('accountant:vat', 'Registration is due at a threshold.'), ...filler(4)]);
  assert.equal(r.pass, false); assert.equal(r.found, true); assert.deepEqual(r.missing, ['AED 375,000']);
});

test('only the Arabic row of the expected entry fails (the facts are English)', () => {
  assert.equal(grade(item, [row('accountant:vat@ar', good.excerpt), ...filler(4)]).pass, false);
});

test('the fact present only in a row that is not an expected entry fails', () => {
  assert.equal(grade(item, [row('accountant:vat-history', good.excerpt), row('accountant:vat', 'no number here'), ...filler(3)]).pass, false);
});

test('every fact is required, not any one of them', () => {
  assert.equal(grade({ ...item, expected_facts: ['AED 375,000', '12 months', 'Federal Tax Authority'] }, [good, ...filler(4)]).pass, false);
});

test('an item that could never pass is refused by the validator', () => {
  const entries = new Map([['accountant:vat', { body_en: 'x'.repeat(EXCERPT) + ' AED 375,000' }]]);
  assert.match(validateExam({ items: [item] }, entries).join('\n'), /not in the first 1200 characters/);
  assert.match(validateExam({ items: [{ ...item, expected_entry_ids: ['accountant:nope'] }] }, entries).join('\n'), /not in the seat pack/);
  assert.match(validateExam({ items: [{ ...item, expected_facts: [] }] }, entries).join('\n'), /no expected facts/);
});

test('every committed exam is well-formed: five seats, 40+ items each, every item passable', () => {
  const packs = readPacks(join(REPO, 'knowledge'));
  const exams = readExams();
  assert.deepEqual(exams.map((x) => x.seat).sort(), ['accountant', 'ceo', 'customer_support', 'it_engineer', 'marketing']);
  for (const x of exams) {
    assert.ok(x.items.length >= 40, `${x.seat}: ${x.items.length} items`);
    const p = packs.find((q) => q.kind === 'seat' && q.code === x.seat);
    assert.deepEqual(validateExam(x, new Map(p.pack.entries.map((e) => [e.id, e]))), [], x.seat);
  }
});
