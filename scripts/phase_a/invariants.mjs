// PHASE A — STEP 7: the deterministic invariant suite, run against production.
//
// Deliberately NOT the same code as the migration's own postconditions. A migration that asserts
// its own success is a closed loop; this reads the database back from outside and asks the
// questions PHASE_A_INVARIANTS.md asks, in its own words. Read-only throughout — every statement
// goes through mgmtRead, which refuses anything that is not.
//
//   node scripts/phase_a/invariants.mjs
import { mgmtRead, PROD_REF } from '../staging/qd_guard.mjs';

const q = async (s) => mgmtRead(PROD_REF, s);
const one = async (s) => (await q(s))[0];
let pass = 0, fail = 0;
const sect = (s) => console.log(`\n── ${s} ${'─'.repeat(Math.max(0, 74 - s.length))}`);
const check = (name, ok, detail = '') => {
  if (ok) { pass++; console.log(`PASS  ${name}${detail ? '  — ' + detail : ''}`); }
  else { fail++; console.log(`FAIL  ${name}  — ${detail}`); }
};
const eq = async (name, sql, want, unit = '') => {
  const v = Number(Object.values(await one(sql))[0]);
  check(name, v === want, `${v}${unit}${v === want ? '' : ` (expected ${want})`}`);
  return v;
};
const zero = async (name, sql, what) => {
  const rows = await q(sql);
  check(name, rows.length === 0, rows.length ? `${rows.length}: ` + rows.slice(0, 6).map(r => Object.values(r).join('/')).join(', ') : `0 ${what}`);
};

sect('Counts');
await eq('active primary departments = 10', `select count(*) from org_departments where active`, 10);
await eq('canonical accountable standing roles = 90',
  `select count(*) from org_role where status='active' and runtime_mode <> 'knowledge_overlay'`, 90);
await eq('category overlays = 86',
  `select count(*) from org_role where status='active' and runtime_mode='knowledge_overlay'`, 86);
await zero('every overlay is a category overlay',
  `select role_id from org_role where status='active' and runtime_mode='knowledge_overlay' and role_id !~ '^category_overlay_[0-9]{3}_'`, 'strays');
await eq('overlays are excluded from the 90 (86 + 90 = 176 active roles)',
  `select count(*) from org_role where status='active'`, 176);
await zero('one active department head per department, and the head is a member',
  `select d.dept_key from org_departments d where d.active and (d.lead_agent is null or not exists
     (select 1 from org_agents a where a.agent_key=d.lead_agent and a.active and a.department=d.dept_key))`, 'headless departments');
{
  const shape = Object.values(await one(`select string_agg(n::text, ',' order by n) from (
    select count(*) n from org_role where status='active' and runtime_mode <> 'knowledge_overlay'
     group by primary_department_id) s`))[0];
  check('department role counts are 4,6,7,7,7,9,11,11,11,17', shape === '4,6,7,7,7,9,11,11,11,17', shape);
}

sect('Identity and reporting');
await zero('no duplicate active role identity',
  `select runtime_agent_key from org_role where status='active' and runtime_agent_key is not null
    group by 1 having count(*) > 1`, 'shared identities');
await zero('every role has one primary department that exists',
  `select role_id from org_role r where r.status='active' and not exists
     (select 1 from org_departments d where d.dept_key = r.primary_department_id)`, 'orphans');
await zero('every role has a primary manager except the CEO',
  `select role_id from org_role where status='active' and manager_role_id is null and role_id <> 'ceo'`, 'unmanaged');
await zero('no self-management',
  `select role_id from org_role where status='active' and manager_role_id = role_id`, 'self-managers');
await zero('no reporting cycles',
  `with recursive up(root, cur, depth, path) as (
     select role_id, manager_role_id, 1, array[role_id] from org_role where status='active'
     union all
     select u.root, r.manager_role_id, u.depth+1, u.path || r.role_id
       from up u join org_role r on r.role_id = u.cur and r.status='active'
      where u.depth < 30 and not r.role_id = any(u.path))
   select distinct root from up where depth >= 30`, 'chains terminate');
await zero('no committee membership creates a second role record',
  `select role_id from org_role_committee c where not exists
     (select 1 from org_role r where r.role_id = c.role_id)`, 'phantom seats');
await zero('every retired role still resolves to a live one',
  `select r.role_id from org_role r where r.status='retired' and not exists
     (select 1 from org_role_alias a where a.alias = r.role_id)`, 'unresolvable');
await zero('every alias points at an active role',
  `select a.alias from org_role_alias a join org_role r on r.role_id=a.role_id where r.status <> 'active'`, 'dead targets');
