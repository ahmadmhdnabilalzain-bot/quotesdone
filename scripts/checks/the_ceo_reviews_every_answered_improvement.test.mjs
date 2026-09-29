// THE CEO REVIEWS EVERY ANSWERED IMPROVEMENT WITHIN ITS WINDOW (ceo, 28 Sep 2026).
//
// 113 answered ceo.improvement handoffs sat pending past their 1-day window because the only closer ran every
// 7 days and waited for the source to recover. This fails if the review routine disappears from the live
// mirror, stops closing accepted answers or returning the rest, or its seat_duty runs less often than hourly.
//
// The review is read from its CANONICAL definition (the last definer in MANIFEST order, pending files included):
// since 29 Sep 2026 a_rejection_never_ends_the_cycle_the_ceo_gives_reasons_and_the_seat_revises.sql decides each
// answer in fn_ceo_review_one_answered_improvement, so reading only FILE would certify a body production no
// longer runs. The seat duty is still FILE's.
//
//   node --test scripts/checks/the_ceo_reviews_every_answered_improvement.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { readSchemaMirror } from '../lib/schema_mirror.mjs';
import { manifestWithPending } from '../lib/pending_sql.mjs';
import { definitions } from '../lib/canonical_sql.mjs';

const at = (p) => fileURLToPath(new URL('../../' + p, import.meta.url));
const rd = (p) => readFileSync(at(p), 'utf8');
const FILE = 'scripts/sql/the_ceo_reviews_every_answered_improvement_within_its_window.sql';
const uncomment = (s) => s.split('\n').filter((l) => !/^\s*--/.test(l)).join('\n');
const code = uncomment(rd(FILE));
const review = (() => {
  const want = new Set(['fn_ceo_reviews_answered_improvements', 'fn_ceo_review_one_answered_improvement']);
  const out = new Map();
  for (const f of manifestWithPending()) {
    if (!existsSync(at(f))) continue;
    for (const d of definitions(rd(f))) if (want.has(d.name)) out.set(d.name, d.stmt);
  }
  return uncomment([...out.values()].join('\n'));
})();

test('the review closes accepted answers and returns the rest', () => {
  assert.match(review, /detail->>'type' = 'ceo\.improvement'/);
  assert.match(review, /a\.detail \? 'replied_at'/);
  assert.match(review, /fn_seat_handoff_complete\(h\.id/);
  assert.match(review, /\(detail - 'replied_at'\) \|\| jsonb_build_object\('returned'/);
});

test('it runs hourly as a CEO seat duty, inside the 1-day window', () => {
  assert.match(code, /\('ceo\.improvement_review', 'ceo', interval '1 hour', 'fn_ceo_reviews_answered_improvements'/);
});

test('the live mirror carries the routine', () => {
  assert.match(readSchemaMirror(), /FUNCTION public\.fn_ceo_reviews_answered_improvements\(\)/i);
});
