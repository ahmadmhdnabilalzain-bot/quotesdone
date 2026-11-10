// THE FOUNDER GETS ONE DAILY LIST OF WHAT A SESSION MUST FIX, ON THE IT DIGEST HE ALREADY RECEIVES (it_engineer, 10 Nov
// 2026, ruling 1574). Measured that day: what only a working session can fix (a duty failing every run, questions past
// their deadline, what a playbook refused) had no way to reach him; a second email kind is not the answer.
// Fix: scripts/sql/the_founder_gets_one_daily_list_of_what_a_session_must_fix.sql
//   node --test scripts/checks/the_founder_gets_one_daily_list_of_what_a_session_must_fix.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { canonicalBody, productionSkip, rehearseChain } from '../lib/canonical_body.mjs';

test('the list rides on the IT digest, under its own kind, and the decisions are chosen as before', () => {
  const { file, body } = canonicalBody('fn_customer_support_sends_the_it_digest');
  assert.match(body, /public\.fn_it_session_fix_list\(\)/, `${file}: the digest does not read the list`);
  assert.match(body, /if jsonb_array_length\(v_items\) = 0 and n_sess = 0 then/, `${file}: an empty list would still send`);
  assert.equal((body.match(/p_kind => '/g) || []).length, 1, `${file}: the digest must send one kind of email`);
  assert.match(body, /p_kind => 'it_daily_digest'/);
  assert.match(body, /not v_his or coalesce\(v_cat, ''\) not in \('money', 'destructive_production_change', 'fact_only_he_holds'\)/,
    `${file}: decisions must still be his three categories only`);
});

test('the list is at most twelve lines, in words', () => {
  const { body } = canonicalBody('fn_it_session_fix_list');
  assert.match(body, /where rn <= 12/);
  assert.match(body, /replace\(split_part\(d\.duty, '\.', 2\), '_', ' '\)/, 'a duty is named in words, not by its key');
  assert.match(body, /fn_held_question_is_person_facing\(q\.surface\) then 0/, 'a person waiting comes first');
});

test('production, rolled back: the list today and the digest it would send (stubbed)', { skip: productionSkip() }, async () => {
  const v = await rehearseChain(['scripts/sql/the_knowledge_request_duty_names_itself_when_it_closes_a_handoff.sql',
    'scripts/sql/the_originators_close_the_handoffs_whose_answer_came_back_and_whose_condition_cleared.sql',
    'scripts/sql/a_parked_model_question_has_an_owner_and_a_deadline.sql',
    'scripts/sql/the_it_engineer_runs_the_safe_fix_playbooks_itself.sql',
    'scripts/sql/the_founder_gets_one_daily_list_of_what_a_session_must_fix.sql'],
    'scripts/sql/the_founder_gets_one_daily_list_of_what_a_session_must_fix_probe.sql');
  assert.match(v, /^PROBE OK/, v);
});
