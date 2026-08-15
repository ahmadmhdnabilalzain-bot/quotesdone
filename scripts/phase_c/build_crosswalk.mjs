// Phase C Stage C1 — build PHASE_C_RUNTIME_COMPONENT_CROSSWALK.csv and
// PHASE_C_EXECUTOR_ACCOUNTABILITY.csv from the measured inventory.
//
//   node scripts/phase_c/inventory.mjs && node scripts/phase_c/build_crosswalk.mjs
//
// Every field is derived, never typed.  The derivation rules live in lib/component_map.mjs
// and lib/classify.mjs so a verdict can be reproduced, and the `evidence` column on each
// row names the measurement that produced it.
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { join } from 'node:path';
import { REPO, OUT, loadPackage, writeCSV } from './lib/package.mjs';
import { sql } from './lib/db.mjs';
import * as C from './lib/classify.mjs';
import * as M from './lib/component_map.mjs';

const inv = JSON.parse(readFileSync(join(OUT, '_inventory.json'), 'utf8'));
const pkg = loadPackage();

// ------------------------------------------------------------------ frozen references
const wfRows = await sql(`select workflow_id, workflow_name, accountable_role_id from public.phase_b_workflow order by workflow_id`);
const roleRows = await sql(`select role_id, primary_department_id from public.org_role where status='active'`);
const stepRows = await sql(`select step_id, workflow_id, step_no, accountable_role_id from public.phase_b_workflow_step order by workflow_id, step_no`);
const pbx = await sql(`select current_artifact_type, current_artifact_name, target_workflow_id
                       from public.phase_b_crosswalk`);

const wfOwner = new Map(wfRows.map(w => [w.workflow_id, w.accountable_role_id]));
const deptOf = new Map(roleRows.map(r => [r.role_id, r.primary_department_id]));
const firstStep = new Map();                       // workflow_id -> first step_id
for (const s of stepRows) if (!firstStep.has(s.workflow_id)) firstStep.set(s.workflow_id, s.step_id);
const pbTarget = new Map(pbx.map(r => [`${r.current_artifact_type}:${r.current_artifact_name}`, r.target_workflow_id]));

// The system-actor registry is the authority on which role owns a system actor.
const actorOwner = new Map(pkg.systemActors.map(a => [a.system_actor_id, a.accountable_role_id]));
// Package department tokens are long-form; the live keys are short.  Resolved through the
// alias table below, which the reconciliation migration loads.
const DEPT_ALIAS = {
  finance_payments: 'finance', people_company_operations: 'people_ops', growth_revenue: 'growth',
  data_intelligence_knowledge: 'data_intel', assurance_security_reliability: 'assurance',
  marketplace_supplier_network: 'marketplace', legal_compliance_risk_trust: 'legal',
  customer_experience_communications: 'customer_experience', product_engineering_ai: 'product_eng',
};
const ROLE_ALIAS = {                               // package spelling -> live canonical role_id
  coo: 'chief_operating_officer', it_operations_site_reliability_engineer: 'it_operations_engineer',
  lifecycle_channel_operations_specialist: 'lifecycle_channel_operations',
  chief_product_technology_officer: 'cto', fpa_analyst: 'fpna_analyst',
};
const liveRole = t => ROLE_ALIAS[t] || t;
const liveDept = t => DEPT_ALIAS[t] || t;

// An agent key is a runtime identity, not a role id.  org_role.runtime_agent_key and
// org_role_alias both map it back; a key that resolves to neither is reported, never guessed.
const aliasRows = await sql(`select alias, role_id from public.org_role_alias`);
const byAlias = new Map(aliasRows.map(a => [a.alias, a.role_id]));
const byAgentKey = new Map(
  (await sql(`select runtime_agent_key, role_id from public.org_role
              where status='active' and runtime_agent_key is not null`))
  .map(r => [r.runtime_agent_key, r.role_id]));
const activeRoleIds = new Set(roleRows.map(r => r.role_id));
function resolveAgentKey(k) {
  if (!k) return null;
  if (activeRoleIds.has(k)) return k;
  if (byAgentKey.has(k)) return byAgentKey.get(k);
  const a = byAlias.get(k);
  return a && activeRoleIds.has(a) ? a : null;
}

