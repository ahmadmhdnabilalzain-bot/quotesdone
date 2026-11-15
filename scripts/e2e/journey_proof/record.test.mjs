// The dossier's own judgements: right suppliers asked, cost by step, findings in order of harm.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { matcherVerdict, costByStep, orderFindings, secondsBetween } from './record.mjs';

test('the matcher verdict separates right, wrong, missed, real and added-by-the-test', () => {
  const fx = [
    { lead_id: 1, label: 'R1', should: 'right' }, { lead_id: 2, label: 'R2', should: 'right' }, { lead_id: 3, label: 'R3', should: 'right' },
    { lead_id: 4, label: 'W1', should: 'wrong_emirate' }, { lead_id: 5, label: 'U1', should: 'unrelated' },
  ];
  const v = matcherVerdict(fx, [{ lead_id: 1 }, { lead_id: 2 }, { lead_id: 4 }, { lead_id: 99, is_demo: true, company: 'ZZ DEMO other run' }, { lead_id: 7, is_demo: false, company: 'Real Co' }], [{ lead_id: 3 }]);
  assert.deepEqual(v.right_asked.map((x) => x.label), ['R1', 'R2']);
  assert.deepEqual(v.wrong_asked.map((x) => x.should), ['wrong_emirate', 'outside_this_run', 'REAL']);
  assert.deepEqual(v.right_missed.map((x) => x.label), ['R3']);
  assert.equal(v.real_supplier_asked.length, 1);
  assert.deepEqual(v.added_by_test.map((x) => x.label), ['R3']);
});

test('cost goes to the step whose window holds it; the rest is named, not lost', () => {
  const steps = [{ id: 's2', title: 'chat', start: '2026-11-13T10:00:00Z', end: '2026-11-13T10:10:00Z' }, { id: 's5', title: 'quotes', start: '2026-11-13T10:20:00Z', end: '2026-11-13T10:30:00Z' }];
  const c = costByStep([{ at: '2026-11-13T10:01:00Z', fn: 'inquiry_intake', usd: 0.01 }, { at: '2026-11-13T10:02:00Z', fn: 'inquiry_intake', usd: 0.02 },
    { at: '2026-11-13T10:25:00Z', fn: 'quote_extract', usd: 0.05 }, { at: '2026-11-13T10:15:00Z', fn: 'drawing_boq', usd: 0.1 }], steps);
  assert.equal(c.total_usd, 0.18);
  assert.deepEqual(c.by_step.map((b) => [b.step, b.calls, b.usd]), [['s2', 2, 0.03], ['s5', 1, 0.05], ['other', 1, 0.1]]);
});

test('findings are printed most serious first', () => {
  const o = orderFindings([{ severity: 'harness', text: 'h' }, { severity: 'looked_wrong', text: 'w' }, { severity: 'leak', text: 'l' }, { severity: 'product', text: 'p' }, { severity: 'leak', text: 'l2' }]);
  assert.deepEqual(o.map((f) => f.text), ['l', 'l2', 'p', 'w', 'h']);
  assert.equal(secondsBetween('2026-11-13T10:00:00.000Z', '2026-11-13T10:00:07.420Z'), 7.4);
});
