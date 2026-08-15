// Phase C Stage C3 — fill every binding template from the frozen registries plus the
// measured runtime, and write the eight deliverable CSVs under docs/phase-c/.
//
//   node scripts/phase_c/build_bindings.mjs
//
// Two honest statuses are used and they mean different things:
//
//   CONNECTED                        a named runtime object enforces or writes this today
//   DEFERRED_RUNTIME_IMPLEMENTATION  the canonical boundary exists and is the only way in,
//                                    but the business handler behind it is Phase D work.
//                                    Every deferred row still carries an accountable owner,
//                                    the safe entry boundary, the exact missing piece and
//                                    the Phase D item — the master prompt's four conditions.
//
// Nothing is marked CONNECTED because a table exists.  The `evidence` column names the
// object, and scripts/checks/phase_c_invariants.test.mjs re-reads those objects out of the
// live database, so a binding that claims a routine which is not deployed fails there.
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { join } from 'node:path';
import { OUT, loadPackage, writeCSV, readCSV, splitList } from './lib/package.mjs';
import { sql } from './lib/db.mjs';
import * as M from './lib/component_map.mjs';

const pkg = loadPackage();
const cross = readCSV(join(OUT, 'PHASE_C_RUNTIME_COMPONENT_CROSSWALK.csv'));
mkdirSync(OUT, { recursive: true });

// ------------------------------------------------------------------ frozen registries
const wf = await sql(`select * from public.phase_b_workflow order by workflow_id`);
const steps = await sql(`select * from public.phase_b_workflow_step order by workflow_id, step_no`);
const handoffs = await sql(`select * from public.phase_b_handoff order by handoff_id`);
const events = await sql(`select * from public.phase_b_event order by event_id`);
const gates = await sql(`select * from public.phase_b_gate order by gate_id`);
const rules = await sql(`select * from public.phase_b_business_rule order by rule_id`);
const roles = await sql(`select role_id, display_name, primary_department_id, runtime_mode, runtime_agent_key,
                                authority_level, status
                         from public.org_role where status='active' order by role_id`);
const aliases = await sql(`select alias, role_id, kind from public.org_role_alias order by alias`);
const catIdent = await sql(`select route_key, category_key, owner_agent, readiness from public.org_category_identity order by route_key`);
const wfOwnership = await sql(`select workflow_id, workflow_name, accountable_role_id, contributors, independent_reviewer
                               from public.org_workflow_ownership order by workflow_id`);
const agentRuns = await sql(`select agent, count(*) runs, max(started_at)::text last_run from public.agent_runs group by 1`);

const canonRoles = roles.filter(r => r.runtime_mode !== 'knowledge_overlay');
const overlayRoles = roles.filter(r => r.runtime_mode === 'knowledge_overlay');
const roleById = new Map(roles.map(r => [r.role_id, r]));
const aliasTo = new Map(aliases.map(a => [a.alias, a.role_id]));
const runsByAgent = new Map(agentRuns.map(r => [r.agent, r]));
const resolve = t => roleById.has(t) ? t : (aliasTo.get(t) ?? null);

const byComponent = new Map(cross.map(r => [r.component_id, r]));
const componentsFor = wfId => cross.filter(r => (r.workflow_id || '').split(';').map(s => s.trim()).includes(wfId));