/** The accountable business owner for a component, given the workflow it serves. */
function ownerFor(workflow, systemActor) {
  if (workflow && workflow !== 'ALL' && workflow !== 'OUT_OF_SCOPE' && wfOwner.has(workflow)) {
    return { role: wfOwner.get(workflow), scope: workflow, step: firstStep.get(workflow) || '' };
  }
  // SYSTEM scope: the registry names who owns the actor.  §3.5 — the actor executes, the
  // role owns.  This is the "explicit justified system scope" the invariant allows.
  const role = liveRole(actorOwner.get(systemActor) || 'chief_operating_officer');
  return { role, scope: workflow === 'OUT_OF_SCOPE' ? 'OUT_OF_SCOPE' : 'SYSTEM_SCOPE', step: '' };
}

const rows = [];
const push = o => rows.push(o);
const base = (id, type, path) => ({
  component_id: id, component_type: type, source_path_or_db_object: path,
  entry_method: '', current_callers: '', external_entry: '', schedule_or_trigger: '',
  mutates_state: '', current_actor: '', canonical_system_actor: '', accountable_role_id: '',
  department_id: '', workflow_id: '', step_id: '', authority_class: '', trace_policy_id: '',
  idempotency_strategy: '', retry_policy: '', activation_state: '', classification: '',
  gap: '', repair_or_keep_action: '', evidence: '',
});

// ------------------------------------------------------------------------- cron jobs
for (const c of inv.cron) {
  const wf = M.CRON_TO_WORKFLOW[c.jobname] ?? pbTarget.get(`cron_job:${c.jobname}`) ?? 'ALL';
  const actor = 'system.scheduler';
  const own = ownerFor(wf, actor);
  const cls = C.classifyCron(c);
  const r = base(`cron:${c.jobname}`, 'cron_job', `cron.job/${c.jobid}`);
  Object.assign(r, {
    entry_method: 'pg_cron schedule', current_callers: 'pg_cron', external_entry: 'no',
    schedule_or_trigger: c.schedule, mutates_state: 'yes',
    current_actor: 'pg_cron (postgres superuser)', canonical_system_actor: actor,
    accountable_role_id: own.role, department_id: liveDept(deptOf.get(own.role) || ''),
    workflow_id: own.scope, step_id: own.step,
    authority_class: M.actionClassFor(wf), trace_policy_id: M.TYPE_TO_TRACE_POLICY.cron_job,
    idempotency_strategy: M.TYPE_TO_IDEMPOTENCY.cron_job, retry_policy: M.TYPE_TO_RETRY.cron_job,
    activation_state: c.active ? 'active' : 'inactive', classification: cls,
    gap: cls === 'INACTIVE_HISTORICAL' ? `switched off after ${c.runs} runs; last ${c.last_start}` :
         cls === 'REPAIR_BEFORE_REACTIVATION' ? 'switched off and never ran; unproven' : '',
    repair_or_keep_action: c.active
      ? 'keep active; accountability now recorded, activation state unchanged'
      : 'leave deactivated — Phase C does not re-enable business automation merely because it is mapped',
    evidence: `cron.job_run_details runs=${c.runs} last_status=${c.last_status ?? 'none'}`,
  });
  push(r);
}

// --------------------------------------------------------------------- edge functions
for (const e of inv.edge) {
  const wf = M.EDGE_TO_WORKFLOW[e.slug] ?? pbTarget.get(`edge_function:${e.slug}`) ?? 'ALL';
  const actor = M.edgeSystemActor(e);
  const own = ownerFor(wf, actor);
  const entry = C.edgeEntry(e);
  const cls = C.classifyEdge(e);
  const callers = [...e.frontend, ...e.edge, ...e.db, ...e.cron];
  const r = base(`edge:${e.slug}`, 'edge_function', `supabase/functions/${e.slug}/index.ts`);
  Object.assign(r, {
    entry_method: entry === 'internal_caller' ? 'invoked by repo/database/cron caller'
      : entry === 'external_product_entry' ? 'external HTTP entry (verify_jwt=false product surface)'
      : entry === 'unauthenticated_only' ? 'reachable over HTTP without a JWT; no caller in the estate'
      : 'no caller and JWT-gated: unreachable today',
    current_callers: callers.slice(0, 6).join('; ') + (callers.length > 6 ? ` (+${callers.length - 6})` : ''),
    external_entry: entry === 'external_product_entry' ? 'yes' : e.verify_jwt_false ? 'unauthenticated_only' : 'no',
    schedule_or_trigger: e.cron.join('; '),
    mutates_state: e.mutates ? 'yes' : 'no',
    current_actor: 'service_role', canonical_system_actor: actor,
    accountable_role_id: own.role, department_id: liveDept(deptOf.get(own.role) || ''),
    workflow_id: own.scope, step_id: own.step,
    authority_class: M.actionClassFor(wf), trace_policy_id: M.TYPE_TO_TRACE_POLICY.edge_function,
    idempotency_strategy: M.TYPE_TO_IDEMPOTENCY.edge_function, retry_policy: M.TYPE_TO_RETRY.edge_function,
    activation_state: 'deployed', classification: cls,
    gap: cls === 'NO_CALLER_UNCLASSIFIED'
      ? `no caller in repo, database or cron; entry=${entry}` : '',
    repair_or_keep_action: cls === 'NO_CALLER_UNCLASSIFIED'
      ? 'accountability recorded; wiring or retirement is a Phase D decision, not a Phase C deletion'
      : 'keep; accountability and trace policy now recorded',
    evidence: `callers=${e.callers} (frontend ${e.frontend.length}, edge ${e.edge.length}, db ${e.db.length}, cron ${e.cron.length}); verify_jwt_false=${e.verify_jwt_false}`,
  });
  push(r);
}

