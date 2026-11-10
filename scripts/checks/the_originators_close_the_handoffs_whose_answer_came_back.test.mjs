// THE ORIGINATORS CLOSE THE HANDOFFS WHOSE ANSWER CAME BACK AND WHOSE CONDITION IS MEASURED CLEARED (ceo, 10 Nov 2026,
// founder ruling 1574). Measured that day: 53 it.finding handoffs whose occurrence was over waited on their learning for
// good; the CEO left 36 of its own answered handoffs pending; customer_support's knowledge-request duty raised
// "an unnamed caller tried to close it" on every run since 1 Nov, so 50 answered requests never closed.
// Fix: scripts/sql/the_knowledge_request_duty_names_itself_when_it_closes_a_handoff.sql and
//      scripts/sql/the_originators_close_the_handoffs_whose_answer_came_back_and_whose_condition_cleared.sql
//   node --test scripts/checks/the_originators_close_the_handoffs_whose_answer_came_back.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { canonicalBody, productionSkip, rehearseChain } from '../lib/canonical_body.mjs';

test('the knowledge-request duty names customer_support as the closer, and clears the name after', () => {
  const { file, body } = canonicalBody('fn_customer_support_knowledge_request_tick');
  const set = body.indexOf("set_config('qd.handoff_closer', 'customer_support', true)");
  const close = body.indexOf('fn_seat_handoff_complete(');
  const clear = body.indexOf("set_config('qd.handoff_closer', '', true)");
  assert.ok(set >= 0 && close > set && clear > close, `${file}: the close is not wrapped in the originator's own name`);
});

test('the IT sweep closes only an occurrence that is over, with learning the record supports', () => {
  const { file, body } = canonicalBody('fn_it_close_cleared_handoffs');
  assert.match(body, /f0\.closed_at is not null\s+or f0\.started_at > \(a\.detail->>'occurrence_started_at'\)::timestamptz/, `${file}: the occurrence-over rule is missing`);
  assert.match(body, /awaiting_learning'\)::timestamptz < now\(\) - interval '24 hours'/, `${file}: the learning step is not given its day`);
  assert.match(body, /fn_it_attach_learning\(/, `${file}: the close does not go through fn_it_attach_learning (trigger z62's door)`);
  assert.match(body, /No seat applied a fix/, `${file}: the fix text must say no fix was applied, not invent one`);
  assert.match(body, /insert into public\.originator_close_record/, `${file}: a close leaves no record`);
});

test('the CEO closes its own handoffs on a measured predicate, never on age alone', () => {
  const { file, body } = canonicalBody('fn_ceo_closes_answered_handoffs');
  for (const t of ['ceo.root_cause', 'deliberation.review', 'ceo.revise', 'ceo.month_directive']) assert.ok(body.includes(`'${t}'`), `${file}: ${t} is not handled`);
  assert.match(body, /t\.state in \('done', 'closed', 'cancelled'\)/, `${file}: a root cause closes without its task being done`);
  assert.match(body, /v_last\.round > v_round/, `${file}: a revise closes without a later round decided`);
  assert.match(body, /fn_seat_deliberation_close\(d\.id, 'ceo'/, `${file}: the CEO's review is not closed through the deliberation's own door`);
  assert.doesNotMatch(body, /created_at < now\(\) - interval/, `${file}: a handoff must never close on its age`);
});

test('production, rolled back: the sweeps close only measured-cleared handoffs and record each one', { skip: productionSkip() }, async () => {
  const v = await rehearseChain(['scripts/sql/the_knowledge_request_duty_names_itself_when_it_closes_a_handoff.sql',
    'scripts/sql/the_originators_close_the_handoffs_whose_answer_came_back_and_whose_condition_cleared.sql'],
    'scripts/sql/the_originators_close_the_handoffs_whose_answer_came_back_and_whose_condition_cleared_probe.sql');
  assert.match(v, /^PROBE OK/, v);
});
