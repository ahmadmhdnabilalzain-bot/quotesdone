// node --test src/components/portal/supplier/insightsHoldsItsPlace.test.mjs
// Walk of 12 Nov 2026, S11 (sales_engineer, built by it_engineer): opening Insights shifted the layout (CLS 0.62 / 0.43 / 0.39 at
// 390 / 360 / 1440): the scorecard and summary chunks had only the shared 160 px placeholder, and the summary's own loading state was
// 192 px against 1,250-1,950 px loaded. This fails if either placeholder stops holding its loaded size.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const ins = readFileSync(new URL('./Insights.tsx', import.meta.url), 'utf8');
const sum = readFileSync(new URL('./SupplierInsightsSummary.tsx', import.meta.url), 'utf8');
const card = readFileSync(new URL('./SupplierScorecard.tsx', import.meta.url), 'utf8');

test('the scorecard and the summary hold their loaded size while they load', () => {
  assert.match(ins, /const Scorecard: any = dynamic\([^\n]*loading: \(\) => <section className="qd-panel min-h-56 sm:min-h-\[134px\]"/);
  assert.match(card, /className="qd-panel min-h-56 sm:min-h-\[134px\]"/, 'the scorecard\'s own loading state and its chunk placeholder differ');
  assert.match(ins, /const Summary: any = dynamic\([^\n]*loading: \(\) => <section className="qd-panel min-h-svh/);
  assert.match(sum, /if \(!s\) return <section className="qd-panel min-h-svh/);
});
