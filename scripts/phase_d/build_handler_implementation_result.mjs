// PHASE D DELIVERABLE — PHASE_D_HANDLER_IMPLEMENTATION_RESULT.csv
//
// One row per frozen Phase B step, built FROM THE LIVE REGISTRIES and never from the package. The
// script exits 1 rather than writing fewer than 257 rows, so a partial export cannot be mistaken
// for a complete one — the same rule build_d0_crosswalk.mjs follows and for the same reason.
//
//   node scripts/phase_d/build_handler_implementation_result.mjs
//
// The columns are the ones the Phase D brief names for every step: expected effect type, effect
// object, effect service, actual caller, result reference, trace reference, completion condition,
// plus implementation_depth, which answers "what does this handler actually do today" — a different
// question from phase_d_status, which describes the handler CLASS and was being read as if it
// answered both.
import { writeFileSync, mkdirSync } from 'node:fs';
import { mgmtRead, PROD_REF } from '../staging/qd_guard.mjs';

const SQL = `
select
  e.step_id, e.workflow_id, s.step_no, s.step_name, e.step_type,
  b.handler_id, b.handler_version, b.handler_class, b.handler_routine,
  e.implementation_depth, e.expected_effect_type, e.effect_object_id, e.object_resolution,
  e.effect_relation, e.effect_service, e.effect_operation,
  e.actual_caller, e.expected_state_transition, e.completion_condition,
  e.result_reference, e.trace_reference,
  b.input_schema_id, b.output_schema_id,
  array_to_string(b.rule_ids, ';')  as rules_in_scope,
  array_to_string(b.gate_ids, ';')  as gates_in_scope,
  array_to_string(b.business_object_reads, ';')  as business_object_reads,
  array_to_string(b.business_object_writes, ';') as business_object_writes,
  b.business_write_wired,
  b.idempotency_template, b.concurrency_lock_scope,
  array_to_string(b.failure_code_contract, ';') as failure_code_contract,
  b.capability_dependency, b.capability_evidence, b.provider_dependency,
  b.external_effect_policy, b.founder_gate, b.phase_d_status,
  ob.relation_kind as effect_relation_kind,
  ob.policy_family as effect_policy_family,
  coalesce(wm.operation, case when ob.relation_kind = 'PHASE_D_OBJECT_VIEW'
                              then 'PHASE_D_STORE' else '' end) as write_map_operation,
  coalesce(wm.quarantine_note, '') as quarantine_note,
  coalesce((select count(*)::text from public.phase_d_effect_ledger l
             where l.step_id = e.step_id), '0') as effects_produced,
  e.effect_evidence
from public.phase_d_step_effect e
join public.phase_b_workflow_step s on s.step_id = e.step_id
join public.phase_d_handler_binding b on b.step_id = e.step_id
left join public.phase_d_business_object_binding ob on ob.object_id = e.effect_object_id
left join public.phase_d_object_write_map wm on wm.object_id = e.effect_object_id
order by e.workflow_id, s.step_no
`;

const rows = await mgmtRead(PROD_REF, SQL);
if (!Array.isArray(rows) || rows.length !== 257) {
  console.error(`refusing to write: got ${Array.isArray(rows) ? rows.length : 'no'} row(s), expected 257`);
  process.exit(1);
}

const cols = Object.keys(rows[0]);
const cell = (v) => {
  if (v === null || v === undefined) return '';
  const s = String(v);
  return /[",\n\r]/.test(s) ? '"' + s.replace(/"/g, '""') + '"' : s;
};
const csv = [cols.join(','), ...rows.map(r => cols.map(c => cell(r[c])).join(','))].join('\n') + '\n';

mkdirSync('docs/phase-d', { recursive: true });
writeFileSync('docs/phase-d/PHASE_D_HANDLER_IMPLEMENTATION_RESULT.csv', csv);

const by = (k) => rows.reduce((a, r) => (a[r[k]] = (a[r[k]] || 0) + 1, a), {});
console.log(`wrote docs/phase-d/PHASE_D_HANDLER_IMPLEMENTATION_RESULT.csv — ${rows.length} rows × ${cols.length} columns`);
console.log('implementation_depth   ', JSON.stringify(by('implementation_depth')));
console.log('expected_effect_type   ', JSON.stringify(by('expected_effect_type')));
console.log('object_resolution      ', JSON.stringify(by('object_resolution')));
console.log('business_write_wired   ', JSON.stringify(by('business_write_wired')));
console.log('steps with no expected effect type:',
  rows.filter(r => !r.expected_effect_type).length);
console.log('steps with a domain effect and no object:',
  rows.filter(r => !['KERNEL_ONLY_TRANSITION', 'CAPABILITY_REQUEST'].includes(r.expected_effect_type)
                && !r.effect_object_id).length);
