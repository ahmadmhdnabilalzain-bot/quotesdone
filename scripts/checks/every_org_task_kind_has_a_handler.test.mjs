// EVERY ORG TASK KIND HAS A HANDLER, AND A DECISION GOES TO THE SEAT THAT OWNS IT (ceo, 10 Nov 2026, ruling 1574).
// Measured that day: 6 assigned routine_operational_decision tasks of founder_mail kinds the consumer had no branch for,
// the oldest 47 days and 71 attempts, and the CEO's own AED 1M forecast paper in customer_support's queue.
// Fix: scripts/sql/every_org_task_kind_has_a_handler_and_a_decision_goes_to_its_owner.sql
//   node --test scripts/checks/every_org_task_kind_has_a_handler.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { canonicalBody, productionSkip, read, rehearseChain } from '../lib/canonical_body.mjs';

const FILE = 'scripts/sql/every_org_task_kind_has_a_handler_and_a_decision_goes_to_its_owner.sql';

test('the six kinds that had no handler, and the misrouted one, are in the register with their owner', () => {
  const src = read(FILE);
  for (const [kind, owner] of [['supplier_invite_seed', 'ceo'], ['invite_m365_seed', 'ceo'], ['wa_templates_ready', 'ceo'],
    ['invite_paused_bounce', 'sales_engineer'], ['business_health_at_risk', 'ceo']]) {
    assert.match(src, new RegExp(`'routine_operational_decision', '${kind}', '${owner}'`), `${kind} is not registered to ${owner}`);
  }
  for (const kind of ['expense_logged', 'rfq_no_supplier', 'supplier_registered', 'sales_rating']) {
    assert.match(src, new RegExp(`'routine_operational_decision', '${kind}', '[a-z_]+', 'consumer'`), `${kind} (the consumer's) is not registered`);
  }
});

test('a new task of a registered kind lands on its owner, and the tick never closes a consumer kind or a waiting person', () => {
  assert.match(read(FILE), /create trigger a06_org_task_goes_to_its_kinds_owner before insert on public\.org_tasks/);
  const { body } = canonicalBody('fn_org_task_kind_handlers_tick');
  assert.match(body, /if k\.handler = 'consumer' then continue; end if;/, 'the tick must leave the consumer\'s kinds alone');
  assert.match(body, /\(inquiry\|quote\|rfq\|lead\)/, 'a task with a person waiting must stay open');
  assert.match(body, /fn_org_task_close_as_fact\(/, 'a close must go through fn_org_task_close_as_fact');
  assert.match(body, /fn_it_duty_settle\('org_task_kind_unregistered'/, 'an unregistered kind must be one finding');
});

test('production, rolled back: the six are handled and the misrouted one reaches the CEO', { skip: productionSkip() }, async () => {
  const v = await rehearseChain([FILE], FILE.replace(/\.sql$/, '_probe.sql'));
  assert.match(v, /^PROBE OK/, v);
});
