// RETIRED 9 SEP 2026 — THE INSTRUMENT AND ALL THREE OF ITS SUBJECTS WERE DELETED WITH THE ROSTER.
//
// WHAT WAS DROPPED, AND WHEN. The founder ruled on 7 Sep 2026 that everything outside the new
// structure is deleted, collapsing the company to exactly two agents — `ceo` and `customer_support`
// — with NO departments and no role hierarchy; the Phase A–D programme went on 9 Sep. That took the
// whole apparatus this file measured.
//
// MEASURED ON PRODUCTION (htdblwldjkcgjvmqkbeh) 9 SEP 2026, not inferred from the code:
//
//   public.fn_agent_binding_rule()   0 rows in pg_proc — the routine both tests below called is gone
//                                    (42883: function public.fn_agent_binding_rule() does not exist)
//   public.org_agents                2 rows, both active: ceo, customer_support; department NULL on
//                                    both, manager_key NULL on both
//   public.org_departments           table present, 0 rows — so `depts` is 0, never the 10 asserted
//
// AND ITS THREE LIMBS, each read from the table that made it true (git c435fdf, the original
// fn_agent_binding_rule.sql), are all structurally empty — not merely inactive:
//
//   has_event     public.event_subscription      0 rows (0 active). The dispatcher table the rule
//                                                called the only thing that counts as "consumes an
//                                                event" holds nothing for any agent.
//   has_executor  public.workflow                0 active; public.workflow_step 0 rows;
//                                                public.org_action_executor 0 active; and
//                                                public.phase_c_component does not exist at all.
//                                                Both halves of the executor limb are gone.
//   has_playbook  public.org_role_identity 13 rows and public.ops_knowledge 9,139 rows survive, but
//                                                a playbook alone was never the rule — the rule was
//                                                the conjunction of all three, and two are empty.
//
// WHY NOTHING IS LEFT TO CHECK, AND WHY THIS IS NOT REPAIRED. The property "every active agent owns
// a decision that fires" cannot be re-pointed at what survives: no surviving table binds an agent to
// an event, a mechanism or a firing decision. Every table on production carrying an agent_key that
// still holds rows records what an agent KNOWS or DID (agent_knowledge, agent_memory, agent_chats,
// agent_actions, employee_authority, skills_matrix) — none records what it is subscribed to or may
// execute. Measuring the property honestly today would require first rebuilding the subscription and
// executor machinery the founder deliberately deleted. That is his call to make, not this check's,
// so it is recommended and not done.
//
// The second test is worse than unmeasurable, it is now WRONG: it asserted 10 active departments,
// 45–54 active personas, at most 12 leadership seats and every worker reporting to a department
// lead. The founder's 7 Sep ruling is 2 agents and 0 departments. Left running, this file would
// redden CI for the estate matching his instruction.
//
// NOT SOFTENED, RETIRED. Neither assertion was relaxed to make it pass; the file stops running
// because both of its subjects — the binding-rule routine and the ten-department roster — no longer
// exist. His standing rule "no job or task exists without an agent" is the INVERSE direction and is
// unaffected by this retirement; it is not measured here and never was.
//
// ORIGINAL HEADER FOLLOWS.
//
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
const mgmtRead = async (ref, sql) => (await import('../../lib/qd_guard.mjs')).mgmtRead(ref, sql);
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
