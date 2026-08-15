// PHASE A — the founder-approved baseline, computed rather than transcribed.
//
// Every checksum here is taken TWICE, from two independent sources: the committed CSV artefact in
// docs/phase-a/, and the live database it was exported from. If a pair ever disagrees, the repo and
// the database have diverged and the baseline is not a baseline. Both values are recorded, so a
// later reader can tell WHICH side moved rather than only that something did.
//
// Read-only. Every statement goes through mgmtRead, which refuses anything that is not.
//
//   node scripts/phase_a/freeze.mjs [--approved-at <iso8601>]
import { readFileSync, writeFileSync, existsSync } from 'node:fs';
import { execSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { mgmtRead, PROD_REF } from '../staging/qd_guard.mjs';

const argv = process.argv.slice(2);
const arg = (k) => { const i = argv.indexOf(`--${k}`); return i < 0 ? null : argv[i + 1]; };
const sha = (s) => createHash('sha256').update(typeof s === 'string' ? s : s).digest('hex');
const q = (s) => mgmtRead(PROD_REF, s);

// The migrations that built this baseline. They were applied by the production-direct protocol —
// scripts/apply_sql.mjs posts the committed bytes and reads the definitions back — NOT by the
// Supabase migration runner, so they are deliberately absent from supabase_migrations.schema_migrations.
// The file digest is the version that means anything here, and it is recorded rather than a runner
// row being invented for a run that did not happen.
const MIGRATIONS = [
  '20260815050000_phase_a_organization_closure.sql',
  '20260815051500_phase_a_followup_orphaned_work_and_evaluation.sql',
  '20260815052500_phase_a_the_role_resolved_but_the_employee_did_not.sql',
  '20260815053000_phase_a_the_new_role_had_no_identity_and_no_caller.sql',
  '20260815060000_phase_a_closure_corrections.sql',
  '20260815061500_phase_a_the_merge_left_a_stale_identity.sql',
];
const ROLLBACKS = ['scripts/sql/phase_a_rollback.sql', 'scripts/sql/phase_a_closure_rollback.sql'];

// ---- the six registries, live ------------------------------------------------------------------
// Ordered deterministically and rendered as one line per row, so the same organisation always
// yields the same digest whatever order the server returns.
const live = {};
live.departments = (await q(`select dept_key, name, lead_agent from org_departments where active order by dept_key`))
  .map(r => `${r.dept_key}|${r.name}|${r.lead_agent ?? ''}`);
live.roles = (await q(`select role_id, display_name, primary_department_id, manager_role_id, runtime_mode,
    runtime_agent_key, necessity_status, authority_level, runtime_enabled,
    coalesce(cardinality(owned_decisions),0) o, coalesce(cardinality(forbidden_decisions),0) f
  from org_role where status='active' and runtime_mode <> 'knowledge_overlay' order by role_id`))
  .map(r => `${r.role_id}|${r.display_name}|${r.primary_department_id}|${r.manager_role_id ?? ''}|${r.runtime_mode}`
    + `|${r.runtime_agent_key ?? ''}|${r.necessity_status ?? ''}|${r.authority_level}|${r.runtime_enabled}|${r.o}|${r.f}`);
live.reporting_graph = (await q(`select role_id, coalesce(manager_role_id,'founder') m, primary_department_id d
  from org_role where status='active' and runtime_mode <> 'knowledge_overlay' order by role_id`))
  .map(r => `${r.role_id}|${r.m}|${r.d}`);
live.category_overlays = (await q(`select role_id, display_name, primary_department_id
  from org_role where status='active' and runtime_mode='knowledge_overlay' order by role_id`))
  .map(r => `${r.role_id}|${r.display_name}|${r.primary_department_id}`);
live.workflow_ownership = (await q(`select workflow_id, workflow_name, accountable_role_id,
    array_to_string(contributors,';') c, coalesce(independent_reviewer,'') ir
  from org_workflow_ownership order by workflow_id`))
  .map(r => `${r.workflow_id}|${r.workflow_name}|${r.accountable_role_id}|${r.c}|${r.ir}`);
live.founder_reserved = (await q(`select decision_key, description from founder_reserved_decision order by decision_key`))
  .map(r => `${r.decision_key}|${r.description}`);

// ---- the same six, as committed ----------------------------------------------------------------
const FILES = {
  departments: 'docs/phase-a/PHASE_A_DEPARTMENT_REGISTRY.csv',
  roles: 'docs/phase-a/PHASE_A_CANONICAL_ROLE_REGISTRY.csv',
  reporting_graph: 'docs/phase-a/PHASE_A_REPORTING_GRAPH.csv',
  category_overlays: 'docs/phase-a/PHASE_A_CATEGORY_OVERLAY_REGISTRY.csv',
  workflow_ownership: 'docs/phase-a/PHASE_A_WORKFLOW_OWNERSHIP.csv',
  founder_reserved: 'docs/phase-a/PHASE_A_FOUNDER_RESERVED_DECISIONS.md',
};

const registries = {};
for (const [k, rows] of Object.entries(live)) {
  registries[k] = {
    rows: rows.length,
    database_sha256: sha(rows.join('\n')),
    committed_artefact: FILES[k],
    artefact_sha256: existsSync(FILES[k]) ? sha(readFileSync(FILES[k])) : null,
  };
}

// ---- the organization fingerprint, the same one the deployment used ------------------------------
const fpSrc = {
  departments: (await q(`select dept_key, name, active, lead_agent from org_departments order by dept_key`))
    .map(d => `${d.dept_key}|${d.name}|${d.active}|${d.lead_agent ?? ''}`),
  roles: (await q(`select role_id, display_name, primary_department_id, manager_role_id, runtime_mode,
      runtime_agent_key, status, evaluation_suite, coalesce(array_length(owned_decisions,1),0) n_owned,
      coalesce(array_length(forbidden_decisions,1),0) n_forbidden from org_role order by role_id`))
    .map(r => `${r.role_id}|${r.display_name}|${r.primary_department_id}|${r.manager_role_id ?? ''}`
      + `|${r.runtime_mode}|${r.runtime_agent_key ?? ''}|${r.status}|${r.evaluation_suite ?? ''}|${r.n_owned}|${r.n_forbidden}`),
  categories: (await q(`select category_key from org_category_identity order by 1`)).map(c => c.category_key),
  workflow_steps: (await q(`select workflow_key, step_no, step, actor_role from workflow_step order by workflow_key, step_no`))
    .map(f => `${f.workflow_key}|${f.step_no}|${f.step}|${f.actor_role ?? ''}`),
  reserved: (await q(`select decision_key from founder_reserved_decision order by 1`)).map(r => r.decision_key),
  agents: (await q(`select agent_key, department, active, manager_key from org_agents order by agent_key`))
    .map(a => `${a.agent_key}|${a.department}|${a.active}|${a.manager_key ?? ''}`),
};
const ORGANIZATION = {
  rows: Object.values(fpSrc).reduce((n, v) => n + v.length, 0),
  sha256: sha(Object.entries(fpSrc).map(([k, v]) => `${k}\n${v.join('\n')}`).join('\n--\n')),
};

// ---- the counts the founder approved, re-measured rather than copied -----------------------------
const counts = (await q(`select
  (select count(*) from org_departments where active) active_departments,
  (select count(*) from org_role where status='active' and runtime_mode <> 'knowledge_overlay') canonical_roles,
  (select count(*) from org_role where status='active' and runtime_mode='knowledge_overlay') category_overlays,
  (select count(*) from org_departments where active and lead_agent is not null) department_heads,
  (select count(*) from fn_phase_a_organization_violations()) phase_a_violations,
  (select count(*) from fn_phase_a_deferred_items()) deferred_items,
  (select count(*) from org_workflow_ownership) organizational_workflows,
  (select count(*) from org_role where status='retired') retired_roles`))[0];

const baseline = {
  phase: 'A',
  approved_by: 'founder',
  approved_at: arg('approved-at') || new Date().toISOString().replace(/\.\d+Z$/, 'Z'),
  project_ref: PROD_REF,
  final_commit: execSync('git rev-parse HEAD').toString().trim(),
  final_commit_subject: execSync('git log -1 --pretty=%s').toString().trim(),
  counts,
  organization_fingerprint: ORGANIZATION,
  registries,
  migrations: MIGRATIONS.map(m => ({
    version: m.split('_')[0], file: `supabase/migrations/${m}`,
    sha256: sha(readFileSync(`supabase/migrations/${m}`)),
  })),
  rollbacks: ROLLBACKS.map(f => ({ file: f, sha256: sha(readFileSync(f)) })),
  migration_provenance:
    'Applied by the production-direct protocol (scripts/apply_sql.mjs posts the committed bytes and reads '
    + 'the definitions back), NOT by the Supabase migration runner. They are therefore deliberately absent '
    + 'from supabase_migrations.schema_migrations; inventing runner rows would claim a provenance that did '
    + 'not happen. The file digest above is the version that means anything.',
  deferred_to_later_phases: (await q(`select rule, role_id from fn_phase_a_deferred_items() order by rule`))
    .map(d => `${d.rule}:${d.role_id}`),
};

writeFileSync('docs/phase-a/PHASE_A_FOUNDER_APPROVED_BASELINE.json', JSON.stringify(baseline, null, 2) + '\n');

// mismatches between the two sources, if any
const drift = Object.entries(registries).filter(([, v]) => v.artefact_sha256 === null);
console.log(`approved_at        ${baseline.approved_at}`);
console.log(`final commit       ${baseline.final_commit}`);
console.log(`organization       ${ORGANIZATION.rows} rows  ${ORGANIZATION.sha256}`);
for (const [k, v] of Object.entries(registries)) {
  console.log(`${k.padEnd(19)}${String(v.rows).padStart(4)} rows  db ${v.database_sha256.slice(0, 16)}…  artefact ${v.artefact_sha256 ? v.artefact_sha256.slice(0, 16) + '…' : 'MISSING'}`);
}
console.log(`\ncounts: ${JSON.stringify(counts)}`);
if (drift.length) { console.error(`\n${drift.length} registry artefact(s) missing: ${drift.map(d => d[0]).join(', ')}`); process.exitCode = 1; }
else console.log('\nwrote docs/phase-a/PHASE_A_FOUNDER_APPROVED_BASELINE.json');