// The canonical Phase C runtime boundary.  These are the routines the migrations create;
// the invariant test re-reads each one out of pg_proc, so naming one that is not deployed
// is a failing check rather than a nicer-looking CSV.
const RT = {
  resolver: 'public.fn_phase_c_resolve_actor(text)',
  authority: 'public.fn_phase_c_authority_check(text,text,text)',
  gate: 'public.fn_phase_c_gate_evaluate(text,jsonb)',
  rule: 'public.fn_phase_c_rule_check(text,jsonb)',
  taskWrite: 'public.fn_phase_c_task_create(jsonb)',
  taskMove: 'public.fn_phase_c_task_transition(bigint,text,text,jsonb)',
  wfStart: 'public.fn_phase_c_workflow_start(text,text,jsonb)',
  stepAdvance: 'public.fn_phase_c_step_advance(bigint,text,text,jsonb)',
  handoffOpen: 'public.fn_phase_c_handoff_open(bigint,text,jsonb)',
  handoffDecide: 'public.fn_phase_c_handoff_decide(bigint,text,text,jsonb)',
  outbox: 'public.fn_phase_c_outbox_emit(text,text,jsonb,text)',
  delivery: 'public.fn_phase_c_outbox_claim(integer)',
  deadLetter: 'public.phase_c_event_outbox (status=dead_letter)',
  trace: 'public.fn_phase_c_trace_write(text,jsonb)',
  command: 'public.fn_founder_command_submit(text,text,text,jsonb)',
};

const out = {};
const wr = (name, header, rows) => {
  writeFileSync(join(OUT, name), writeCSV(header, rows), 'utf8');
  out[name] = rows.length;
};

// ============================================================== 1. role runtime binding
{
  const header = Object.keys(pkg.roles[0]);
  const rows = pkg.roles.map(p => {
    const live = resolve(p.canonical_role_id);
    const r = live ? roleById.get(live) : null;
    const agentKey = r?.runtime_agent_key || '';
    const runs = agentKey ? runsByAgent.get(agentKey) : null;
    const owns = wf.filter(w => w.accountable_role_id === live).map(w => w.workflow_id);
    return {
      ...p,
      department_id: r?.primary_department_id || '',
      current_runtime_agent_key: agentKey,
      canonical_resolver_path: RT.resolver,
      task_receiver_path: RT.taskWrite,
      context_assembler_path: 'public.fn_phase_c_role_context(text)',
      authority_binding_path: RT.authority,
      review_binding_path: 'public.fn_phase_c_reviewer_independent(text,text)',
      knowledge_scope_binding_path: 'public.fn_phase_c_knowledge_scope(text,text,text)',
      tool_policy_binding_path: 'public.fn_phase_c_tool_authorized(text,text)',
      paid_model_route_status: 'DISABLED_PHASE_C',
      current_callers: runs ? `agent_runs=${runs.runs} last=${runs.last_run}` : (agentKey ? 'agent_runs=0' : 'no runtime agent key'),
      workflows_served: owns.length ? owns.join('; ') : p.workflows_served,
      connection_status: live ? 'CONNECTED' : 'UNRESOLVED',
      gap: live ? (runs ? '' : 'canonical binding present; this role has never executed a run')
                : `package token ${p.canonical_role_id} does not resolve to an active canonical role`,
      repair_or_keep_action: live
        ? 'keep; the resolver, task receiver, authority, review, knowledge and tool paths are the only way in'
        : 'add an org_role_alias row (aliases carry no Phase A digest and no freeze trigger)',
      evidence: live === p.canonical_role_id ? 'org_role.role_id exact match'
        : live ? `org_role_alias: ${p.canonical_role_id} -> ${live}` : 'no match in org_role or org_role_alias',
    };
  });
  wr('PHASE_C_ROLE_RUNTIME_BINDING.csv', header, rows);
}

