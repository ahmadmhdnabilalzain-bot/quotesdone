// THE CEO RULE spend_against_constraint IS MEASURED FROM THE ACCOUNTANT'S BOOKS. ceo, 28 Sep 2026.
// Until then the branch answered 'not_instrumented' and fn_ceo_decisions_evaluate reported ok:false.
// This fails if the branch stops reading the posted journal or the attribution table, or goes back
// to declaring itself blind. It reads the schema mirror once the file is applied, and the file before.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const FILE = 'scripts/sql/spend_against_the_constraint_is_measured_from_the_books.sql';
const MIRROR = 'supabase/schema/full_schema.sql';

function evaluatorBody() {
  const mirror = readFileSync(MIRROR, 'utf8');
  const m = mirror.match(/FUNCTION public\.fn_ceo_decisions_evaluate\([\s\S]*?\n\$function\$;?/i);
  if (m && m[0].includes('gl_account_funnel_stage')) return m[0];
  return readFileSync(FILE, 'utf8');   // before the apply: the pending file is the definition
}

test('spend_against_constraint reads posted expense lines through the stage attribution', () => {
  const body = evaluatorBody();
  const start = body.indexOf("when 'spend_against_constraint' then");
  assert.ok(start > 0, 'the evaluator has no spend_against_constraint branch');
  const branch = body.slice(start, body.indexOf("when 'structure' then", start));
  assert.match(branch, /public\.gl_journal_lines/);
  assert.match(branch, /j\.status = 'posted'/);
  assert.match(branch, /public\.gl_account_funnel_stage/);
  assert.doesNotMatch(branch, /v_blind := v_blind/, 'the branch declares itself not_instrumented again');
});

test('the attribution table is service-role only', () => {
  const sql = readFileSync(FILE, 'utf8');
  assert.match(sql, /alter table public\.gl_account_funnel_stage enable row level security/);
  assert.match(sql, /create policy gl_account_funnel_stage_service_role_only/);
  assert.match(sql, /revoke all on public\.gl_account_funnel_stage from anon, authenticated/);
});
