// Emit docs/phase-c-kernel/SYSTEM_EXECUTION_TRACE_INSTRUMENTATION.csv — §10.
//
// The brief is explicit that components must NOT all be run merely to produce traces. So this
// proves instrumentation STRUCTURALLY: for every active state-changing component, where its trace
// comes from, under which policy, who is accountable and which system actor executes it.
//
//   node scripts/phase_c/gen_trace_instrumentation.mjs
import { writeFileSync, mkdirSync } from 'node:fs';
import { sql } from './lib/db.mjs';

const rows = await sql(`
select c.component_id, c.component_type, c.source_path_or_db_object, c.entry_method,
       c.schedule_or_trigger, c.mutates_state, c.activation_state,
       c.accountable_role_id, c.canonical_system_actor, c.current_actor,
       c.workflow_id, c.step_id, c.authority_class, c.trace_policy_id, c.classification,
       c.idempotency_strategy, c.retry_policy,
       w.jobid              as wrapper_jobid,
       w.note               as wrapper_note,
       e.exempt_to_policy   as exemption_policy,
       e.reason             as exemption_reason,
       p.trace_required,
       sc.source_class      as cutover_class,
       sc.target_kernel_adapter as cutover_adapter
  from public.phase_c_component c
  left join public.phase_c_system_execution_wrapper w on w.component_id = c.component_id
  left join public.phase_c_component_trace_exemption e on e.component_id = c.component_id
  left join public.phase_c_trace_policy p on p.trace_policy_id = c.trace_policy_id
  left join public.phase_c_source_cutover sc on sc.source_component_id = c.component_id
 where c.activation_state in ('active','deployed')
 order by c.mutates_state desc, c.component_type, c.component_id`);

// Where a trace for this component actually comes from. Named, not asserted — each answer points
// at the routine or the table row that produces it.
const creationPoint = r => {
  if (r.wrapper_jobid) return `fn_kernel_cron_exec(${r.wrapper_jobid}) wraps this job and writes the system-execution trace`;
  if (r.cutover_adapter === 'fn_kernel_trigger_submit') return 'fn_kernel_trigger_submit writes the adapter trace, then fn_kernel_workflow_start writes the run, step and task traces';
  if (r.cutover_adapter === 'fn_kernel_signal_submit') return 'fn_kernel_signal_submit writes the signal trace, parented to the run trace';
  if (!r.mutates_state) return `no trace created — ${r.trace_required === 'NOT_REQUIRED' ? 'exempt' : r.trace_required} under ${r.trace_policy_id}`;
  if (r.exemption_policy) return `exempt to ${r.exemption_policy} — ${(r.exemption_reason || '').slice(0, 120)}`;
  return 'fn_phase_c_trace_write, called by the kernel routine that performs the change';
};

const out = rows.map(r => ({
  component_id: r.component_id,
  component_type: r.component_type,
  source: r.source_path_or_db_object,
  mutates_business_state: r.mutates_state ? 'YES' : 'no',
  canonical_adapter_or_wrapper:
    r.wrapper_jobid ? `fn_kernel_cron_exec (job ${r.wrapper_jobid})`
    : r.cutover_adapter && r.cutover_adapter.startsWith('fn_kernel') ? r.cutover_adapter
    : r.mutates_state ? 'kernel routine (direct)' : 'none — read-only',
  trace_policy: r.trace_policy_id || '(none recorded)',
  trace_required: r.trace_required || '(no policy row)',
  trace_creation_point: creationPoint(r),
  accountable_role: r.accountable_role_id || '(none)',
  system_actor: r.canonical_system_actor || r.current_actor || '(none)',
  workflow_or_scope: r.workflow_id
    ? `${r.workflow_id}${r.step_id ? ' / ' + r.step_id : ''}`
    : (r.mutates_state ? 'technical scope: ' + (r.classification || 'unclassified') : 'read-only, no workflow scope'),
  authority_class: r.authority_class || '(none)',
  idempotency: r.idempotency_strategy || '(none recorded)',
  retry_policy: r.retry_policy || '(none recorded)',
  cutover_class: r.cutover_class || 'not an autonomous source',
  activation: r.activation_state,
  exemption_reason: r.exemption_reason || '',
}));

const COLS = Object.keys(out[0]);
mkdirSync('docs/phase-c-kernel', { recursive: true });
writeFileSync('docs/phase-c-kernel/SYSTEM_EXECUTION_TRACE_INSTRUMENTATION.csv',
  [COLS.join(',')].concat(out.map(o =>
    COLS.map(c => { const v = String(o[c] ?? ''); return /[",\n]/.test(v) ? `"${v.replace(/"/g, '""')}"` : v; }).join(','))
  ).join('\n') + '\n');

const mut = out.filter(o => o.mutates_business_state === 'YES');
const noTrace = mut.filter(o => o.trace_policy === '(none recorded)' || o.trace_required === 'NOT_REQUIRED');
console.log(`${out.length} active/deployed components; ${mut.length} change business state`);
console.log(`state-changing with no required trace policy: ${noTrace.length}`);
if (noTrace.length) console.log(noTrace.slice(0, 10).map(o => '  ' + o.component_id + ' -> ' + o.trace_policy).join('\n'));
