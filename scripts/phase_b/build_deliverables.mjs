// Emit the Phase B deliverable registries by READING THEM BACK OUT OF PRODUCTION.
//
//   node scripts/phase_b/build_deliverables.mjs
//
// The registries are not re-serialised from the package: they are selected from the deployed
// phase_b_* tables, so what the founder reads is what is live, not what a file intended.
import { writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { REPO } from './lib/package.mjs';
import { sql } from './lib/db.mjs';

const OUT = join(REPO, 'docs', 'phase-b');
const esc = v => {
  if (v === null || v === undefined) return '';
  const s = Array.isArray(v) ? v.join('; ') : String(v);
  return /[",\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
};
const writeCSV = (file, rows) => {
  if (!rows.length) throw new Error(`${file}: no rows read back from production`);
  const hdr = Object.keys(rows[0]);
  writeFileSync(join(OUT, file),
    [hdr.join(','), ...rows.map(r => hdr.map(h => esc(r[h])).join(','))].join('\n') + '\n', 'utf8');
  console.log(`${String(rows.length).padStart(5)}  ${file}`);
};

writeCSV('PHASE_B_WORKFLOW_REGISTRY.csv', await sql(`
  select workflow_id, workflow_name, domain, criticality, profile, primary_object,
         accountable_role_id, package_accountable_token,
         array_to_string(contributors, '; ') as contributors,
         independent_reviewer_role_id, start_event, required_end_state, founder_boundary,
         allowed_terminal_states, reopen_allowed, version, status, purpose
  from public.phase_b_workflow order by workflow_id`));

writeCSV('PHASE_B_WORKFLOW_STEP_REGISTRY.csv', await sql(`
  select workflow_id, step_no, step_id, step_name, step_type, accountable_role_id,
         package_accountable_token, actor_kind,
         array_to_string(contributors, '; ') as contributors, independent_reviewer_role_id,
         entry_condition, required_inputs, required_action, required_output, acceptance_criteria,
         closure_criteria, failure_or_block_state, founder_gate, idempotency_scope, repeatable,
         is_closure_step, next_step_if_pass, next_step_if_fail, success_workflow_state,
         failure_workflow_state, notes
  from public.phase_b_workflow_step order by workflow_id, step_no`));

writeCSV('PHASE_B_WORKFLOW_STATE_MODEL.csv', await sql(`
  select 'workflow' as model, state, definition, terminal from public.phase_b_workflow_state
  union all
  select 'step', state, definition, terminal from public.phase_b_step_state
  order by model desc, state`));

writeCSV('PHASE_B_WORKFLOW_TRANSITIONS.csv', await sql(`
  select 'workflow' as model, from_state, to_state, condition from public.phase_b_workflow_transition
  union all
  select 'step', from_state, to_state, condition from public.phase_b_step_transition
  order by model desc, from_state, to_state`));

writeCSV('PHASE_B_HANDOFF_REGISTRY.csv', await sql(`
  select handoff_id, workflow_id, from_step_id, to_step_id, sending_role_id, receiving_role_id,
         sending_department_id, receiving_department_id, handoff_type, trigger, required_packet,
         receiving_acceptance_criteria, rejection_condition, return_owner_role_id,
         closure_condition, sla_policy_id
  from public.phase_b_handoff order by handoff_id`));

writeCSV('PHASE_B_BUSINESS_OBJECT_REGISTRY.csv', await sql(`
  select object_id, governing_workflow_id, accountable_role_id, definition, record_policy, mutation_rule
  from public.phase_b_business_object order by object_id`));

writeCSV('PHASE_B_BUSINESS_RULE_REGISTRY.csv', await sql(`
  select rule_id, rule_name, rule_text, workflow_scope, rule_type
  from public.phase_b_business_rule order by rule_id`));

writeCSV('PHASE_B_GATE_REGISTRY.csv', await sql(`
  select gate_id, gate_name, workflow_scope, required_evidence, pass_result, fail_result, gate_type
  from public.phase_b_gate order by gate_id`));

writeCSV('PHASE_B_EXCEPTION_ESCALATION_MATRIX.csv', await sql(`
  select exception_id, exception_name, workflow_scope, detection_owner_role_id,
         escalation_owner_role_id, required_response, closure_condition
  from public.phase_b_exception order by exception_id`));

writeCSV('PHASE_B_SLA_POLICY.csv', await sql(`
  select sla_policy_id, name, workflow_scope, target, classification, breach_action
  from public.phase_b_sla_policy order by sla_policy_id`));

writeCSV('PHASE_B_EVENT_REGISTRY.csv', await sql(`
  select event_id, event_name, workflow_id, emitted_by, trigger, primary_consumer_role_id,
         payload_contract, dedupe_key
  from public.phase_b_event order by event_id`));

writeCSV('PHASE_B_FOUNDER_BOUNDARY_MAPPING.csv', await sql(`
  select boundary_id, boundary_name, definition, workflow_scope, decision_owner, phase_b_enforcement
  from public.phase_b_founder_boundary order by boundary_id`));
