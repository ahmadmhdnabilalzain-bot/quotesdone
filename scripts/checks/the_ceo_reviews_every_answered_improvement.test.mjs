// THE CEO REVIEWS EVERY ANSWERED IMPROVEMENT WITHIN ITS WINDOW (ceo, 28 Sep 2026).
//
// 113 answered ceo.improvement handoffs sat pending past their 1-day window because the only closer ran every
// 7 days and waited for the source to recover. This fails if the review routine disappears from the live
// mirror, stops closing accepted answers or returning the rest, or its seat_duty runs less often than hourly.
//
//   node --test scripts/checks/the_ceo_reviews_every_answered_improvement.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { readSchemaMirror } from '../lib/schema_mirror.mjs';

const rd = (p) => readFileSync(fileURLToPath(new URL('../../' + p, import.meta.url)), 'utf8');
const FILE = 'scripts/sql/the_ceo_reviews_every_answered_improvement_within_its_window.sql';
const code = rd(FILE).split('\n').filter((l) => !/^\s*--/.test(l)).join('\n');

test('the review closes accepted answers and returns the rest', () => {
  assert.match(code, /detail->>'type' = 'ceo\.improvement'/);
  assert.match(code, /a\.detail \? 'replied_at'/);
  assert.match(code, /fn_seat_handoff_complete\(h\.id/);
  assert.match(code, /\(detail - 'replied_at'\) \|\| jsonb_build_object\('returned'/);
});

test('it runs hourly as a CEO seat duty, inside the 1-day window', () => {
  assert.match(code, /\('ceo\.improvement_review', 'ceo', interval '1 hour', 'fn_ceo_reviews_answered_improvements'/);
});

test('the live mirror carries the routine', () => {
  assert.match(readSchemaMirror(), /FUNCTION public\.fn_ceo_reviews_answered_improvements\(\)/i);
});
