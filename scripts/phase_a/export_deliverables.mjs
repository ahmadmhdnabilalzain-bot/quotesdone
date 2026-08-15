// PHASE A — the deliverable registries, exported FROM THE DEPLOYED DATABASE.
//
// Deliberately not a copy of the package. The package is the target; these say what production
// actually holds after the migration, with the canonical ids that are really in use. Where the two
// differ on an ID the package id is carried in the crosswalk column, so nothing diverges silently.
//
//   node scripts/phase_a/export_deliverables.mjs
import { writeFileSync, mkdirSync, readFileSync } from 'node:fs';
import { mgmtRead, PROD_REF } from '../staging/qd_guard.mjs';

const q = (s) => mgmtRead(PROD_REF, s);
const cell = (v) => {
  const s = v === null || v === undefined ? '' : Array.isArray(v) ? v.join('; ') : String(v);
  return /[",\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
};
const csv = (rows, cols) => [cols.join(','), ...rows.map(r => cols.map(c => cell(r[c])).join(','))].join('\n') + '\n';

mkdirSync('docs/phase-a', { recursive: true });
const cross = JSON.parse(readFileSync('docs/phase-a/phase_a_crosswalk.json', 'utf8'));
const pkgIdFor = new Map(cross.filter(c => c.live).map(c => [c.live, c.target]));

const depts = await q(`select d.dept_key as department_id, d.name as department_name, d.lead_agent as head_agent_key,
    (select r.role_id from org_role r where r.runtime_agent_key = d.lead_agent and r.status='active') as head_role_id,
    (select count(*) from org_role r where r.primary_department_id = d.dept_key and r.status='active'
       and r.runtime_mode <> 'knowledge_overlay') as accountable_roles, d.active
  from org_departments d where d.active order by d.dept_key`);
writeFileSync('docs/phase-a/PHASE_A_DEPARTMENT_REGISTRY.csv',
  csv(depts, ['department_id', 'department_name', 'head_role_id', 'head_agent_key', 'accountable_roles', 'active']));

const roles = await q(`select role_id as canonical_role_id, display_name as display_title,
    primary_department_id as department_id, manager_role_id as primary_manager_role_id,
    runtime_mode, runtime_agent_key, necessity_status, necessity_reason as organizational_purpose,
    array_to_string(owned_decisions, '; ') as decisions_owned,
    array_to_string(forbidden_decisions, '; ') as decisions_forbidden,
    authority_level, evaluation_suite, status
  from org_role where status='active' and runtime_mode <> 'knowledge_overlay' order by primary_department_id, role_id`);
for (const r of roles) r.package_role_id = pkgIdFor.get(r.canonical_role_id) || r.canonical_role_id;
writeFileSync('docs/phase-a/PHASE_A_CANONICAL_ROLE_REGISTRY.csv', csv(roles,
  ['canonical_role_id', 'package_role_id', 'display_title', 'department_id', 'primary_manager_role_id',
    'runtime_mode', 'runtime_agent_key', 'necessity_status', 'organizational_purpose', 'decisions_owned',
    'decisions_forbidden', 'authority_level', 'evaluation_suite', 'status']));

const graph = await q(`select role_id, coalesce(manager_role_id, 'founder') as manager_role_id,
    primary_department_id as department_id, 'PRIMARY_REPORTING' as relationship
  from org_role where status='active' and runtime_mode <> 'knowledge_overlay' order by role_id`);
writeFileSync('docs/phase-a/PHASE_A_REPORTING_GRAPH.csv', csv(graph, ['role_id', 'manager_role_id', 'department_id', 'relationship']));

const comm = await q(`select c.committee_key, c.name as committee, rc.role_id, rc.seat as membership,
    r.display_name as role_title
  from org_role_committee rc join org_committee c on c.committee_key = rc.committee_key
  join org_role r on r.role_id = rc.role_id
  order by c.committee_key, case rc.seat when 'chair' then 0 when 'secretary' then 1 when 'member' then 2
    when 'standing_adviser' then 3 else 4 end, rc.role_id`);
writeFileSync('docs/phase-a/PHASE_A_EXECUTIVE_COMMITTEE.csv', csv(comm, ['committee_key', 'committee', 'role_id', 'role_title', 'membership']));

const ov = await q(`select r.role_id as overlay_role_id, r.display_name as overlay_title,
    r.primary_department_id as operational_department_id, r.necessity_status, r.necessity_reason,
    r.runtime_agent_key, r.status
  from org_role r where r.status='active' and r.runtime_mode='knowledge_overlay' order by r.role_id`);
writeFileSync('docs/phase-a/PHASE_A_CATEGORY_OVERLAY_REGISTRY.csv',
  csv(ov, ['overlay_role_id', 'overlay_title', 'operational_department_id', 'necessity_status', 'necessity_reason', 'runtime_agent_key', 'status']));

const flows = await q(`select workflow_id, workflow_name, accountable_role_id,
    array_to_string(contributors, '; ') as contributors, independent_reviewer,
    start_event, required_end_state, founder_boundary
  from org_workflow_ownership order by workflow_id`);
writeFileSync('docs/phase-a/PHASE_A_WORKFLOW_OWNERSHIP.csv', csv(flows,
  ['workflow_id', 'workflow_name', 'accountable_role_id', 'contributors', 'independent_reviewer',
    'start_event', 'required_end_state', 'founder_boundary']));

const reserved = await q(`select decision_key, description from founder_reserved_decision order by decision_key`);

console.log(`departments ${depts.length} · roles ${roles.length} · reporting ${graph.length} · committee seats ${comm.length}`);
console.log(`overlays ${ov.length} · workflows ${flows.length} · founder-reserved ${reserved.length}`);
writeFileSync('docs/phase-a/phase_a_reserved.json', JSON.stringify(reserved, null, 2) + '\n');
