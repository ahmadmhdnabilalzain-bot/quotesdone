// THE IT ENGINEER RUNS THE SAFE-FIX PLAYBOOKS ITSELF (it_engineer, 10 Nov 2026, ruling 1574). Measured that day: 54
// it_playbook rows, 1 with a remedy routine, 0 playbook runs ever, while the families below stayed open by the dozen.
// Fix: scripts/sql/the_it_engineer_runs_the_safe_fix_playbooks_itself.sql
//   node --test scripts/checks/the_it_engineer_runs_the_safe_fix_playbooks_itself.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { canonicalBody, productionSkip, read, rehearseChain } from '../lib/canonical_body.mjs';

const FILE = 'scripts/sql/the_it_engineer_runs_the_safe_fix_playbooks_itself.sql';
const FAMILIES = ['close_cleared_handoffs', 'delivery_outcome', 'model_consumer', 'workflow_park', 'credential_rotation',
  'backup_requeue', 'marketing_step_retry', 'expire_parked_questions'];
// a playbook never writes these: leads, quotes, money, customers, inquiries
const BUSINESS = /\b(?:insert\s+into|update|delete\s+from)\s+(?:public\.)?(leads|quotes|transactions|customers|inquiries|refunds|supplier_dues|expense_entries|gl_journal)\b/i;

test('the eight families are approved by ruling 1574, each with a routine and a guardrail', () => {
  const src = read(FILE);
  for (const f of FAMILIES) assert.match(src, new RegExp(`\\('${f}', [^\\n]*'fn_it_safe_fix_[a-z_]+'`), `${f} has no routine row`);
  assert.equal((src.match(/, 1574, true,/g) || []).length, FAMILIES.length, 'every listed family carries ruling 1574 and is active');
  assert.match(src, /check \(not active or approval_ruling is not null or ceo_approved_at is not null\)/, 'an unapproved family could be made active');
});

test('no family routine writes business data, deploys, or touches a schema', () => {
  for (const fn of ['fn_it_safe_fix_delivery_outcome', 'fn_it_safe_fix_model_consumer', 'fn_it_safe_fix_workflow_park', 'fn_it_safe_fix_credential_rotation',
    'fn_it_safe_fix_backup_requeue', 'fn_it_safe_fix_marketing_step_retry', 'fn_it_safe_fix_close_cleared_handoffs', 'fn_it_safe_fix_expire_parked_questions']) {
    const { body } = canonicalBody(fn);
    const code = body.replace(/--[^\n]*/g, '').replace(/'(?:[^']|'')*'/g, "''");
    assert.doesNotMatch(code, BUSINESS, `${fn} writes a business table`);
    assert.doesNotMatch(code, /\b(?:create|alter|drop)\s+(?:table|function|trigger|policy)\b|net\.http_post|app_secrets\s+set/i, `${fn} changes a schema, calls out or writes a secret`);
  }
});

test('the dispatcher bounds every family and parks one that fails twice', () => {
  const { body } = canonicalBody('fn_it_safe_fix_tick');
  assert.match(body, /< fam\.max_runs_per_occurrence/);
  assert.match(body, /exit when n >= fam\.max_per_tick/);
  assert.match(body, /outcome = 'failed' and r\.ran_at > now\(\) - interval '1 day'\) >= 2/);
  assert.match(body, /insert into public\.it_safe_fix_run/);
});

test('production, rolled back: what each family fixes today', { skip: productionSkip() }, async () => {
  const v = await rehearseChain(['scripts/sql/the_knowledge_request_duty_names_itself_when_it_closes_a_handoff.sql',
    'scripts/sql/the_originators_close_the_handoffs_whose_answer_came_back_and_whose_condition_cleared.sql',
    'scripts/sql/a_parked_model_question_has_an_owner_and_a_deadline.sql', FILE], FILE.replace(/\.sql$/, '_probe.sql'));
  assert.match(v, /^PROBE OK/, v);
});