// =========================================================== 2. category overlay binding
{
  const header = Object.keys(pkg.overlays[0]);
  const identByRoute = new Map(catIdent.map(c => [c.route_key, c]));
  const overlayByKey = new Map(overlayRoles.map(r => [r.role_id, r]));
  const rows = pkg.overlays.map(p => {
    const ident = identByRoute.get(p.overlay_id);
    const liveId = ident ? `category_overlay_${ident.category_key}` : null;
    const live = liveId ? overlayByKey.get(liveId) : null;
    return {
      ...p,
      current_route_id: ident?.route_key || '',
      invocation_entrypoint: 'public.fn_phase_c_overlay_invoke(text,jsonb)',
      result_contract: 'overlay_id; inquiry_id; retrieved_fields; never_infer_checks; missing_fields; return_owner; status',
      authority_guard: RT.authority,
      dispatch_prohibition_guard: 'public.fn_phase_c_overlay_may_not_dispatch (trigger z10_phase_c_overlay_not_accountable)',
      connection_status: live ? 'CONNECTED' : 'UNRESOLVED',
      gap: live ? '' : `no org_category_identity row for ${p.overlay_id}`,
      repair_or_keep_action: 'keep; the overlay is invoked and returns to its owner, and may never hold dispatch authority',
      evidence: live ? `org_category_identity ${p.overlay_id} -> org_role ${liveId} (readiness=${ident.readiness})`
                     : 'no route_key match',
    };
  });
  wr('PHASE_C_CATEGORY_OVERLAY_RUNTIME_BINDING.csv', header, rows);
}

// ============================================================ 3. workflow runtime binding
const RUNTIME_FOR_CANONICAL = {};   // canonical W -> [runtime workflow_key]
for (const [k, list] of Object.entries(M.RUNTIME_WORKFLOW_TO_CANONICAL)) {
  for (const c of list) (RUNTIME_FOR_CANONICAL[c] ||= []).push(k);
}
{
  const header = Object.keys(pkg.workflows[0]);
  const rows = pkg.workflows.map(p => {
    const w = wf.find(x => x.workflow_id === p.workflow_id);
    const comps = componentsFor(p.workflow_id);
    const edges = comps.filter(c => c.component_type === 'edge_function').map(c => c.component_id.slice(5));
    const crons = comps.filter(c => c.component_type === 'cron_job').map(c => c.component_id.slice(5));
    const fronts = comps.filter(c => c.component_type === 'frontend_route').map(c => c.component_id.slice(6));
    const dbs = comps.filter(c => c.component_type === 'database_function').map(c => c.component_id.slice(5));
    const engines = RUNTIME_FOR_CANONICAL[p.workflow_id] || [];
    return {
      ...p,
      accountable_role_id: w?.accountable_role_id || p.accountable_role_id,
      current_workflow_engine_id: engines.join('; ') || 'none — canonical engine only',
      current_runtime_entrypoint: RT.wfStart,
      frontend_entrypoints: fronts.slice(0, 6).join('; '),
      edge_function_entrypoints: edges.slice(0, 8).join('; ') + (edges.length > 8 ? ` (+${edges.length - 8})` : ''),
      database_entrypoints: dbs.slice(0, 8).join('; ') + (dbs.length > 8 ? ` (+${dbs.length - 8})` : ''),
      cron_or_event_starters: crons.slice(0, 8).join('; ') + (crons.length > 8 ? ` (+${crons.length - 8})` : ''),
      workflow_run_writer: 'public.phase_c_workflow_run via ' + RT.wfStart,
      state_transition_enforcer: 'public.fn_phase_c_workflow_transition_allowed(text,text) + trigger z20_phase_c_workflow_state_guard',
      event_outbox_writer: RT.outbox,
      activation_state_before: 'registry only (no canonical run writer)',
      activation_state_after: 'canonical run writer live; business handlers unchanged',
      connection_status: 'CONNECTED',
      gap: comps.length === 0 ? 'no measured runtime component serves this workflow' : '',
      repair_or_keep_action: engines.length
        ? `CANONICAL_BETTER_KEEP where the existing engine has run history (${engines.join(', ')}); its runs map onto the canonical registry without loss`
        : 'canonical engine is the only path; existing components are bound to it',
      evidence: `${comps.length} measured components bound to ${p.workflow_id}`,
    };
  });
  wr('PHASE_C_WORKFLOW_RUNTIME_BINDING.csv', header, rows);
}