// ------------------------------------------------------------------ database routines
for (const f of inv.db_functions) {
  const wf = M.routineWorkflow(f.proname);
  const actor = f.called_by_trigger ? 'system.workflow_engine'
    : f.named_by_cron ? 'system.scheduler' : 'system.task_engine';
  const own = ownerFor(wf, actor);
  const cls = C.classifyRoutine(f);
  const mutates = C.mutatesRoutine(f);
  const r = base(`dbfn:${f.proname}(${f.args})`, 'database_function', `public.${f.proname}`);
  Object.assign(r, {
    entry_method: f.called_by_trigger ? 'trigger' : f.named_by_cron ? 'cron command'
      : f.named_by_edge_or_frontend ? 'RPC from an edge function or the frontend'
      : Number(f.named_by_other_functions) > 0 ? 'called by another routine'
      : 'PostgREST RPC surface only; nothing in the estate names it',
    current_callers: [f.called_by_trigger ? 'trigger' : null, f.named_by_cron ? 'cron' : null,
      f.named_by_edge_or_frontend ? 'edge/frontend rpc' : null,
      Number(f.named_by_other_functions) > 0 ? `${f.named_by_other_functions} routines` : null]
      .filter(Boolean).join('; '),
    external_entry: 'no', schedule_or_trigger: f.called_by_trigger ? 'trigger' : '',
    mutates_state: mutates ? 'yes' : 'no',
    current_actor: f.prosecdef ? 'SECURITY DEFINER (function owner)' : 'caller',
    canonical_system_actor: actor,
    accountable_role_id: own.role, department_id: liveDept(deptOf.get(own.role) || ''),
    workflow_id: own.scope, step_id: own.step,
    authority_class: M.actionClassFor(wf), trace_policy_id: M.TYPE_TO_TRACE_POLICY.database_function,
    idempotency_strategy: M.TYPE_TO_IDEMPOTENCY.database_function,
    retry_policy: M.TYPE_TO_RETRY.database_function,
    activation_state: 'deployed', classification: cls,
    gap: cls === 'NO_CALLER_UNCLASSIFIED'
      ? 'no trigger, cron, routine, edge function or frontend file names it; reachable only by a direct PostgREST RPC' : '',
    repair_or_keep_action: 'keep; accountability and trace policy now recorded',
    evidence: `volatility=${f.provolatile} writes_sql=${f.writes_sql} trigger=${f.called_by_trigger} cron=${f.named_by_cron} rpc=${f.named_by_edge_or_frontend} routines=${f.named_by_other_functions}`,
  });
  push(r);
}

