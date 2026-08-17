// Emit the K17 cutover register seed AND docs/phase-c-kernel/ACTIVE_SOURCE_CUTOVER_MATRIX.csv from
// ONE source of truth, so the committed CSV and the deployed table can never disagree.
//
//   node scripts/phase_c/gen_k17.mjs
import { writeFileSync, mkdirSync } from 'node:fs';
import { sql } from './lib/db.mjs';
import { CLASSIFICATION, CLASS_NAME } from './source_classification.mjs';

// The population, defined once and stated out loud: every source that carries an adapter in any
// state, plus every retired one, plus every source that is live AND creates business work but was
// never connected. A source outside all three is a guard, an audit or a probe — 415 of them — and
// is on the K10 inventory, not here.
const rows = await sql(`
  select source_key, source_kind, source_ref, source_class, adapter_trigger_type, workflow_id,
         accountable_role_id, connection_state, disposition, is_active_now, creates_work_now,
         routes_through_inbox, evidence
    from public.v_kernel_trigger_source_derived
   where connection_state in ('CONNECTED_ACTIVE','CONNECTED_INACTIVE','INTENTIONALLY_RETIRED')
      or (coalesce(is_active_now,false) and coalesce(creates_work_now,false)
          and coalesce(disposition,'') <> 'FOUNDER_COMMAND_SURFACE')
      -- ...or it is already classified. Same rule as fn_kernel_source_cutover_state: the register
      -- may GROW when a new source appears and may never silently SHED a row because a flag on it
      -- moved. K17 corrected recorded_creates_work on three sources and two of them fell out of
      -- this query, which is how the rule was learned.
      or source_key in (select source_component_id from public.phase_c_source_cutover)
   order by source_kind, source_key`);

const missing = rows.filter(r => !CLASSIFICATION[r.source_key]).map(r => r.source_key);
if (missing.length) { console.error('UNCLASSIFIED, refusing to emit:\n' + missing.join('\n')); process.exit(1); }
const extra = Object.keys(CLASSIFICATION).filter(k => !rows.some(r => r.source_key === k));
if (extra.length) { console.error('CLASSIFIED BUT NOT IN THE POPULATION:\n' + extra.join('\n')); process.exit(1); }

// Statuses and cutover actions the increments have already written. Recomputing them from class
// and activation would silently undo K21's BLOCKED_NO_WORKFLOW_FOR_THIS_SIGNAL, K22b's
// RECLASSIFIED_INTERNAL_RECOMPUTATION and K25's three — the CSV would then disagree with the table
// it was built to stay in step with, which is the whole failure this generator exists to prevent.
const LIVE = Object.fromEntries((await sql(
  `select source_component_id, status, cutover_action, disposition_evidence
     from public.phase_c_source_cutover`))
  .map(r => [r.source_component_id, r]));

const ACTOR = {
  cron_job: 'system.scheduler', database_trigger: 'system.task_engine',
  edge_function: 'system.webhook_receiver', event_trigger: 'system.task_engine',
  frontend_path: 'system.webhook_receiver',
};
const q = v => v === null || v === undefined ? 'null' : `'${String(v).replace(/'/g, "''")}'`;