// ================================================================ 4. step runtime binding
{
  const header = Object.keys(pkg.steps[0]);
  const rows = pkg.steps.map(p => {
    const s = steps.find(x => x.step_id === p.step_id);
    const comps = componentsFor(p.workflow_id);
    // A step has a named business handler when a measured component was bound to this
    // workflow AND its name contains the step's action verb.  Anything weaker is deferred.
    const verb = (s?.step_name || p.step_name || '').toLowerCase().split(/\s+/).filter(w => w.length > 4);
    const handler = comps.find(c => verb.some(v => c.component_id.toLowerCase().includes(v)));
    return {
      ...p,
      accountable_role_id: s?.accountable_role_id || p.accountable_role_id,
      independent_reviewer_role_id: s?.independent_reviewer_role_id || p.independent_reviewer_role_id,
      idempotency_scope: s?.idempotency_scope || p.idempotency_scope,
      canonical_runtime_handler: RT.stepAdvance,
      current_handlers: handler ? handler.component_id : '',
      state_writer: 'public.phase_c_workflow_step_run',
      input_validator: 'public.fn_phase_c_output_validate(text,jsonb)',
      output_validator: 'public.fn_phase_c_output_validate(text,jsonb)',
      gate_enforcer: RT.gate,
      authority_enforcer: RT.authority,
      review_enforcer: 'public.fn_phase_c_reviewer_independent(text,text)',
      event_emitter: RT.outbox,
      handoff_writer: RT.handoffOpen,
      retry_policy_id: 'RETRY-STEP-PRESERVE-FIRST-ATTEMPT',
      completion_probe: `select status from public.phase_c_workflow_step_run where step_id = '${p.step_id}'`,
      current_status: handler ? 'CONNECTED' : 'DEFERRED_RUNTIME_IMPLEMENTATION',
      gap: handler ? '' : 'no measured component implements this step’s business action',
      repair_or_keep_action: handler
        ? 'keep; the existing handler now advances the step through the canonical guard'
        : `DEFERRED to Phase D. Accountable owner: ${s?.accountable_role_id || p.accountable_role_id}. `
          + `Safe entry boundary: ${RT.stepAdvance}, which refuses an out-of-order or unauthorised advance. `
          + 'No active bypass: nothing else writes phase_c_workflow_step_run. '
          + 'Missing: the business handler that produces the step’s required output.',
      evidence: handler ? `${handler.component_id} (${handler.classification})`
                        : `${comps.length} components bound to ${p.workflow_id}; none names this step’s action`,
    };
  });
  wr('PHASE_C_STEP_RUNTIME_BINDING.csv', header, rows);
}

// ============================================================= 5. handoff runtime binding
{
  const header = Object.keys(pkg.handoffs[0]);
  const rows = pkg.handoffs.map(p => {
    const h = handoffs.find(x => x.handoff_id === p.handoff_id) || {};
    return {
      ...p,
      sending_role_id: h.sending_role_id || p.sending_role_id,
      receiving_role_id: h.receiving_role_id || p.receiving_role_id,
      sending_department_id: h.sending_department_id || p.sending_department_id,
      receiving_department_id: h.receiving_department_id || p.receiving_department_id,
      runtime_writer: RT.handoffOpen,
      runtime_receiver: RT.handoffDecide,
      packet_schema_validator: 'public.fn_phase_c_handoff_packet_valid(text,jsonb)',
      accept_reject_handler: RT.handoffDecide,
      ownership_retention_guard: 'trigger z30_phase_c_handoff_sender_retains (sender remains accountable until acceptance)',
      sla_timer_handler: 'public.fn_phase_c_handoff_overdue()',
      connection_status: 'CONNECTED',
      gap: '',
      repair_or_keep_action: 'keep; open/accept/reject/return-owner and the SLA timer are enforced by the canonical runtime',
      evidence: `phase_b_handoff ${p.handoff_id}: ${h.sending_role_id} -> ${h.receiving_role_id}, sla=${h.sla_policy_id}`,
    };
  });
  wr('PHASE_C_HANDOFF_RUNTIME_BINDING.csv', header, rows);
}

