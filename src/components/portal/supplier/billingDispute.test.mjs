// node --test src/components/portal/supplier/billingDispute.test.mjs
// Walk of 12 Nov 2026 (sales_engineer, built by it_engineer). S9: on a phone the due row crushed "Due ..." and "Dispute this charge"
// into a 42 px column, one word per line (p1_android_a_billing.jpg). S10: disputing a charge used window.prompt and window.alert.
// This fails if the row goes back to one squeezed line on a phone, or the browser's boxes come back, or Send loses its moving state.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const src = readFileSync(new URL('./core/Billing.tsx', import.meta.url), 'utf8');

test('the due row stacks on a phone and sits in one line from 640 px', () => {
  const row = /<div key=\{d\.id\} className="([^"]*)" data-testid="bill-due-row">/.exec(src);
  assert.ok(row, 'the due row is gone');
  assert.match(row[1], /\bflex-col\b/); assert.match(row[1], /\bsm:flex-row\b/);
  assert.match(src, /data-testid="bill-dispute"[\s\S]{0,120}whitespace-nowrap/, 'the dispute button can wrap one word per line');
});

test('a dispute is asked and answered in the portal\'s own form, under the charge, and Send turns and cannot be pressed twice', () => {
  assert.doesNotMatch(src, /window\.(prompt|alert|confirm)\(/);
  assert.match(src, /\{disputeOf === d\.id && <div role="group"[^>]*data-testid="bill-dispute-dialog"/, 'the dispute form is not under its charge');
  assert.match(src, /data-testid="bill-dispute-send" busy=\{disp\.busy\} disabled=\{disp\.pending\}/);
  assert.match(src, /<textarea rows=\{4\}/);
});
