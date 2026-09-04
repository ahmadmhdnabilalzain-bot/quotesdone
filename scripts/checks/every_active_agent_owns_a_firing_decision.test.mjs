// EVERY ACTIVE AGENT OWNS A FIRING DECISION — the binding rule that sizes the roster (MASTER_PLAN §3).
//
//   An agent exists only if it OWNS a decision that fires: one event it consumes, one action it can
//   execute, one playbook/rule it applies. No owned firing decision -> the persona is parked.
//
// public.fn_agent_binding_rule() measures the three per active persona on production, the same way
// every run (see scripts/sql/fn_agent_binding_rule.sql for what each column reads). This is a GATE:
// the failing set must be empty. A persona activated without a subscription, a mechanism or a scoped
// playbook reddens CI here instead of drawing a paid brain-turn for nothing.
//
// It also holds the plan's shape: 10 active departments, 45–54 active personas, at most 12 seats above
// 'specialist' (one lead per department plus the two CEO-office officers), every active persona
// reporting to its department lead (the CEO alone reports to nobody).
//
//   node --test scripts/checks/every_active_agent_owns_a_firing_decision.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync } from 'node:fs';
import { join } from 'node:path';
import { homedir } from 'node:os';

const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN
  || existsSync(join(homedir(), '.supabase', 'access-token'));
if (!hasToken) console.log('NOT_VERIFIED_MISSING_MANAGEMENT_CREDENTIAL');
const skip = hasToken ? false : 'no Supabase management token';

const PROD_REF = 'htdblwldjkcgjvmqkbeh';
const mgmtRead = async (ref, sql) => (await import('../staging/qd_guard.mjs')).mgmtRead(ref, sql);
const rows = async (sql) => { const r = await mgmtRead(PROD_REF, sql); return Array.isArray(r) ? r : []; };

test('every active persona consumes an event, can execute a mechanism, and applies a scoped playbook', { skip }, async () => {
  const bad = await rows(`
    select agent_key, department, has_event, has_executor, has_playbook
      from public.fn_agent_binding_rule() where not passes order by department, agent_key`);
  for (const r of bad) console.error(`  ${r.department}/${r.agent_key}: event=${r.has_event} executor=${r.has_executor} playbook=${r.has_playbook}`);
  assert.equal(bad.length, 0, `${bad.length} active persona(s) own no firing decision`);
});

test('the roster holds the plan\'s shape', { skip }, async () => {
  const [r] = await rows(`
    select (select count(*) from public.org_departments where active) depts,
           (select count(*) from public.org_agents where active) active,
           (select count(*) from public.org_agents where active and seniority <> 'specialist') leadership,
           (select count(*) from public.org_agents where active and manager_key is null) apex,
           (select count(*) from public.org_agents a join public.org_departments d on d.dept_key = a.department
             where a.active and a.agent_key <> d.lead_agent and a.manager_key <> d.lead_agent
               and not (a.department = 'exec' and a.manager_key = 'ceo')) not_reporting_to_lead`);
  assert.equal(Number(r.depts), 10, 'ten active departments');
  assert.ok(Number(r.active) >= 45 && Number(r.active) <= 54, `active personas ${r.active} outside the plan's 45–54`);
  assert.ok(Number(r.leadership) <= 12, `${r.leadership} leadership seats, the plan allows 12`);
  assert.equal(Number(r.apex), 1, 'only the CEO reports to nobody');
  assert.equal(Number(r.not_reporting_to_lead), 0, 'a worker does not report to its department lead');
});