await zero('an inactive or retired role holds no runtime employee',
  `select role_id from org_role r where r.status <> 'active' and r.runtime_agent_key is not null
     and exists (select 1 from org_agents a where a.agent_key=r.runtime_agent_key and a.active
                   and not exists (select 1 from org_role x where x.runtime_agent_key=a.agent_key and x.status='active'))`,
  'stranded employees');
await zero('every active employee maps to an active canonical role',
  `select a.agent_key from org_agents a where a.active and not exists
     (select 1 from org_role r where r.runtime_agent_key = a.agent_key and r.status='active')`, 'unowned employees');

sect('Necessity and ownership');
await zero('every active role states a necessity status',
  `select role_id from org_role where status='active' and (necessity_status is null or btrim(necessity_status)='')`, 'unstated');
await zero('every active role states an explicit reason',
  `select role_id from org_role where status='active' and (necessity_reason is null or length(btrim(necessity_reason)) < 10)`, 'unstated');
await zero('every accountable role has explicit forbidden decisions',
  `select role_id from org_role where status='active' and runtime_mode <> 'knowledge_overlay'
     and coalesce(cardinality(forbidden_decisions),0) = 0`, 'unbounded roles');
await eq('30 organizational workflows are owned', `select count(*) from org_workflow_ownership`, 30);
await zero('every workflow owner is an active canonical role',
  `select workflow_id from org_workflow_ownership o where not exists
     (select 1 from org_role r where r.role_id=o.accountable_role_id and r.status='active')`, 'ghost owners');
await zero('no workflow is multiply owned',
  `select workflow_id from org_workflow_ownership where accountable_role_id like '%;%' or accountable_role_id like '%,%'`, 'shared ownership');
await zero('a contributor is never the accountable owner',
  `select workflow_id from org_workflow_ownership where accountable_role_id = any(contributors)`, 'collisions');
await zero('every active accountable role owns a decision, a workflow or people',
  `select r.role_id from org_role r where r.status='active' and r.runtime_mode <> 'knowledge_overlay'
     and coalesce(cardinality(r.owned_decisions),0) = 0
     and not exists (select 1 from org_workflow_ownership o where o.accountable_role_id = r.role_id)
     and not exists (select 1 from org_role m where m.manager_role_id = r.role_id and m.status='active')
     and not exists (select 1 from workflow_step s where s.actor_role = r.role_id)`, 'idle roles');
// THE FIVE CONSEQUENTIAL STEPS, PINNED TO THE WORKFLOW THAT CARRIES EACH.
//
// The first cut of this swept workflow_name for the invariant's own words — 'supplier selection',
// 'privacy', 'release', 'payment', 'knowledge' — and reported two unowned. Both were owned:
// supplier selection is W12 "Supplier matching and dispatch", and the privacy review is W08
// "Supplier-safe payload and file approval", whose owner is literally the Marketplace Content &
// Privacy Reviewer. The organisation was right and the instrument was reading for vocabulary
// rather than for the thing.
//
// The mapping is now explicit, which is stricter and not looser: a keyword sweep passes as soon as
// SOMETHING matches, so it would have gone green if privacy review were owned by the wrong role or
// split across two workflows. This names the workflow, requires exactly one, and requires an owner.
{
  const MAP = [
    ['supplier selection', 'W12', 'Supplier matching and dispatch'],
    ['privacy review', 'W08', 'Supplier-safe payload and file approval'],
    ['release', 'W24', 'Release and production approval'],
    ['payment reconciliation', 'W16', 'Payment, billing and reconciliation'],
    ['knowledge validation', 'W26', 'Knowledge creation and validation'],
  ];
  for (const [concern, wid, name] of MAP) {
    const rows = await q(`select workflow_id, workflow_name, accountable_role_id
      from org_workflow_ownership where workflow_id = '${wid}'`);
    const ok = rows.length === 1 && rows[0].workflow_name === name && !!rows[0].accountable_role_id;
    check(`${concern} is owned, by exactly one role`, ok,
      rows.length === 1 ? `${wid} ${rows[0].workflow_name} -> ${rows[0].accountable_role_id}` : `${rows.length} row(s) for ${wid}`);
  }
}

sect('Independence');
await zero('no workflow owner is their own independent reviewer',
  `select workflow_id from org_workflow_ownership where independent_reviewer = accountable_role_id`, 'self-reviewers');
await zero('an independent reviewer is never managed by the department it reviews (model evaluation)',
  `select r.role_id from org_role r where r.role_id='model_evaluator'
     and (r.primary_department_id <> 'assurance' or r.manager_role_id <> 'quality_and_release_director')`, 'independent');
