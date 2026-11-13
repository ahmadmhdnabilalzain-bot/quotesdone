// A RUN'S PRIVACY REQUESTS ARE TORN DOWN BY ITS OWN ADDRESSES (13 Nov 2026, customer_support; built by it_engineer).
// The live walk of "Download my data" (run 272229bd) left 8 pdpl_requests and 8 pdpl_operator_log rows after teardown
// reported 0 leftovers: the factory never reached either table. Teardown now removes them by the run's exact addresses
// (its customers' e-mails and its leads' sign-in addresses, each also carrying the run's tag), before the customers and
// leads that name those addresses are deleted. This fails if the steps go, run after the rows they read, or widen to a
// pattern on a domain that another run or a real person could match.
//   node --test scripts/checks/a_runs_privacy_requests_are_torn_down_by_its_own_addresses.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { pdplSteps, runAddressesSql } from '../lib/demo_factory.mjs';

const SRC = readFileSync(new URL('../lib/demo_factory.mjs', import.meta.url), 'utf8');
const S = { cust: `(email like 'qd-abcd1234-%@example.%')`, lead: `'qd_run:abcd1234' = any(coalesce(tags,'{}'::text[]))` };

test('the four privacy tables are removed, children first, by the run\'s own addresses', () => {
  const steps = pdplSteps('abcd1234', S);
  assert.deepEqual(steps.map(([l]) => l), ['pdpl_operator_log (run)', 'pdpl_erase_files (run)', 'pdpl_lead_erase_vault (run)', 'pdpl_requests (run)']);
  const addr = runAddressesSql('abcd1234', S);
  for (const [, sql] of steps) assert.ok(sql.includes(addr), sql);
  assert.match(addr, /from public\.customers where/); assert.match(addr, /from public\.leads where/);
});

test('an address must belong to the run itself: its tag, never just a domain', () => {
  const addr = runAddressesSql('abcd1234', S);
  assert.ok(addr.includes("like 'qd-abcd1234-%@example.%'") && addr.includes("like 'delivered+qd-abcd1234-%@resend.dev'"));
  for (const [, sql] of pdplSteps('abcd1234', S)) {
    assert.doesNotMatch(sql, /like '%@|like 'delivered\+qd-%@|like 'qd-%@/, 'no pattern that matches every run or a whole domain');
  }
});

test('they run while the customers and leads that name the addresses still exist', () => {
  const at = (label) => SRC.indexOf(label);
  const pdpl = at('...pdplSteps(tag, s)');
  assert.ok(pdpl > 0, 'teardown calls pdplSteps');
  assert.ok(pdpl < at("['leads', `with im as (delete from public.inbound_messages where lead_id in ${LEAD})"), 'before leads');
  assert.ok(pdpl < at("['customers', `delete from public.customers where id in ${CUST}`]"), 'before customers');
});