const out = rows.map(r => {
  const [cls, vocab, why] = CLASSIFICATION[r.source_key];
  const active = r.is_active_now === true;
  // The adapter each class must call. C and D call none — that IS the rule for them.
  const adapter = cls === 'A' ? 'fn_kernel_trigger_submit'
                : cls === 'B' ? 'fn_kernel_signal_submit'
                : 'none — this class may not create business work';
  // A source that is switched off stays switched off. An adapter existing is not a reason to
  // activate anything, and the brief says so in as many words.
  const action = cls === 'D' ? 'NONE — already retired, kept for history'
    : !active ? `wire ${adapter} into the handler; leave the source DISABLED`
    : cls === 'C' ? 'confirm it writes no business work; raise a class-A request on threshold'
    : `route through ${adapter}; then disable the direct write`;
  return {
    source_component_id: r.source_key,
    source_type: r.source_kind,
    source_class: `${cls} ${CLASS_NAME[cls]}`,
    current_entry_point: r.source_kind === 'cron_job' ? `cron.job ${r.source_ref}`
      : r.source_kind === 'database_trigger' ? `trigger ${r.source_ref}`
      : r.source_kind === 'frontend_path' ? `route ${r.source_ref}`
      : `edge function ${r.source_ref}`,
    current_direct_side_effects: r.creates_work_now === true
      ? 'writes business work directly (measured live from the catalogue: creates_work_now = true)'
      : 'no business write measured (creates_work_now = false)',
    target_kernel_adapter: adapter,
    target_workflow: cls === 'A' ? (r.workflow_id || '(none registered)')
      : cls === 'B' ? `${r.workflow_id || '(any)'} — the EXISTING run, never a new one` : 'none',
    target_step_or_signal: vocab || 'none',
    accountable_role: r.accountable_role_id,
    system_actor: ACTOR[r.source_kind],
    idempotency_key: cls === 'A' ? `trigger: <source_system>:<source_ref> (fn_kernel_trigger_submit default)`
      : cls === 'B' ? `signal: <source_type>:<source_id>:${vocab}:<workflow_run_id>`
      : 'n/a — creates nothing to deduplicate',
    trace_policy: cls === 'C' ? 'TRACE-MONITORING' : 'TRACE-SYSTEM-EXECUTION',
    current_activation: active ? 'ACTIVE' : 'DISABLED',
    cutover_action: LIVE[r.source_key]?.cutover_action ?? action,
    rollback: cls === 'D' ? 'n/a' :
      `re-point the handler at its pre-cutover write; the adapter row stays for the record`,
    status: LIVE[r.source_key]?.status ?? (
        cls === 'D' ? 'RETIRED'
      : !active ? 'ADAPTER_ASSIGNED_SOURCE_STAYS_DISABLED'
      : cls === 'C' ? 'READ_ONLY_CONFIRMED'
      : 'ADAPTER_ASSIGNED_CUTOVER_PENDING'),
    // 's 'final evidence': the routine or trigger that DISCHARGES this disposition, which
    // fn_kernel_cutover_measure verifies rather than takes on trust.
    final_evidence: LIVE[r.source_key]?.disposition_evidence ?? '(not yet recorded)',
    classification_reason: why,
    evidence: (r.evidence || '').slice(0, 400),
  };
});

const COLS = ['source_component_id','source_type','source_class','current_entry_point',
  'current_direct_side_effects','target_kernel_adapter','target_workflow','target_step_or_signal',
  'accountable_role','system_actor','idempotency_key','trace_policy','current_activation',
  'cutover_action','rollback','status','final_evidence','classification_reason','evidence'];

mkdirSync('docs/phase-c-kernel', { recursive: true });
const csv = [COLS.join(',')].concat(out.map(o =>
  COLS.map(c => { const v = String(o[c] ?? ''); return /[",\n]/.test(v) ? `"${v.replace(/"/g,'""')}"` : v; }).join(','))
).join('\n') + '\n';
writeFileSync('docs/phase-c-kernel/ACTIVE_SOURCE_CUTOVER_MATRIX.csv', csv);

writeFileSync('scripts/sql/kernel_k17_source_cutover_seed.sql',
`-- K17 seed — GENERATED by scripts/phase_c/gen_k17.mjs. Do not hand-edit; edit the classification
-- in scripts/phase_c/source_classification.mjs and re-run, so the committed CSV in
-- docs/phase-c-kernel/ACTIVE_SOURCE_CUTOVER_MATRIX.csv and this table cannot drift apart.
begin;

delete from public.phase_c_source_cutover;

insert into public.phase_c_source_cutover
  (${COLS.join(', ')})
values
${out.map(o => '  (' + COLS.map(c => q(o[c])).join(', ') + ')').join(',\n')};

commit;
`);

const by = c => out.filter(o => o.source_class.startsWith(c)).length;
console.log(`${out.length} sources classified — A ${by('A')}, B ${by('B')}, C ${by('C')}, D ${by('D')}`);
console.log(`active ${out.filter(o => o.current_activation === 'ACTIVE').length}, ` +
            `disabled ${out.filter(o => o.current_activation === 'DISABLED').length}`);
