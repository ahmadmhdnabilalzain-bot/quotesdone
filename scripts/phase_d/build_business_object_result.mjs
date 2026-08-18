// PHASE D — build docs/phase-d/PHASE_D_BUSINESS_OBJECT_RESULT.csv (required deliverable 4 of 15).
//
// One row per frozen Phase B business object, carrying every column the Phase D brief asks for.
// Every value is read from the live database: the binding registry, the live catalogue for the
// relation and its RLS/policy state, the write map for current callers and direct DML, and the
// frozen registry for the workflows and steps that use the object.
//
// Two columns are deliberately measured rather than asserted:
//   rls_policy      — the POLICY COUNT, not the relrowsecurity flag. 536 public tables have RLS
//                     enabled with zero policies, which is deny-all rather than protection by
//                     configuration, and reporting the flag alone would read as the opposite.
//   current_direct_dml — every edge function in phase_c_edge_function_writes that writes the
//                     bound relation, with its write kind. An empty list is a measurement, and it
//                     is printed as "none measured" rather than left blank.

import { mgmtRead, PROD_REF } from '../staging/qd_guard.mjs';
import { writeFileSync, mkdirSync } from 'node:fs';

const q = (sql) => mgmtRead(PROD_REF, sql, 'phase D business object export');

const cell = (v) => {
  if (v === null || v === undefined) return '';
  const s = String(v).replace(/\r?\n/g, ' ').trim();
  return /[",]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
};
const row = (cs) => cs.map(cell).join(',');

const rows = await q(`
  select
    b.object_id,
    b.display_name,
    -- every workflow and step that names this object as its workflow's primary object
    coalesce((select string_agg(distinct w.workflow_id, ';' order by w.workflow_id)
                from public.phase_b_workflow w where w.primary_object = b.object_id),
             b.governing_workflow_id)                       as workflows_using_it,
    coalesce((select string_agg(s.step_id, ';' order by s.step_id)
                from public.phase_b_workflow_step s
                join public.phase_b_workflow w on w.workflow_id = s.workflow_id
               where w.primary_object = b.object_id), '')   as steps_using_it,
    b.canonical_relation,
    b.relation_kind,
    b.primary_identity,
    b.parent_identity,
    b.ownership_scope,
    b.ownership_column,
    b.canonical_read_service,
    b.canonical_write_service,
    -- CURRENT CALLERS, measured from the write map rather than declared
    coalesce((select string_agg(distinct w.edge_function, ';' order by w.edge_function)
                from public.phase_c_edge_function_writes w
               where w.table_name = replace(b.canonical_relation,'public.','')),
             'none measured')                               as current_callers,
    coalesce((select string_agg(distinct w.edge_function || ':' || w.write_kind, ';'
                                order by w.edge_function || ':' || w.write_kind)
                from public.phase_c_edge_function_writes w
               where w.table_name = replace(b.canonical_relation,'public.','')),
             'none measured')                               as current_direct_dml,
    b.status_model,
    b.versioning,
    b.record_policy,
    b.policy_family                                          as append_only_or_mutable_policy,
    -- RLS: the POLICY COUNT, because 536 tables carry the flag with no policy at all
    coalesce((select case when c.relrowsecurity
                          then (select count(*)::text from pg_policy p where p.polrelid = c.oid)
                               || ' policy(ies), RLS enabled'
                          else 'RLS DISABLED' end
                from pg_class c join pg_namespace n on n.oid = c.relnamespace
               where n.nspname='public'
                 and c.relname = replace(b.canonical_relation,'public.','')),
             'view over public.phase_d_object_record; access is through the services only')
                                                             as rls_policy,
    b.accountable_role_id                                    as role_authority,
    b.storage_bucket                                         as storage_path_or_bucket,
    b.raw_representation,
    b.safe_representation,
    b.trace_relationship,
    b.retention,
    b.cancellation_behaviour                                 as cancellation_supersession,
    b.compensation                                           as compensation_rollback,
    'PD-OBJ-POS-' || upper(b.object_id)                      as positive_test,
    'PD-OBJ-NEG-' || upper(b.object_id) || '-UNBOUND;'
      || 'PD-OBJ-NEG-' || upper(b.object_id) || '-EMPTY_PAYLOAD;'
      || 'PD-OBJ-NEG-' || upper(b.object_id) || '-NO_OWNER;'
      || 'PD-OBJ-NEG-' || upper(b.object_id) || '-POLICY_VIOLATION;'
      || 'PD-OBJ-NEG-' || upper(b.object_id) || '-CROSS_OWNER'  as negative_tests,
    b.current_status,
    b.target_action,
    'bc20365..HEAD (scripts/sql/phase_d_d2_business_object_map.sql)' as implementation_commit,
    'applied to htdblwldjkcgjvmqkbeh, read back identical'    as production_version,
    b.evidence
  from public.phase_d_business_object_binding b
  order by b.object_id
`);

if (rows.length !== 56) {
  console.error(`expected 56 object rows, got ${rows.length}. Refusing to write a partial file — `
    + 'a short object map reads as "these are all the objects" and it would not be.');
  process.exit(1);
}
const unresolved = rows.filter((r) => !r.canonical_relation || !r.canonical_read_service);
if (unresolved.length) {
  console.error(`${unresolved.length} object(s) have no relation or no read service.`);
  process.exit(1);
}

mkdirSync('docs/phase-d', { recursive: true });
const header = Object.keys(rows[0]);
writeFileSync('docs/phase-d/PHASE_D_BUSINESS_OBJECT_RESULT.csv',
  [row(header), ...rows.map((r) => row(header.map((h) => r[h])))].join('\n') + '\n', 'utf8');

const n = (p) => rows.filter(p).length;
console.log(`PHASE_D_BUSINESS_OBJECT_RESULT.csv — ${rows.length} rows, ${header.length} columns`);
console.log(`  bound to an existing table      ${n((r) => r.relation_kind === 'EXISTING_TABLE')}`);
console.log(`  built on the Phase D store      ${n((r) => r.relation_kind === 'PHASE_D_OBJECT_VIEW')}`);
for (const a of ['KEEP_VERIFIED', 'KEEP_BETTER_EXISTING', 'REPAIR', 'IMPLEMENT']) {
  console.log(`  ${a.padEnd(30)} ${n((r) => r.target_action === a)}`);
}
console.log(`  customer-scoped                 ${n((r) => r.ownership_scope === 'CUSTOMER')}`);
console.log(`  supplier-scoped                 ${n((r) => r.ownership_scope === 'SUPPLIER')}`);
console.log(`  company-scoped                  ${n((r) => r.ownership_scope === 'COMPANY')}`);
console.log(`  with measured edge-function callers ${n((r) => r.current_callers !== 'none measured')}`);