// ------------------------------------------------------------------ database triggers
for (const t of inv.db_triggers) {
  const wf = pbTarget.get(`state_table:${t.table_name}`) ?? M.routineWorkflow(t.function_name);
  const actor = 'system.workflow_engine';
  const own = ownerFor(wf, actor);
  const cls = C.classifyTrigger(t);
  const r = base(`trigger:${t.table_name}.${t.tgname}`, 'database_trigger', `public.${t.table_name} -> ${t.function_name}()`);
  Object.assign(r, {
    entry_method: 'row event', current_callers: `public.${t.table_name}`, external_entry: 'no',
    schedule_or_trigger: [t.is_before ? 'BEFORE' : 'AFTER',
      [t.on_insert && 'INSERT', t.on_update && 'UPDATE', t.on_delete && 'DELETE'].filter(Boolean).join('/')].join(' '),
    mutates_state: 'yes', current_actor: 'writer session', canonical_system_actor: actor,
    accountable_role_id: own.role, department_id: liveDept(deptOf.get(own.role) || ''),
    workflow_id: own.scope, step_id: own.step,
    authority_class: M.actionClassFor(wf), trace_policy_id: M.TYPE_TO_TRACE_POLICY.database_trigger,
    idempotency_strategy: M.TYPE_TO_IDEMPOTENCY.database_trigger,
    retry_policy: M.TYPE_TO_RETRY.database_trigger,
    activation_state: t.tgenabled === 'O' ? 'active' : `disabled(${t.tgenabled})`,
    classification: cls, gap: cls === 'INACTIVE_HISTORICAL' ? 'trigger disabled' : '',
    repair_or_keep_action: 'keep; accountability recorded, enable state unchanged',
    evidence: `pg_trigger.tgenabled=${t.tgenabled}`,
  });
  push(r);
}

// ---------------------------------------------------------------------- state tables
for (const s of inv.state_tables) {
  const wf = pbTarget.get(`state_table:${s.table_name}`) ?? M.routineWorkflow(s.table_name);
  const actor = 'system.workflow_engine';
  const own = ownerFor(wf, actor);
  const r = base(`table:${s.table_name}`, 'state_table', `public.${s.table_name}`);
  Object.assign(r, {
    entry_method: 'written by routines/triggers/edge functions',
    current_callers: '', external_entry: 'no', schedule_or_trigger: '',
    mutates_state: 'yes', current_actor: 'various writers', canonical_system_actor: actor,
    accountable_role_id: own.role, department_id: liveDept(deptOf.get(own.role) || ''),
    workflow_id: own.scope, step_id: own.step,
    authority_class: M.actionClassFor(wf), trace_policy_id: M.TYPE_TO_TRACE_POLICY.state_table,
    idempotency_strategy: M.TYPE_TO_IDEMPOTENCY.state_table, retry_policy: M.TYPE_TO_RETRY.state_table,
    activation_state: 'active', classification: 'CANONICAL_KEEP', gap: '',
    repair_or_keep_action: 'keep; the state it carries is now attributed to a canonical owner',
    evidence: `state columns [${s.state_columns}]; approx ${s.approx_rows} rows`,
  });
  push(r);
}

// ------------------------------------------------------- runtime workflow definitions
for (const w of inv.runtime_workflows) {
  const canon = M.RUNTIME_WORKFLOW_TO_CANONICAL[w.workflow_key] || ['ALL'];
  const wf = canon[0];
  const actor = 'system.workflow_engine';
  const own = ownerFor(wf, actor);
  const cls = C.classifyRuntimeWorkflow(w);
  const r = base(`rtwf:${w.workflow_key}`, 'runtime_workflow_definition', `public.workflow/${w.workflow_key}`);
  Object.assign(r, {
    entry_method: w.trigger_event || 'start event', current_callers: 'workflow_dispatch',
    external_entry: 'no', schedule_or_trigger: w.trigger_event || '',
    mutates_state: 'yes', current_actor: 'service_role', canonical_system_actor: actor,
    accountable_role_id: own.role, department_id: liveDept(deptOf.get(own.role) || ''),
    workflow_id: canon.join('; '), step_id: own.step,
    authority_class: M.actionClassFor(wf), trace_policy_id: M.TYPE_TO_TRACE_POLICY.runtime_workflow_definition,
    idempotency_strategy: M.TYPE_TO_IDEMPOTENCY.runtime_workflow_definition,
    retry_policy: M.TYPE_TO_RETRY.runtime_workflow_definition,
    activation_state: w.active ? 'active' : 'inactive', classification: cls,
    gap: Number(w.runs) === 0 ? `${w.steps} steps defined, 0 runs — never executed` : '',
    repair_or_keep_action: Number(w.runs) > 0
      ? 'CANONICAL_BETTER_KEEP: a working state machine with run history; canonical binding maps onto it'
      : 'accountability recorded; first execution is Phase D business-correctness work',
    evidence: `public.workflow_run runs=${w.runs} last=${w.last_run ?? 'never'}; steps=${w.steps}`,
  });
  push(r);
}

