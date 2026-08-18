// PHASE D · D0 — build PHASE_D_CURRENT_CODE_HANDLER_CROSSWALK.csv from the LIVE registries.
//
// The packaged CSVs in the Phase D zip are source references. PHASE_D_PRECONDITIONS_AND_FROZEN_
// BASELINES.md is explicit: "Before implementation Claude must export the live founder-approved
// effective registries and prove the frozen counts/hashes, PBCR-001 and zero unapproved drift."
// So this reads the database, never the package, and every column it writes is derived rather
// than transcribed.
//
// One number the package and the live registry genuinely disagree on, and it is not a defect:
// the packaged handoff matrix carries 161 rows and public.phase_b_handoff carries 159. The
// founder-approved effective baseline is the live one; the package is the pre-erratum source.
// The difference is recorded in the report rather than reconciled away.

import { mgmtRead, PROD_REF } from '../staging/qd_guard.mjs';

// mgmtRead refuses anything that is not read-only, which is what makes running this against the
// one project safe: a D0 export has no business writing.
const q = async (sql) => mgmtRead(PROD_REF, sql, 'phase D D0 crosswalk export');

const csvCell = (v) => {
  if (v === null || v === undefined) return '';
  const s = String(v).replace(/\r?\n/g, ' ').trim();
  return /[",]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
};
const csvRow = (cells) => cells.map(csvCell).join(',');

const rows = await q(`
  select
    b.step_id,
    b.workflow_id,
    s.step_no,
    s.step_name,
    s.step_type,
    b.handler_id,
    b.handler_version,
    b.handler_class,
    b.handler_routine                      as target_handler_routine,
    b.accountable_role_id,
    coalesce(nullif(s.independent_reviewer_role_id,''),'')  as independent_reviewer_role_id,
    b.input_schema_id,
    b.output_schema_id,
    (select cardinality(required_keys) from public.phase_d_handler_schema
      where schema_id = b.input_schema_id)  as input_required_keys,
    (select cardinality(required_keys) from public.phase_d_handler_schema
      where schema_id = b.output_schema_id) as output_required_keys,
    cardinality(b.rule_ids)                 as rules_in_scope,
    (select count(*) from unnest(b.rule_ids) r
      join public.phase_d_rule_enforcement e on e.rule_id = r
     where e.status = 'ENFORCED')           as rules_enforced,
    (select count(*) from unnest(b.rule_ids) r
      join public.phase_d_rule_enforcement e on e.rule_id = r
     where e.status = 'OUTSTANDING')        as rules_outstanding,
    cardinality(b.gate_ids)                 as gates_in_scope,
    b.idempotency_template,
    b.concurrency_lock_scope,
    array_to_string(b.failure_code_contract,';') as failure_code_contract,
    b.capability_dependency,
    coalesce(nullif(b.capability_evidence,''),'') as capability_evidence,
    b.provider_dependency,
    b.external_effect_policy,
    b.trace_point,
    b.founder_gate,
    -- WHAT PHASE C RECORDED, kept beside the Phase D verdict so the two can be compared rather
    -- than one silently replacing the other.
    coalesce(nullif(b.phase_c_current_handler,''),'(none measured)') as phase_c_current_handler,
    b.phase_c_connection                    as phase_c_connection_status,
    sb.canonical_runtime_handler            as phase_c_named_handler,
    case when exists (select 1 from public.kernel_retired_path rp
                       where rp.disposition = 'DISABLED'
                         and sb.canonical_runtime_handler like '%' || rp.path_name || '%')
         then 'YES — the Phase C binding names a DISABLED path'
         else 'no' end                      as phase_c_handler_is_retired,
    -- The Phase D reconciliation verdict.
    case
      when b.phase_c_connection = 'DEFERRED_RUNTIME_IMPLEMENTATION' then 'IMPLEMENT'
      else 'WRAP_TO_CANONICAL'
    end                                     as target_action,
    b.phase_d_status,
    s.next_step_if_pass,
    (select h.handoff_id from public.phase_b_handoff h
      where h.from_step_id = b.step_id limit 1) as opens_handoff,
    s.is_closure_step,
    'PD-POS-' || b.step_id                  as positive_test_id,
    'PD-NEG-' || b.step_id || '-MISSING_INPUT;PD-NEG-' || b.step_id || '-WRONG_ACTOR;PD-NEG-'
      || b.step_id || '-INVALID_STATE;PD-NEG-' || b.step_id || '-DUPLICATE;PD-NEG-'
      || b.step_id || '-RULE_GATE;PD-NEG-' || b.step_id || '-OUTPUT_SCHEMA' as negative_test_ids,
    'NOT_RUN'                               as result
  from public.phase_d_handler_binding b
  join public.phase_b_workflow_step s on s.step_id = b.step_id
  left join public.phase_c_step_binding sb on sb.step_id = b.step_id
  order by b.workflow_id, s.step_no
`);

if (!Array.isArray(rows) || rows.length === 0) {
  console.error('D0 crosswalk: the query returned no rows. Refusing to write an empty crosswalk — '
    + 'an empty file would read as "nothing to reconcile" rather than as a failed export.');
  process.exit(1);
}
if (rows.length !== 257) {
  console.error(`D0 crosswalk: expected 257 rows and got ${rows.length}. `
    + 'The frozen Phase B registry declares 257 steps; refusing to write a partial crosswalk.');
  process.exit(1);
}

const header = Object.keys(rows[0]);
const out = [csvRow(header), ...rows.map((r) => csvRow(header.map((h) => r[h])))].join('\n') + '\n';

const { writeFileSync } = await import('node:fs');
writeFileSync('PHASE_D_CURRENT_CODE_HANDLER_CROSSWALK.csv', out, 'utf8');

// The summary is printed so the run itself states what it covered, rather than the reader having
// to open the file to find out whether it means anything.
const count = (pred) => rows.filter(pred).length;
console.log(`PHASE_D_CURRENT_CODE_HANDLER_CROSSWALK.csv — ${rows.length} rows, ${header.length} columns`);
console.log(`  workflows                     ${new Set(rows.map((r) => r.workflow_id)).size}`);
console.log(`  target_action IMPLEMENT       ${count((r) => r.target_action === 'IMPLEMENT')}`);
console.log(`  target_action WRAP_TO_CANONICAL ${count((r) => r.target_action === 'WRAP_TO_CANONICAL')}`);
console.log(`  phase_c binding named a RETIRED path  ${count((r) => r.phase_c_handler_is_retired.startsWith('YES'))}`);
console.log(`  capability-dependent          ${count((r) => r.capability_dependency !== 'NONE')}`);
console.log(`  steps opening a handoff       ${count((r) => r.opens_handoff)}`);
console.log(`  closure steps                 ${count((r) => r.is_closure_step)}`);
console.log(`  rules outstanding on >=1 step ${count((r) => Number(r.rules_outstanding) > 0)}`);
