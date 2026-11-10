// A REVISION THE MODEL CANNOT WRITE IS ASKED ONCE ON ANOTHER FAMILY, THEN WRITTEN FROM THE CEO'S REASONS, AND A PARKED
// REVISION COUNTS AS A ROUND (ceo, 10 Nov 2026, rulings 1059 and 1574). Measured that day: 14 items' last CEO decision was
// 'rejected' and every one of their 14 revision questions had failed on the same route; the refile waited 7 days and
// asked that route again, and a revision never written was never a round, so the 4-round guard could not trip.
// Fix: scripts/sql/a_revision_the_model_cannot_write_is_asked_on_another_family_then_written_from_the_reasons.sql
//      supabase/functions/_shared/think/engine.ts (otherFamilyThan; _shared/think_other_family.test.ts)
//   node --test scripts/checks/a_revision_the_model_cannot_write_is_asked_on_another_family.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { canonicalBody, productionSkip, read, rehearseChain } from '../lib/canonical_body.mjs';

test('a failed revision is asked again once on another family, then written from the reasons, then parked as a round', () => {
  const { file, body } = canonicalBody('fn_ceo_revision_refile');
  assert.match(body, /'otherFamilyThan', v_model/, `${file}: the re-asked question does not name the family to avoid`);
  assert.match(body, /'other_family_at'/, `${file}: the another-family ask is not marked, so it would repeat`);
  assert.match(body, /fn_ceo_revision_applies\(h\.id, v_result\)/, `${file}: the deterministic revision does not go through the model answer's own door`);
  assert.match(body, /'model', 'deterministic'/, `${file}: a revision written by code must say so`);
  assert.match(body, /'parks', coalesce\(\(evidence->>'parks'\)::int, 0\) \+ 1/, `${file}: a park is not counted`);
  assert.match(body, /fn_ceo_decision_owe\(/, `${file}: at 4 rounds the CEO is not owed the choice`);
  assert.doesNotMatch(body, /interval '7 days'/, `${file}: the failed revision must not wait a week on the route that failed`);
  assert.doesNotMatch(body, /fn_notify_founder|to_role.*founder/, `${file}: the founder is never in the loop (1059)`);
});

test('fn_ceo_decision_next counts parked revisions with the rejections, so fn_ceo_decide\'s guard trips on them', () => {
  const { file, body } = canonicalBody('fn_ceo_decision_next');
  assert.match(body, /'rejections'[\s\S]*decision = 'rejected'\)[\s\S]*\+ \(select coalesce\(sum\(\(a\.evidence->>'parks'\)::int\), 0\)/, `${file}: parks are not in 'rejections'`);
  assert.match(canonicalBody('fn_ceo_decide').body, /if v_rej >= 4 then/, 'fn_ceo_decide no longer refuses a fifth round');
});

test('think() sends a re-asked synthesis to another family', () => {
  const engine = read('supabase/functions/_shared/think/engine.ts');
  assert.match(engine, /const synthRoute = req\.otherFamilyThan \? \{ counterpartModel: req\.otherFamilyThan \} : \{\};/);
  assert.equal((engine.match(/\.\.\.synthRoute/g) || []).length, 2, 'both synthesis passes must carry the route');
});

test('production, rolled back: the 14 pending revisions go through the whole cycle', { skip: productionSkip() }, async () => {
  const v = await rehearseChain(['scripts/sql/a_revision_the_model_cannot_write_is_asked_on_another_family_then_written_from_the_reasons.sql'],
    'scripts/sql/a_revision_the_model_cannot_write_is_asked_on_another_family_then_written_from_the_reasons_probe.sql');
  assert.match(v, /^PROBE OK/, v);
});
