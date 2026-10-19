// EVERY REVIEW HAS A REVIEWER OF ANOTHER FAMILY (ceo, 19 Oct 2026).
//
// think() cross-checks every high-stakes answer with a model of ANOTHER family (verify -> knowledge_validation, or the
// seat's own <seat>__knowledge_validation), routed by fn_ai_route_review_for from the reviewer class's model pair. A
// Claude-written answer can only be reviewed by the non-Claude model of that pair, so if a matrix change ever leaves a
// reviewer pair with no model outside an author's family, every such answer goes out
// 'review_held_no_independent_reviewer' while the answer itself still reads as answered. That is what the exam logs
// showed on 19 Oct (10 in one run); there the pair was right and the one cross-family reviewer was failing (thinking
// headroom, _shared/request_shape.ts). This guards the other half: the pair itself.
//
// For every active class that lists reviews_class, and every active class it reviews, each author model (primary and
// fallback) must have at least one reviewer model in the reviewer's pair whose family (the part before '/') differs.
// Reads production model_policy (read-only). Without a token the production test is skipped, unless
// MATRIX_REQUIRE_LIVE=1, where it fails rather than pass over nothing.
//
//   node --test scripts/checks/every_review_has_a_reviewer_of_another_family.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync } from 'node:fs';
import { join } from 'node:path';
import { homedir } from 'node:os';

const family = (m) => String(m ?? '').split('/')[0];

/** rows: model_policy rows {task_class, model_primary, model_fallback, reviews_class}. Returns the gaps. */
export function reviewGaps(rows) {
  const byClass = new Map(rows.map((r) => [r.task_class, r]));
  const gaps = [];
  for (const rv of rows) {
    const reviewers = [rv.model_primary, rv.model_fallback].filter(Boolean);
    for (const c of rv.reviews_class ?? []) {
      const author = byClass.get(c);
      if (!author) continue;   // a reviewed class that is not active has no author to review
      for (const a of [author.model_primary, author.model_fallback].filter(Boolean)) {
        if (!reviewers.some((m) => family(m) !== family(a))) gaps.push(`${rv.task_class} reviews ${c}: author ${a} has no reviewer outside ${family(a)} in [${reviewers.join(', ')}]`);
      }
    }
  }
  return gaps;
}

test('the guard bites: a reviewer pair inside the author family is a gap', () => {
  const rows = [
    { task_class: 'ceo__internal_judgement', model_primary: 'anthropic/claude-opus-5.5', model_fallback: null },
    { task_class: 'ceo__knowledge_validation', model_primary: 'anthropic/claude-sonnet-5.5', model_fallback: 'anthropic/claude-opus-5.5', reviews_class: ['ceo__internal_judgement'] },
  ];
  assert.equal(reviewGaps(rows).length, 1);
  rows[1].model_fallback = 'openai/gpt-6-luna-pro';
  assert.deepEqual(reviewGaps(rows), []);
});

const tok = process.env.SUPABASE_ACCESS_TOKEN || (existsSync(join(homedir(), '.supabase', 'access-token')) ? 'file' : null);
test('production: every active review class has a model of another family for every author', { skip: !tok && process.env.MATRIX_REQUIRE_LIVE !== '1' && 'no SUPABASE_ACCESS_TOKEN' }, async () => {
  const { sql } = await import('../lib/db.mjs');
  const rows = await sql(`select task_class, model_primary, model_fallback, reviews_class from public.model_policy where active`, { readOnly: true });
  assert.ok(Array.isArray(rows) && rows.some((r) => r.task_class === 'knowledge_validation'), 'model_policy read returned no knowledge_validation row');
  assert.deepEqual(reviewGaps(rows), []);
});
