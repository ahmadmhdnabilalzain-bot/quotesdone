// fn_ceo_delivery_undelivered_decide must not cast a handoff's subject_id to bigint unguarded.
// ceo, 28 Sep 2026: report 6330's subject_id was a text dedupe key ("wa_templates_ready:<email>:<uuid>"),
// the cast raised, and fn_ceo_report_answer_sweep left the report unanswered (ceo:report_answer_failed).
// Reads the live mirror, which every PR keeps equal to production.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readSchemaMirror } from '../lib/schema_mirror.mjs';

test('the CEO delivery decider guards its subject_id cast', () => {
  const schema = readSchemaMirror();
  const m = schema.match(/FUNCTION public\.fn_ceo_delivery_undelivered_decide\([\s\S]*?\nend \$function\$/);
  assert.ok(m, 'fn_ceo_delivery_undelivered_decide is in the mirror');
  assert.doesNotMatch(m[0], /nullif\(v_req\.detail ->> 'subject_id', ''\)::bigint/, 'unguarded bigint cast of subject_id');
  assert.match(m[0], /'subject_id' ~ '\^\[0-9\]/, 'subject_id is cast only when all digits');
});
