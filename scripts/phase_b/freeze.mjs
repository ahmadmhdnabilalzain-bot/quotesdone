// Record the founder-approved Phase B baseline.
//
//   node scripts/phase_b/freeze.mjs            # print what would be recorded
//   node scripts/phase_b/freeze.mjs --emit     # also write scripts/sql/phase_b_12_founder_approved_baseline.sql
//
// Every registry checksum is taken TWICE, from two independent sources: the committed CSV in
// docs/phase-b/, and the live database it was exported from.  If a pair ever disagrees, the
// repository and the database have diverged and the baseline is not a baseline.  Both values are
// recorded, so a later reader can tell which side moved.  This is the recipe scripts/phase_a/
// freeze.mjs used, kept identical on purpose.
//
// The FROZEN STRUCTURE digest is not computed here at all — it is read from
// public.fn_phase_b_structure_digest(), the same function the freeze guard calls.  Two
// implementations of one digest is two chances to disagree; there is one.
import { readFileSync, existsSync, writeFileSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { join } from 'node:path';
import { REPO } from './lib/package.mjs';
import { sql, PROJECT_REF } from './lib/db.mjs';

const EMIT = process.argv.includes('--emit');
const sha = s => createHash('sha256').update(s).digest('hex');
const fileSha = p => existsSync(join(REPO, p)) ? sha(readFileSync(join(REPO, p))) : null;
const q = s => `'${String(s).replace(/'/g, "''")}'`;

// ---- the migration set, in the order it was applied to production -------------------------
const MIGRATIONS = [
  'scripts/sql/phase_b_01_workflow_registry_schema.sql',
  'scripts/sql/phase_b_02_identity_aliases.sql',
  'scripts/sql/phase_b_03_registry_core.sql',
  'scripts/sql/phase_b_04_steps.sql',
  'scripts/sql/phase_b_05_handoffs_and_exceptions.sql',
  'scripts/sql/phase_b_06_events.sql',
  'scripts/sql/phase_b_07_crosswalk.sql',
  'scripts/sql/phase_b_08_validators.sql',
  'scripts/sql/phase_b_09_pin_function_search_path.sql',
  'scripts/sql/phase_b_10_gate_attachment.sql',
  'scripts/sql/phase_b_11_baseline_functions.sql',
];
const ROLLBACKS = ['scripts/sql/phase_b_workflow_closure_rollback.sql'];

// ---- the registries, live, one line per row -------------------------------------------------
const live = {};
live.workflow_registry = (await sql(`select workflow_id, workflow_name, domain, criticality, profile,
    primary_object, accountable_role_id, coalesce(independent_reviewer_role_id,'') ir,
    array_to_string(contributors,';') c, start_event, required_end_state, founder_boundary
  from public.phase_b_workflow order by workflow_id`))
  .map(r => [r.workflow_id, r.workflow_name, r.domain, r.criticality, r.profile, r.primary_object,
    r.accountable_role_id, r.ir, r.c, r.start_event, r.required_end_state, r.founder_boundary].join('|'));

live.step_registry = (await sql(`select step_id, workflow_id, step_no, step_name, step_type,
    accountable_role_id, coalesce(independent_reviewer_role_id,'') ir, actor_kind,
    array_to_string(contributors,';') c, next_step_if_pass, next_step_if_fail,
    success_workflow_state, failure_workflow_state, is_closure_step, coalesce(founder_gate,'') fg,
    idempotency_scope
  from public.phase_b_workflow_step order by step_id`))
  .map(r => [r.step_id, r.workflow_id, r.step_no, r.step_name, r.step_type, r.accountable_role_id,
    r.ir, r.actor_kind, r.c, r.next_step_if_pass, r.next_step_if_fail, r.success_workflow_state,
    r.failure_workflow_state, r.is_closure_step, r.fg, r.idempotency_scope].join('|'));

live.handoff_registry = (await sql(`select handoff_id, workflow_id, from_step_id, to_step_id,
    sending_role_id, receiving_role_id, sending_department_id, receiving_department_id,
    handoff_type, return_owner_role_id, sla_policy_id
  from public.phase_b_handoff order by handoff_id`))
  .map(r => [r.handoff_id, r.workflow_id, r.from_step_id, r.to_step_id, r.sending_role_id,
    r.receiving_role_id, r.sending_department_id, r.receiving_department_id, r.handoff_type,
    r.return_owner_role_id, r.sla_policy_id].join('|'));

live.object_registry = (await sql(`select object_id, governing_workflow_id, accountable_role_id,
    record_policy, mutation_rule from public.phase_b_business_object order by object_id`))
  .map(r => [r.object_id, r.governing_workflow_id, r.accountable_role_id, r.record_policy, r.mutation_rule].join('|'));

live.rule_registry = (await sql(`select rule_id, rule_name, workflow_scope, rule_type, rule_text
  from public.phase_b_business_rule order by rule_id`))
  .map(r => [r.rule_id, r.rule_name, r.workflow_scope, r.rule_type, r.rule_text].join('|'));

live.gate_registry = (await sql(`select gate_id, gate_name, workflow_scope, gate_type,
    required_evidence, pass_result, fail_result from public.phase_b_gate order by gate_id`))
  .map(r => [r.gate_id, r.gate_name, r.workflow_scope, r.gate_type, r.required_evidence,
    r.pass_result, r.fail_result].join('|'));

live.exception_registry = (await sql(`select exception_id, exception_name, workflow_scope,
    detection_owner_role_id, escalation_owner_role_id, required_response, closure_condition
  from public.phase_b_exception order by exception_id`))
  .map(r => [r.exception_id, r.exception_name, r.workflow_scope, r.detection_owner_role_id,
    r.escalation_owner_role_id, r.required_response, r.closure_condition].join('|'));

live.sla_registry = (await sql(`select sla_policy_id, name, workflow_scope, target, classification,
    breach_action from public.phase_b_sla_policy order by sla_policy_id`))
  .map(r => [r.sla_policy_id, r.name, r.workflow_scope, r.target, r.classification, r.breach_action].join('|'));

live.event_registry = (await sql(`select event_id, event_name, workflow_id, emitted_by,
    primary_consumer_role_id, payload_contract, dedupe_key from public.phase_b_event order by event_id`))
  .map(r => [r.event_id, r.event_name, r.workflow_id, r.emitted_by, r.primary_consumer_role_id,
    r.payload_contract, r.dedupe_key].join('|'));

live.state_machine = (await sql(`
  select 'A'||state k, 'wf_state|'||state||'|'||terminal::text v from public.phase_b_workflow_state
  union all select 'B'||state, 'step_state|'||state||'|'||terminal::text from public.phase_b_step_state
  union all select 'C'||from_state||'>'||to_state, 'wf_transition|'||from_state||'|'||to_state||'|'||condition
    from public.phase_b_workflow_transition
  union all select 'D'||from_state||'>'||to_state, 'step_transition|'||from_state||'|'||to_state||'|'||condition
    from public.phase_b_step_transition
  order by k`)).map(r => r.v);

live.crosswalk = (await sql(`select current_artifact_type, current_artifact_name, target_workflow_id,
    target_classification from public.phase_b_crosswalk
  order by current_artifact_type, current_artifact_name`))
  .map(r => [r.current_artifact_type, r.current_artifact_name, r.target_workflow_id, r.target_classification].join('|'));

live.founder_boundary = (await sql(`select boundary_id, boundary_name, workflow_scope, decision_owner,
    phase_b_enforcement, definition from public.phase_b_founder_boundary order by boundary_id`))
  .map(r => [r.boundary_id, r.boundary_name, r.workflow_scope, r.decision_owner, r.phase_b_enforcement,
    r.definition].join('|'));

live.effective_errata = (await sql(`select package_file, record_id, defect, correction::text
  from public.phase_b_package_erratum order by package_file, record_id`))
  .map(r => [r.package_file, r.record_id, r.defect, r.correction].join('|'));

// ---- the committed artefact for each -------------------------------------------------------
const FILES = {
  workflow_registry:  'docs/phase-b/PHASE_B_WORKFLOW_REGISTRY.csv',
  step_registry:      'docs/phase-b/PHASE_B_WORKFLOW_STEP_REGISTRY.csv',
  handoff_registry:   'docs/phase-b/PHASE_B_HANDOFF_REGISTRY.csv',
  object_registry:    'docs/phase-b/PHASE_B_BUSINESS_OBJECT_REGISTRY.csv',
  rule_registry:      'docs/phase-b/PHASE_B_BUSINESS_RULE_REGISTRY.csv',
  gate_registry:      'docs/phase-b/PHASE_B_GATE_REGISTRY.csv',
  exception_registry: 'docs/phase-b/PHASE_B_EXCEPTION_ESCALATION_MATRIX.csv',
  sla_registry:       'docs/phase-b/PHASE_B_SLA_POLICY.csv',
  event_registry:     'docs/phase-b/PHASE_B_EVENT_REGISTRY.csv',
  state_machine:      'docs/phase-b/PHASE_B_WORKFLOW_STATE_MODEL.csv',
  crosswalk:          'docs/phase-b/PHASE_B_CURRENT_TO_TARGET_WORKFLOW_CROSSWALK.csv',
  founder_boundary:   'docs/phase-b/PHASE_B_FOUNDER_BOUNDARY_MAPPING.csv',
  // effective_errata lives only in the database and in lib/identity.mjs; there is no CSV, and
  // recording a null here is honest where inventing a file path would not be.
  effective_errata:   null,
};

const registries = {};
for (const [k, rows] of Object.entries(live)) {
  registries[k] = {
    rows: rows.length,
    database: sha(rows.join('\n')),
    artefact: FILES[k] ? fileSha(FILES[k]) : null,
    committed_artefact: FILES[k],
  };
}
// the state machine spans two CSVs; fold the transitions file into its artefact digest
if (FILES.state_machine) {
  registries.state_machine.artefact = sha(
    readFileSync(join(REPO, 'docs/phase-b/PHASE_B_WORKFLOW_STATE_MODEL.csv')).toString()
    + readFileSync(join(REPO, 'docs/phase-b/PHASE_B_WORKFLOW_TRANSITIONS.csv')).toString());
  registries.state_machine.committed_artefact =
    'docs/phase-b/PHASE_B_WORKFLOW_STATE_MODEL.csv + PHASE_B_WORKFLOW_TRANSITIONS.csv';
}

// ---- the frozen structure, read from the one SQL definition --------------------------------
const structureRows = await sql('select * from public.fn_phase_b_structure_digest()');
const structure = Object.fromEntries(structureRows.map(r =>
  [r.subject, { rows: Number(r.rows), database: r.sha256 }]));

// ---- production organization / workflow fingerprint ----------------------------------------
const fp = (await sql(`select
  (select count(*) from public.org_departments where active)                                 d_active,
  (select count(*) from public.org_role where status='active' and runtime_mode <> 'knowledge_overlay') roles,
  (select count(*) from public.org_role where status='active' and runtime_mode = 'knowledge_overlay')  overlays,
  (select count(*) from public.org_workflow_ownership)                                       org_wf,
  (select count(*) from public.fn_phase_a_baseline_drift())                                  pa_drift,
  (select count(*) from public.fn_phase_a_organization_violations())                          pa_viol,
  (select count(*) from public.phase_b_workflow)                                             wf,
  (select count(*) from public.phase_b_workflow_step)                                        steps,
  (select count(*) from public.phase_b_handoff)                                              handoffs,
  (select count(*) from public.phase_b_crosswalk)                                            crosswalk,
  (select count(*) from cron.job)                                                            cron_jobs,
  (select count(*) from cron.job where active)                                               cron_active,
  (select count(*) from public.llm_route_health where open_until > now())                    routes_held`))[0];
const fingerprint = { values: fp, sha256: sha(JSON.stringify(fp)) };

// ---- counts, exactly as the founder listed them --------------------------------------------
const counts = {
  workflows: Number(fp.wf),
  steps: Number(fp.steps),
  handoffs: Number(fp.handoffs),
  cross_department_handoffs: Number((await sql(
    `select count(*) c from public.phase_b_handoff where handoff_type='cross_department'`))[0].c),
  business_objects: registries.object_registry.rows,
  business_rules: registries.rule_registry.rows,
  gates: registries.gate_registry.rows,
  exceptions: registries.exception_registry.rows,
  sla_policies: registries.sla_registry.rows,
  events: registries.event_registry.rows,
  workflow_states: 14,
  workflow_transitions: 35,
  step_states: 11,
  step_transitions: 19,
  founder_boundaries: registries.founder_boundary.rows,
  crosswalk_classifications: Number(fp.crosswalk),
  canonical_roles_represented: 90,
  departments_represented: 10,
  category_overlays_governed: 86,
  effective_errata_resolved: (await sql(
    'select count(*) c from public.fn_phase_b_effective_errata() where resolved')).at(0).c,
  unresolved_phase_b_errata: (await sql(
    'select count(*) c from public.fn_phase_b_effective_errata() where not resolved')).at(0).c,
};

const commit = execFileSync('git', ['rev-parse', 'HEAD'], { cwd: REPO }).toString().trim();
const APPROVED_AT = '2026-08-15T08:45:00Z';   // founder approval, stated in this session

// ---- report ---------------------------------------------------------------------------------
console.log(`commit      ${commit}`);
console.log(`project     ${PROJECT_REF}`);
console.log(`fingerprint ${fingerprint.sha256}`);
console.log('\nregistry                 rows   database          artefact');
const mismatches = [];
for (const [k, v] of Object.entries(registries)) {
  console.log(`${k.padEnd(22)}${String(v.rows).padStart(6)}   ${v.database.slice(0, 16)}  `
    + (v.artefact ? v.artefact.slice(0, 16) : '(no committed CSV)'));
  if (v.committed_artefact && !v.artefact) mismatches.push(`${k}: artefact missing`);
}
console.log('\nfrozen structure         rows   digest');
for (const [k, v] of Object.entries(structure)) {
  console.log(`${k.padEnd(22)}${String(v.rows).padStart(6)}   ${v.database.slice(0, 16)}`);
}
console.log(`\nerrata resolved ${counts.effective_errata_resolved}/3, unresolved ${counts.unresolved_phase_b_errata}`);
if (String(counts.unresolved_phase_b_errata) !== '0') {
  console.error('REFUSING: an erratum is unresolved; the baseline must not be recorded.');
  process.exit(1);
}
if (mismatches.length) { console.error('REFUSING:\n  ' + mismatches.join('\n  ')); process.exit(1); }

if (!EMIT) { console.log('\n(dry run — pass --emit to write the migration)'); process.exit(0); }

// ---- emit the baseline migration ------------------------------------------------------------
const baseline = {
  counts,
  registry_sha256: { ...registries, structure },
  fingerprint_sha256: fingerprint.sha256,
  fingerprint_values: fingerprint.values,
  migrations: MIGRATIONS.map(f => ({ file: f, sha256: fileSha(f) })),
  rollbacks: ROLLBACKS.map(f => ({ file: f, sha256: fileSha(f) })),
  approval: {
    scope: ['workflow purpose', 'sequence', 'ownership', 'handoffs', 'inputs and outputs',
      'business states', 'transitions', 'rules', 'gates', 'exceptions', 'SLAs', 'founder boundaries'],
    explicitly_not_claimed:
      'This approval does NOT claim the current application runtime already executes all workflows '
      + 'correctly. The runtime gaps are recorded in public.phase_b_phase_c_wiring_gap.',
  },
  note: 'Applied by the production-direct protocol (scripts/apply_sql.mjs posts the committed bytes '
    + 'and reads the definitions back), NOT by the Supabase migration runner, so these versions are '
    + 'deliberately absent from supabase_migrations.schema_migrations. The file digest is the version '
    + 'that means anything. Every registry digest is recorded twice, from the database and from the '
    + 'committed CSV; if a pair disagrees the repository and the database have diverged.',
};

const GAPS = [
  ['12 of 19 current runtime workflow definitions have zero runs',
   '12 of 19 workflow_key values in public.workflow have no row in public.workflow_run',
   "select w.workflow_key, count(r.*) from public.workflow w left join public.workflow_run r on r.workflow_key = w.workflow_key group by 1 having count(r.*) = 0"],
  ['rfq_handling has zero complete runtime journeys',
   'rfq_handling has 18 steps, all gated, 20 assigned employees and 0 runs',
   "select count(*) from public.workflow_run where workflow_key = 'rfq_handling'"],
  ['407 cron and Edge Function execution paths lack canonical accountability',
   '205 cron jobs execute under pg_cron and 202 edge functions under the service role; none carries an accountable canonical role',
   "select count(*) from public.phase_b_crosswalk where current_owner_or_actor like '%no accountable role attached%'"],
  ['64 Edge Functions have no known caller or external entry point',
   '87 of 202 have no caller in repo, database or cron; 23 of those serve an external surface, leaving 64',
   'node scripts/phase_b/edge_callers.mjs && node scripts/phase_b/classify_entry_points.mjs'],
  ['W21 has no runtime implementation',
   'no cron job, edge function, runtime workflow definition or frontend route maps to W21',
   "select * from public.phase_b_crosswalk where current_artifact_type = 'none'"],
  ['eleven canonical workflows have no runtime-step implementation',
   'measured against public.workflow_step, which holds ordered steps for 19 runtime workflows only',
   'node scripts/phase_b/build_crosswalk.mjs'],
  ['four deployment-parity items remain unverifiable',
   'auth_api, dev_login, qa_login and src_io yield no distinctive signature, so they are UNVERIFIED rather than verified',
   'node scripts/verify_deploy_parity.mjs --all'],
];

const sqlText = `-- Phase B — the founder-approved baseline.
--
-- Recorded 15 Aug 2026 on the founder's explicit approval of Phase B as the final QuotesDone
-- business-workflow architecture.  Generated by scripts/phase_b/freeze.mjs; do not hand-edit.
--
-- The approval covers workflow purpose, sequence, ownership, handoffs, inputs and outputs,
-- business states, transitions, rules, gates, exceptions, SLAs and founder boundaries.
--
-- It does NOT claim the current application runtime already executes all workflows correctly.
-- The founder said so in the approval, and the seven runtime gaps he named are recorded below
-- as Phase C work rather than as Phase B defects.

set lock_timeout = '8s';
set statement_timeout = '600s';

insert into public.org_phase_baseline
  (phase, approved_by, approved_at, project_ref, final_commit, counts, organization_sha256,
   registry_sha256, migrations, rollbacks, deferred, note, recorded_at)
values (
  'B', 'founder', ${q(APPROVED_AT)}, ${q(PROJECT_REF)}, ${q(commit)},
  ${q(JSON.stringify(baseline.counts))}::jsonb,
  ${q(baseline.fingerprint_sha256)},
  ${q(JSON.stringify(baseline.registry_sha256))}::jsonb,
  ${q(JSON.stringify(baseline.migrations))}::jsonb,
  ${q(JSON.stringify(baseline.rollbacks))}::jsonb,
  ${q(JSON.stringify(GAPS.map(g => g[0])))}::jsonb,
  ${q(baseline.note + ' ' + baseline.approval.explicitly_not_claimed)},
  now()
)
on conflict (phase) do update set
  approved_by = excluded.approved_by, approved_at = excluded.approved_at,
  project_ref = excluded.project_ref, final_commit = excluded.final_commit,
  counts = excluded.counts, organization_sha256 = excluded.organization_sha256,
  registry_sha256 = excluded.registry_sha256, migrations = excluded.migrations,
  rollbacks = excluded.rollbacks, deferred = excluded.deferred, note = excluded.note,
  recorded_at = now();

-- ---- the seven runtime gaps the founder accepted as Phase C work ----
insert into public.phase_b_phase_c_wiring_gap (gap, measurement, evidence_command) values
${GAPS.map(g => `  (${q(g[0])}, ${q(g[1])}, ${q(g[2])})`).join(',\n')}
on conflict (gap) do update set
  measurement = excluded.measurement, evidence_command = excluded.evidence_command;

-- Verify by reading it back: the baseline must exist and must not already have drifted.
do $$
declare v_drift bigint; v_gaps bigint; v_errata bigint;
begin
  if not exists (select 1 from public.org_phase_baseline where phase = 'B') then
    raise exception 'phase_b: the baseline row was not recorded';
  end if;
  select count(*) into v_drift  from public.fn_phase_b_baseline_drift();
  select count(*) into v_gaps   from public.phase_b_phase_c_wiring_gap;
  select count(*) into v_errata from public.fn_phase_b_effective_errata() where not resolved;
  if v_drift <> 0 then
    raise exception 'phase_b: baseline recorded but already drifted, % row(s)', v_drift;
  end if;
  if v_gaps <> ${GAPS.length} then
    raise exception 'phase_b: expected ${GAPS.length} Phase C wiring gaps, found %', v_gaps;
  end if;
  if v_errata <> 0 then
    raise exception 'phase_b: % erratum condition(s) unresolved at freeze time', v_errata;
  end if;
  raise notice 'phase_b baseline recorded: drift 0, wiring gaps %, unresolved errata 0', v_gaps;
end $$;
`;

const out = join(REPO, 'scripts', 'sql', 'phase_b_12_founder_approved_baseline.sql');
writeFileSync(out, sqlText, 'utf8');
console.log(`\nwrote ${out.slice(REPO.length + 1)}  (${(sqlText.length / 1024).toFixed(0)} KB)`);
