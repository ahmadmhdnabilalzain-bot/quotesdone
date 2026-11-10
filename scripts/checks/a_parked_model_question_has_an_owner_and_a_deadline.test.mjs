// A PARKED MODEL QUESTION HAS AN OWNER AND A DEADLINE, AND CLOSES WHEN WHAT IT WAS ABOUT IS SETTLED (it_engineer, 10 Nov
// 2026, ruling 1574). Measured that day: 822 pending held_question rows, none with an owner field or a deadline; 438 of
// them about a question already applied or expired.
// Fix: scripts/sql/a_parked_model_question_has_an_owner_and_a_deadline.sql
//   node --test scripts/checks/a_parked_model_question_has_an_owner_and_a_deadline.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { canonicalBody, productionSkip, read, rehearseChain } from '../lib/canonical_body.mjs';

const FILE = 'scripts/sql/a_parked_model_question_has_an_owner_and_a_deadline.sql';

test('every parked question gets its seat and a deadline, and closes only on its record', () => {
  const { body } = canonicalBody('fn_held_questions_settle');
  assert.match(body, /'owner_seat', x\.agent/);
  assert.match(body, /fn_seat_clock_policy\('held_question_days', 7\)/);
  assert.match(body, /a\.rstatus = 'applied'/);
  assert.match(body, /not public\.fn_held_question_is_person_facing\(a\.rsurface\)/, 'a person-facing question must never be dismissed by age or expiry');
  assert.doesNotMatch(read(FILE), /create trigger [a-z0-9_]+[\s\S]{0,80}on public\.agent_actions/i, 'no DDL may lock agent_actions');
});

test('a WhatsApp turn, a supplier or portal reply and the request chat are person-facing', () => {
  const { body } = canonicalBody('fn_held_question_is_person_facing');
  for (const s of ['wa_inbound.unwritten_reply', 'supplier_api.quote_review_unwritten', 'sales_engineer.portal_unwritten', 'inquiry_intake.unwritten_reply']) {
    assert.ok(body.includes(`'${s}'`), `${s} is not person-facing`);
  }
});

test('production, rolled back: the 822 settle, and no person-facing question is dismissed', { skip: productionSkip() }, async () => {
  const v = await rehearseChain([FILE], FILE.replace(/\.sql$/, '_probe.sql'));
  assert.match(v, /^PROBE OK/, v);
});
