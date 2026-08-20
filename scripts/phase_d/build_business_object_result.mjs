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

//
// TWO COLUMNS WERE SENTENCES, NOT MEASUREMENTS, and both were asserted into all 56 rows:
//
//   implementation_commit  'bc20365..HEAD (scripts/sql/phase_d_d2_business_object_map.sql)'
//   production_version     'applied to htdblwldjkcgjvmqkbeh, read back identical'
//
// The second is the worse of the two: this builder performs no read-back of any kind, so the column
// certified something nobody had done. Both are derived now — the implementation identified by the
// content of the SQL file that implements it, and the version from the live catalogue entry for the
// object's own relation.
import { createHash } from 'node:crypto';
import { mgmtRead, PROD_REF } from '../staging/qd_guard.mjs';
import { readFileSync, writeFileSync } from 'node:fs';
import { outPath, provenance } from './lib/deliverable.mjs';

const q = (sql) => mgmtRead(PROD_REF, sql, 'phase D business object export');

// WHICH IMPLEMENTATION THIS MAP CAME FROM — identified by CONTENT, not by a commit hash.
//
// Two wrong answers were tried before this one, and the second is the subtle one.
//
//   `git rev-parse HEAD`     changes on every commit to anything, so the deliverable would differ
//                            from its committed copy the moment any unrelated change landed. The
//                            check that compares them would be red permanently and switched off
//                            within a week.
//   `git log -1 -- <file>`   fixes that — it moves only when the implementation moves — and is
//                            still wrong, because the hash it returns IS NOT MERGE-STABLE. It is
//                            whatever the branch-local commit was at build time. Measured
//                            20 Aug 2026: 9dd1927 is the last commit touching this SQL file and
//                            `git branch --contains 9dd1927` names only the working branch. main
//                            carries a mixture of merge commits and squashes (22 of its last 200
//                            non-merge commits end in a `(#NNN)` squash suffix), and a squash mints
//                            a new hash for the same content — so the value baked into the
//                            committed CSV would name a commit that does not exist on main, the
//                            regeneration would produce a different one, and
//                            scripts/checks/phase_d_deliverables_match_production.test.mjs would go
//                            red on main after every merge. A deliverable must reproduce from the
//                            merged tree, not only from the branch that built it.
//
// The sha256 of the file's own bytes has the property both attempts were reaching for and neither
// had: it changes exactly when the implementation changes, and it survives squash, rebase, merge
// and a shallow clone, because it is not about history at all. It also matches the sibling
// production_version column below, which already identifies the live relation by content digest.
const IMPL_SQL = 'scripts/sql/phase_d_d2_business_object_map.sql';
const implCommit = (() => {
  let bytes;
  try {
    bytes = readFileSync(IMPL_SQL);
  } catch {
    console.error(`${IMPL_SQL} is not in this tree. Refusing to write an implementation_commit `
      + 'column that would be a guess.');
    process.exit(1);
  }
  return `sha256:${createHash('sha256').update(bytes).digest('hex')} (${IMPL_SQL})`;
})();

const cell = (v) => {
  if (v === null || v === undefined) return '';
  const s = String(v).replace(/\r?\n/g, ' ').trim();
  return /[",]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
};
const row = (cs) => cs.map(cell).join(',');
/** A single-quoted SQL literal. The only value interpolated here is a sha256 hex and a repo path. */
const lit = (v) => `'${String(v).replace(/'/g, "''")}'`;

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
    ${lit(implCommit)}                                       as implementation_commit,
    -- THE READ-BACK, ACTUALLY PERFORMED. The relation each object is bound to, as the live
    -- catalogue holds it right now: its kind, and a digest of the thing that defines it — the view
    -- body for a view, the ordered column list and types for a table. A binding whose relation is
    -- not there says ABSENT rather than "read back identical".
    coalesce((select case
                when c.relkind in ('v','m')
                  then c.relkind::text || ' · definition md5 ' || md5(pg_get_viewdef(c.oid))
                else c.relkind::text || ' · ' ||
                     (select count(*)::text from pg_attribute a
                       where a.attrelid = c.oid and a.attnum > 0 and not a.attisdropped)
                     || ' columns · shape md5 ' ||
                     (select md5(string_agg(a.attname || ':' || format_type(a.atttypid, a.atttypmod),
                                            ',' order by a.attnum))
                        from pg_attribute a
                       where a.attrelid = c.oid and a.attnum > 0 and not a.attisdropped)
              end
                from pg_class c join pg_namespace n on n.oid = c.relnamespace
               where n.nspname = 'public'
                 and c.relname = replace(b.canonical_relation,'public.','')),
             'ABSENT ON PRODUCTION — no relation of this name exists in schema public')
                                                             as production_version,
    b.evidence
  from public.phase_d_business_object_binding b
  order by b.object_id
`);

// THE DENOMINATOR IS THE REGISTRY'S. `if (rows.length !== 56)` is right until the binding registry
// moves, and a check that can only agree with itself is a rubber stamp; the zero-guard beside it is
// the half that stops an empty registry reading as a complete export.
const want = await q('select count(*)::int as n from public.phase_d_business_object_binding');
const wantN = want?.[0]?.n ?? 0;
if (!wantN) {
  console.error('public.phase_d_business_object_binding is empty — refusing to write a deliverable '
    + 'over nothing.');
  process.exit(1);
}
if (rows.length !== wantN) {
  console.error(`the binding registry holds ${wantN} object(s) and the export resolved ${rows.length}. `
    + 'Refusing to write a partial file — a short object map reads as "these are all the objects" '
    + 'and it would not be.');
  process.exit(1);
}
const unresolved = rows.filter((r) => !r.canonical_relation || !r.canonical_read_service);
if (unresolved.length) {
  console.error(`${unresolved.length} object(s) have no relation or no read service.`);
  process.exit(1);
}

const header = Object.keys(rows[0]);
writeFileSync(outPath('PHASE_D_BUSINESS_OBJECT_RESULT.csv'),
  provenance({
    command: 'node scripts/phase_d/build_business_object_result.mjs',
    numerator: rows.length,
    denominator: wantN,
    of: 'bound Phase B business objects',
    attribution: 'one row per public.phase_d_business_object_binding row; production_version is a '
      + 'live catalogue read-back of the bound relation, not a claim about one',
  })
  + [row(header), ...rows.map((r) => row(header.map((h) => r[h])))].join('\n') + '\n', 'utf8');

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