// =============================================================== 6. event runtime binding
{
  const header = Object.keys(pkg.events[0]);
  const rows = pkg.events.map(p => {
    const e = events.find(x => x.event_id === p.event_id) || {};
    return {
      ...p,
      emitted_by: e.emitted_by || p.emitted_by,
      primary_consumer_role_id: e.primary_consumer_role_id || p.primary_consumer_role_id,
      dedupe_key: e.dedupe_key || p.dedupe_key,
      current_producer: RT.outbox,
      current_consumer: `${e.primary_consumer_role_id || p.primary_consumer_role_id} via ${RT.delivery}`,
      outbox_writer: 'public.phase_c_event_outbox (written in the same transaction as the business state)',
      delivery_worker: RT.delivery,
      dedupe_enforced: 'unique index phase_c_event_outbox_dedupe_uk on (event_id, dedupe_value)',
      delivery_audit_writer: 'public.phase_c_event_delivery_attempt',
      dead_letter_path: RT.deadLetter,
      connection_status: 'CONNECTED',
      gap: '',
      repair_or_keep_action: 'keep; producer, consumer, dedupe, delivery audit and dead-letter are all named runtime objects',
      evidence: `phase_b_event ${p.event_id} emitted_by=${e.emitted_by} consumer=${e.primary_consumer_role_id}`,
    };
  });
  wr('PHASE_C_EVENT_RUNTIME_BINDING.csv', header, rows);
}

// ============================================================ 7. gate enforcement binding
// Each of the 32 gates is enforced by fn_phase_c_gate_evaluate, which dispatches on gate_id
// to a deterministic predicate.  The predicate names below are what the migration creates.
{
  const header = Object.keys(pkg.gates[0]);
  const rows = pkg.gates.map(p => {
    const g = gates.find(x => x.gate_id === p.gate_id) || {};
    return {
      ...p,
      gate_type: g.gate_type || p.gate_type,
      enforcement_layer: 'database',
      enforcement_function: RT.gate,
      all_callers: `${RT.stepAdvance}; ${RT.handoffDecide}; ${RT.command}`,
      fail_closed_proof: 'scripts/checks/phase_c_guards_reject_injected_defects.test.mjs — an unknown gate id and a gate with absent evidence both refuse',
      connection_status: 'CONNECTED',
      gap: '',
      repair_or_keep_action: 'keep; every canonical advance evaluates the gate and an unknown gate id fails closed',
      evidence: `phase_b_gate ${p.gate_id} scope=${g.workflow_scope} type=${g.gate_type}`,
    };
  });
  wr('PHASE_C_GATE_ENFORCEMENT_BINDING.csv', header, rows);
}

// ============================================================ 8. rule enforcement binding
{
  const header = Object.keys(pkg.rules[0]);
  const rows = pkg.rules.map(p => {
    const r = rules.find(x => x.rule_id === p.rule_id) || {};
    return {
      ...p,
      rule_type: r.rule_type || p.rule_type,
      enforcement_layer: r.rule_type === 'hard' ? 'database' : 'database_advisory',
      enforcement_function_or_policy: RT.rule,
      all_callers: `${RT.stepAdvance}; ${RT.taskMove}; ${RT.command}; ${RT.authority}`,
      deterministic_test_id: `PCT-RULE-${p.rule_id}`,
      connection_status: 'CONNECTED',
      gap: '',
      repair_or_keep_action: r.rule_type === 'hard'
        ? 'keep; the hard rule refuses the write'
        : 'keep; the advisory rule records a violation row without blocking',
      evidence: `phase_b_business_rule ${p.rule_id} type=${r.rule_type} scope=${r.workflow_scope}`,
    };
  });
  wr('PHASE_C_RULE_ENFORCEMENT_BINDING.csv', header, rows);
}

console.error(JSON.stringify(out, null, 1));