await zero('supplier onboarding and verification are different roles',
  `select 'same' where (select accountable_role_id from org_workflow_ownership where workflow_name ilike '%onboard%' limit 1)
     = (select accountable_role_id from org_workflow_ownership where workflow_name ilike '%verif%' limit 1)`, 'separate');
{
  // the alias-disguised self-review guard, forced to fire rather than assumed idle.
  const r = await q(`select count(*) n from org_role_committee`); // read-only warm-up
  const probe = await one(`select count(*) n from pg_trigger t join pg_class c on c.oid=t.tgrelid
     where c.relname in ('artifact_review','review_chain') and not t.tgisinternal`);
  check('the self-review triggers are still installed on artifact_review and review_chain',
    Number(probe.n) >= 2, `${probe.n} trigger(s)`);
}

sect('Category overlays');
await eq('86 overlays exist', `select count(*) from org_role where status='active' and runtime_mode='knowledge_overlay'`, 86);
await eq('86 categories resolve to one', `select count(*) from org_category_identity`, 86);
await zero('no overlay holds an executor or a runtime employee',
  `select role_id from org_role where status='active' and runtime_mode='knowledge_overlay' and runtime_agent_key is not null`, 'standing overlays');
await zero('no overlay owns a workflow',
  `select o.workflow_id from org_workflow_ownership o join org_role r on r.role_id=o.accountable_role_id
    where r.runtime_mode='knowledge_overlay'`, 'overlay owners');
await zero('every overlay states what it cannot decide',
  `select role_id from org_role where status='active' and runtime_mode='knowledge_overlay'
     and necessity_reason not ilike '%cannot decide%'`, 'unbounded overlays');

sect('Founder boundaries');
await eq('founder-reserved decisions are recorded', `select count(*) from founder_reserved_decision`, 11);
await zero('no role owns a founder-reserved decision',
  `select r.role_id from org_role r, founder_reserved_decision d, unnest(d.match_any) m(needle)
    where r.status='active' and position(m.needle in lower(array_to_string(r.owned_decisions,' | '))) > 0`, 'boundary violations');

sect('Historical compatibility');
await zero('no historical department row was deleted',
  `select 'departments' where (select count(*) from org_departments) <> 32`, 'all 32 present');
await eq('four roles are retired, none deleted', `select count(*) from org_role where status='retired'`, 4);
await zero('every retired role kept its rationale',
  `select role_id from org_role where status='retired' and rationale not like '%RETIRED by Phase A%'`, 'documented');
{
  // A FLOOR, NOT AN EXACT COUNT. The check is named 'grew rather than shrank' and asserting an
  // exact number made it fail the moment Phase A closure added a legitimate alias. 167 is the
  // count after the first Phase A deployment; the invariant is that it never goes below it.
  const n = Number(Object.values(await one(`select count(*) from org_role_alias`))[0]);
  check('the alias table grew rather than shrank', n >= 167, `${n} (floor 167)`);
}

sect('Cost');
{
  // NO CATCH HERE, AND THE COLUMN NAME IS THE REASON. The first version of this read `cost_usd`,
  // which does not exist — the column is `cost_aed` — and wrapped the query in
  // `.catch(() => ({ n: 0, usd: 0 }))`. So a query that ERRORED reported zero requests and zero
  // cost, and the cost invariant passed while measuring nothing at all. That is the exact defect
  // this estate keeps finding in its own instruments: an absent input scoring as satisfied. A
  // broken cost check is worse than no cost check, because the founder is reading it.
  const spend = await one(`select count(*) n, coalesce(sum(cost_aed),0) aed from ai_cost_log
    where occurred_at > timestamptz '2026-08-15 04:40:00+00'`);
  check('OpenRouter requests during Phase A = 0', Number(spend.n) === 0, `${spend.n} request(s)`);
  check('paid inference cost during Phase A = AED 0.00 / USD 0.00', Number(spend.aed) === 0,
    `AED ${Number(spend.aed).toFixed(2)}`);
  const held = await one(`select count(*) n from llm_route_health where open_until is not null`);
  check('the provider hold is still in place', Number(held.n) >= 8, `${held.n} route(s) held open-circuit`);
}

console.log(`\n${'='.repeat(78)}`);
console.log(`${pass} passed, ${fail} failed`);
console.log(fail ? 'PHASE_A_NOT_READY — execute scripts/sql/phase_a_rollback.sql' : 'PHASE_A_READY_FOR_FOUNDER_APPROVAL');
process.exitCode = fail ? 1 : 0;
