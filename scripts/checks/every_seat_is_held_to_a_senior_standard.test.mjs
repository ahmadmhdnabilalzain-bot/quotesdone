// EVERY SEAT IS HELD TO A SENIOR STANDARD (ceo, 19 Oct 2026, founder ledger 1003 and 894). Offline: reads the
// repository only. The live measurement is scripts/eval/seat_senior_audit.mjs.
//
// Fails when: a seat has no standard; a checklist item names an entry the seat pack does not hold, or no exam item;
// an exam item tests a checklist item the standard does not list, or has no reworded question and no answer_must (the
// LLM-on exam asks the reworded question and the reader grades against answer_must); a judged file grades an item
// that is not in the exam; or the verdict calls a seat senior below the bar.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { validateStandard, verdict } from '../eval/seat_senior_audit.mjs';

const REPO = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const read = (p) => JSON.parse(readFileSync(join(REPO, p), 'utf8'));
const SEATS = ['ceo', 'customer_support', 'sales_engineer', 'accountant', 'it_engineer', 'marketing'];

for (const seat of SEATS) {
  test(`${seat}: a senior standard whose every item is backed and examined`, () => {
    assert.ok(existsSync(join(REPO, `knowledge/standards/${seat}.json`)), `knowledge/standards/${seat}.json is missing`);
    const std = read(`knowledge/standards/${seat}.json`);
    const pack = read(`knowledge/seats/${seat}.json`);
    const exam = read(`knowledge/exams/${seat}.json`);
    assert.equal(std.seat, seat);
    assert.deepEqual(validateStandard(std, new Set(pack.entries.map((e) => e.id)), new Set(exam.items.map((i) => i.id))), []);
    const cl = new Set(std.checklist.map((c) => c.id));
    const bad = exam.items.filter((i) => !cl.has(i.checklist) || !i.q_reworded?.trim() || !i.answer_must?.length).map((i) => i.id);
    assert.deepEqual(bad, [], 'exam items without a listed checklist id, a reworded question or answer_must');
    for (const c of std.contributions) assert.ok(['live', 'partial', 'missing'].includes(c.status), `${c.id}: status ${c.status}`);
    const j = `knowledge/exams/judged/${seat}.json`;
    if (existsSync(join(REPO, j))) {
      const ids = new Set(exam.items.map((i) => i.id));
      const judged = read(j);
      assert.deepEqual(judged.items.filter((i) => !ids.has(i.id) || !['pass', 'fail'].includes(i.verdict)).map((i) => i.id), []);
    }
  });
}

test('the verdict never calls a seat senior below the bar', () => {
  const full = { checklist_backed: 1, checklist_examined: 1, answered: 0.95, contributions_live: 1 };
  assert.equal(verdict(full).level, 'senior');
  assert.notEqual(verdict({ ...full, answered: 0.949 }).level, 'senior');
  assert.notEqual(verdict({ ...full, answered: null }).level, 'senior');
  assert.notEqual(verdict({ ...full, checklist_backed: 0.99 }).level, 'senior');
  assert.notEqual(verdict({ ...full, contributions_live: 0.9 }).level, 'senior');
});