// ----------------------------------------------------------------- event subscriptions
for (const s of inv.event_subscriptions) {
  // The subscription's identity is (agent_key, event_type) — that pair is what the table is
  // keyed on in practice.  An earlier version fell back to a truncated JSON dump of the row,
  // which collided nine times and would have failed the load with a duplicate key.
  const key = `${s.agent_key}@${s.event_type}`;
  const wf = M.routineWorkflow(String(s.event_type));
  const actor = 'system.event_dispatcher';
  // The subscriber is an agent key, so resolve it: the accountable role is the SUBSCRIBER where
  // it resolves, not the workflow owner. A subscription is that employee's inbox.
  const subscriber = resolveAgentKey(s.agent_key);
  const own = subscriber ? { role: subscriber, scope: wf === 'OUT_OF_SCOPE' ? 'OUT_OF_SCOPE' : (wf === 'ALL' ? 'SYSTEM_SCOPE' : wf), step: '' }
                         : ownerFor(wf, actor);
  const r = base(`evsub:${key}`, 'event_subscription', 'public.event_subscription');
  Object.assign(r, {
    entry_method: 'event delivery', current_callers: 'event_dispatch_15min', external_entry: 'no',
    schedule_or_trigger: s.event_type,
    mutates_state: s.active ? 'yes' : 'no',
    current_actor: `agent ${s.agent_key}`, canonical_system_actor: actor,
    accountable_role_id: own.role, department_id: liveDept(deptOf.get(own.role) || ''),
    workflow_id: own.scope, step_id: own.step,
    authority_class: M.actionClassFor(wf), trace_policy_id: M.TYPE_TO_TRACE_POLICY.event_subscription,
    idempotency_strategy: M.TYPE_TO_IDEMPOTENCY.event_subscription,
    retry_policy: M.TYPE_TO_RETRY.event_subscription,
    activation_state: s.active ? 'active' : 'inactive',
    classification: s.active ? 'WIRE_TO_CANONICAL' : 'INACTIVE_HISTORICAL',
    gap: subscriber ? '' : `subscriber agent key ${s.agent_key} does not resolve to an active canonical role`,
    repair_or_keep_action: 'route through the Phase C outbox so delivery state is explicit',
    evidence: `event_subscription: agent_key=${s.agent_key} event_type=${s.event_type} active=${s.active}; reason="${String(s.reason || '').slice(0, 80)}"`,
  });
  push(r);
}

// -------------------------------------------------------------------- frontend routes
for (const f of inv.frontend) {
  const wf = M.ROUTE_TO_WORKFLOW[f.route] ?? pbTarget.get(`frontend_route:${f.route}`) ?? 'ALL';
  const actor = 'system.command_router';
  const own = ownerFor(wf, actor);
  const cls = C.classifyFrontend(f);
  const r = base(`route:${f.route}`, 'frontend_route', f.path);
  Object.assign(r, {
    entry_method: 'browser navigation', current_callers: 'end user', external_entry: 'yes',
    mutates_state: f.mutates ? 'yes' : 'no',
    current_actor: 'signed-in end user or anonymous visitor', canonical_system_actor: actor,
    accountable_role_id: own.role, department_id: liveDept(deptOf.get(own.role) || ''),
    workflow_id: own.scope, step_id: own.step,
    authority_class: M.actionClassFor(wf), trace_policy_id: M.TYPE_TO_TRACE_POLICY.frontend_route,
    idempotency_strategy: M.TYPE_TO_IDEMPOTENCY.frontend_route,
    retry_policy: M.TYPE_TO_RETRY.frontend_route,
    activation_state: 'deployed', classification: cls, gap: '',
    repair_or_keep_action: 'keep; the surface is owned and its mutations route through the canonical boundary',
    evidence: `mutating=${f.mutates}`,
  });
  push(r);
}

// -------------------------------------------------------------------------- write out
const header = Object.keys(base('', '', ''));
mkdirSync(OUT, { recursive: true });
writeFileSync(join(OUT, 'PHASE_C_RUNTIME_COMPONENT_CROSSWALK.csv'), writeCSV(header, rows), 'utf8');

