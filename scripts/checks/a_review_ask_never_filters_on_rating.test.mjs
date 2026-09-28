// A PUBLIC REVIEW ASK NEVER FILTERS ON RATING (marketing, 28 Sep 2026).
//
// fn_marketing_reputation asked only customers who had rated 4 or 5. Choosing who is asked for a public
// review by the rating they gave is review gating, which Google's review policy forbids. This fails if:
//   1. the chooser (fn_marketing_review_ask_candidates) names a rating or reads public.reviews;
//   2. fn_marketing_reputation names a rating anywhere before its reputation snapshot (the ask part);
//   3. company_review_ask carries a rating again;
//   4. any other routine queues a review ask or sends a public_review_ask.
// Source: the canonical fix file while its scripts/sql/pending note exists, then the live mirror.
// Behaviour is proven by scripts/sql/every_customer_is_asked_for_a_public_review_whatever_their_rating_probe.sql.
//
//   node --test scripts/checks/a_review_ask_never_filters_on_rating.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';

const REPO = fileURLToPath(new URL('../..', import.meta.url));
const read = (p) => readFileSync(join(REPO, p), 'utf8');
const FIX = 'scripts/sql/every_customer_is_asked_for_a_public_review_whatever_their_rating.sql';
const PENDING = 'scripts/sql/pending/every_customer_is_asked_for_a_public_review_whatever_their_rating.txt';
const MIRROR = read('supabase/schema/full_schema.sql');
const SRC = existsSync(join(REPO, PENDING)) ? read(FIX) : MIRROR;
const code = (s) => s.split('\n').map((l) => l.replace(/--.*$/, '')).join('\n');

// Every routine in a source, by name: the text from its header to the next routine header.
function routines(sql) {
  const heads = [...sql.matchAll(/create or replace function public\.(\w+)\s*\(/gi)];
  return heads.map((m, i) => ({ name: m[1], body: code(sql.slice(m.index, i + 1 < heads.length ? heads[i + 1].index : sql.length)) }));
}
const bodyOf = (sql, name) => {
  const r = routines(sql).find((x) => x.name === name);
  assert.ok(r, name + ' is defined');
  return r.body;
};

test('the chooser never reads a rating or a review', () => {
  const b = bodyOf(SRC, 'fn_marketing_review_ask_candidates');
  assert.doesNotMatch(b, /\brating\b/i, 'the review-ask chooser names a rating');
  assert.doesNotMatch(b, /public\.reviews\b/i, 'the review-ask chooser reads public.reviews');
});

test('the ask part of fn_marketing_reputation never names a rating', () => {
  const b = bodyOf(SRC, 'fn_marketing_reputation');
  const cut = b.indexOf('company_reputation_snapshot');
  assert.ok(cut > 0, 'the reputation snapshot is found');
  assert.doesNotMatch(b.slice(0, cut), /\brating\b/i, 'fn_marketing_reputation filters or words its ask by rating');
  assert.match(b.slice(0, cut), /fn_marketing_review_ask_candidates\s*\(\s*\)/, 'the duty does not choose through the rating-blind chooser');
});

test('company_review_ask carries no rating', () => {
  if (SRC === MIRROR) {
    const t = MIRROR.slice(MIRROR.indexOf('CREATE TABLE IF NOT EXISTS public.company_review_ask ('));
    assert.doesNotMatch(t.slice(0, t.indexOf(');')), /\brating\b/i, 'company_review_ask has a rating column');
  } else {
    assert.match(SRC, /drop column if exists rating;/, 'the fix does not drop the rating column');
  }
});

test('no other routine queues or sends a review ask', () => {
  const writers = routines(MIRROR).concat(SRC === MIRROR ? [] : routines(SRC))
    .filter((r) => /insert into public\.company_review_ask|'public_review_ask'/i.test(r.body))
    .map((r) => r.name);
  assert.deepEqual([...new Set(writers)].sort(), ['fn_marketing_reputation'], 'an unchecked routine writes review asks');
});