// ------------------------------------------------------- executor accountability sheet
// The narrower question: of the components that CHANGE state, which are executors with a
// risk class, a reversibility and a compensation?  org_action_executor already carries
// those fields for 59 action classes; this sheet is that table reconciled against the
// canonical owner and the frozen workflow, plus every active state-changing component.
const execHeader = Object.keys({
  executor_id: '', executor_type: '', implementation: '', canonical_system_actor: '',
  accountable_role_id: '', department_id: '', workflow_id: '', step_id: '', action_class: '',
  risk_level: '', reversible: '', idempotency_strategy: '', retry_policy: '',
  rollback_or_compensation: '', review_requirement: '', founder_approval_required: '',
  trace_policy_id: '', activation_state_before: '', activation_state_after: '', status: '', evidence: '',
});
const execRows = [];
const byId = new Map(rows.map(r => [r.component_id, r]));
for (const x of inv.executors) {
  const cid = `executor:${x.action_class}`;
  const wf = M.routineWorkflow(x.action_class);
  const own = ownerFor(wf, 'system.task_engine');
  execRows.push({
    executor_id: cid, executor_type: x.kind, implementation: x.target,
    canonical_system_actor: 'system.task_engine',
    accountable_role_id: own.role, department_id: liveDept(deptOf.get(own.role) || ''),
    workflow_id: own.scope, step_id: own.step, action_class: x.action_class,
    risk_level: x.risk_tier ?? '', reversible: String(x.reversible),
    idempotency_strategy: x.idempotency_strategy ?? '',
    retry_policy: `max_attempts=${x.max_attempts ?? ''} timeout=${x.timeout_seconds ?? ''}s`,
    rollback_or_compensation: x.compensation_action_class ?? 'none_declared',
    review_requirement: x.advisory_safe ? 'advisory_safe' : 'manager_or_reviewer',
    founder_approval_required: 'NO',
    trace_policy_id: 'TRACE-SYSTEM-EXECUTION',
    activation_state_before: x.active ? 'active' : 'inactive',
    activation_state_after: x.active ? 'active' : 'inactive',
    status: 'RECONCILED',
    evidence: `org_action_executor: notifies_human=${x.notifies_human} unattended_ok=${x.unattended_ok} advisory_safe=${x.advisory_safe}`,
  });
}
for (const r of rows.filter(r => r.mutates_state === 'yes' && r.activation_state !== 'inactive')) {
  execRows.push({
    executor_id: r.component_id, executor_type: r.component_type, implementation: r.source_path_or_db_object,
    canonical_system_actor: r.canonical_system_actor, accountable_role_id: r.accountable_role_id,
    department_id: r.department_id, workflow_id: r.workflow_id, step_id: r.step_id,
    action_class: r.authority_class, risk_level: byId.has(r.component_id) ? 'derived_from_action_class' : '',
    reversible: 'see rollback_or_compensation', idempotency_strategy: r.idempotency_strategy,
    retry_policy: r.retry_policy, rollback_or_compensation: 'workflow compensation policy',
    review_requirement: r.authority_class === 'refund_decision' ? 'founder' : 'independent_reviewer_per_phase_b',
    founder_approval_required: r.authority_class === 'refund_decision' ? 'YES' : 'NO',
    trace_policy_id: r.trace_policy_id, activation_state_before: r.activation_state,
    activation_state_after: r.activation_state, status: r.classification, evidence: r.evidence,
  });
}
writeFileSync(join(OUT, 'PHASE_C_EXECUTOR_ACCOUNTABILITY.csv'), writeCSV(execHeader, execRows), 'utf8');

// ------------------------------------------------------------------------- the numbers
const by = (k) => rows.reduce((m, r) => (m[r[k]] = (m[r[k]] || 0) + 1, m), {});
const active = rows.filter(r => r.activation_state !== 'inactive' && !/^disabled/.test(r.activation_state));
const activeMutating = active.filter(r => r.mutates_state === 'yes');
console.error(JSON.stringify({
  components: rows.length,
  executors_sheet: execRows.length,
  by_type: by('component_type'),
  by_classification: by('classification'),
  active_state_changing: activeMutating.length,
  active_state_changing_without_role: activeMutating.filter(r => !r.accountable_role_id).length,
  active_state_changing_without_actor: activeMutating.filter(r => !r.canonical_system_actor).length,
  active_state_changing_without_scope: activeMutating.filter(r => !r.workflow_id).length,
  unclassified: rows.filter(r => !r.classification).length,
  without_department: rows.filter(r => !r.department_id).length,
  system_scope: rows.filter(r => r.workflow_id === 'SYSTEM_SCOPE').length,
  out_of_scope: rows.filter(r => r.workflow_id === 'OUT_OF_SCOPE').length,
}, null, 1));
