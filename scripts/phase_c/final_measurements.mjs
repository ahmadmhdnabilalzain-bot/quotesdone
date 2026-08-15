// Every number the Phase C deliverables quote, measured in one pass and written to
// docs/phase-c/_final_measurements.json.
//
//   node scripts/phase_c/final_measurements.mjs
//
// The reports quote this file rather than re-deriving numbers in prose, so a figure in a report
// and a figure in the database cannot drift apart between one paragraph and the next.
import { writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { OUT } from './lib/package.mjs';
import { sql } from './lib/db.mjs';

const one = async q => (await sql(q))[0];
const many = async q => await sql(q);

const m = {};
m.measured_at_utc = (await one(`select (now() at time zone 'utc')::text t`)).t;

m.frozen = await one(`select
  (select count(*) from public.org_departments where active) departments,
  (select count(*) from public.org_role where status='active' and runtime_mode<>'knowledge_overlay') roles,
  (select count(*) from public.org_role where status='active' and runtime_mode='knowledge_overlay') overlays,
  (select count(*) from public.phase_b_workflow) workflows,
  (select count(*) from public.phase_b_workflow_step) steps,
  (select count(*) from public.phase_b_handoff) handoffs,
  (select count(*) from public.phase_b_event) events,
  (select count(*) from public.phase_b_gate) gates,
  (select count(*) from public.phase_b_business_rule) rules,
  (select count(*) from public.fn_phase_a_baseline_drift()) phase_a_drift,
  (select count(*) from public.fn_phase_b_baseline_drift()) phase_b_drift,
  (select count(*) from public.fn_phase_b_effective_errata() where not resolved) unresolved_errata,
  (select count(*) from public.fn_phase_a_organization_violations()) phase_a_violations`);

m.components = await one(`select
  count(*) total,
  count(*) filter (where mutates_state) state_changing,
  count(*) filter (where mutates_state and activation_state not in ('inactive','disabled')) active_state_changing,
  count(*) filter (where mutates_state and activation_state not in ('inactive','disabled') and accountable_role_id='') active_unowned,
  count(*) filter (where classification='') unclassified,
  count(*) filter (where workflow_id='SYSTEM_SCOPE') system_scope,
  count(*) filter (where workflow_id='OUT_OF_SCOPE') out_of_scope,
  count(distinct accountable_role_id) distinct_owners,
  count(distinct canonical_system_actor) distinct_actors
  from public.phase_c_component`);

m.components_by_type = await many(
  `select component_type, count(*) n, count(*) filter (where mutates_state) mutating
   from public.phase_c_component group by 1 order by 1`);
m.components_by_classification = await many(
  `select classification, count(*) n from public.phase_c_component group by 1 order by 2 desc`);
m.components_by_actor = await many(
  `select canonical_system_actor, count(*) n from public.phase_c_component group by 1 order by 2 desc`);
m.no_caller_by_type = await many(
  `select component_type, count(*) n from public.phase_c_component
   where classification='NO_CALLER_UNCLASSIFIED' group by 1 order by 2 desc`);
m.inactive_historical = await many(
  `select component_id, activation_state, gap from public.phase_c_component
   where classification in ('INACTIVE_HISTORICAL','REPAIR_BEFORE_REACTIVATION') order by component_id`);

m.bindings = await one(`select
  (select count(*) from public.phase_c_role_binding) roles,
  (select count(*) from public.phase_c_role_binding where connection_status='CONNECTED') roles_connected,
  (select count(*) from public.phase_c_role_binding where gap like '%never executed%') roles_never_ran,
  (select count(*) from public.phase_c_overlay_binding) overlays,
  (select count(*) from public.phase_c_workflow_binding) workflows,
  (select count(*) from public.phase_c_step_binding) steps,
  (select count(*) from public.phase_c_step_binding where connection_status='CONNECTED') steps_connected,
  (select count(*) from public.phase_c_step_binding where connection_status='DEFERRED_RUNTIME_IMPLEMENTATION') steps_deferred,
  (select count(*) from public.phase_c_handoff_binding) handoffs,
  (select count(*) from public.phase_c_event_binding) events,
  (select count(*) from public.phase_c_gate_binding) gates,
  (select count(*) from public.phase_c_rule_binding) rules`);

m.steps_deferred_by_workflow = await many(
  `select workflow_id, count(*) n,
          count(*) filter (where connection_status='DEFERRED_RUNTIME_IMPLEMENTATION') deferred
   from public.phase_c_step_binding group by 1 order by 1`);

m.authority = await one(`select
  (select count(*) from public.phase_c_action_class) classes,
  (select count(*) from public.phase_c_action_class where founder_approval_required) founder_approval,
  (select count(*) from public.phase_c_action_class where founder_initiated_only) founder_initiated_only,
  (select string_agg(action_class, ', ') from public.phase_c_action_class where founder_approval_required) approval_class,
  (select string_agg(action_class, ', ' order by action_class) from public.phase_c_action_class where founder_initiated_only) reserved_classes,
  public.fn_phase_c_non_refund_founder_approvals() non_refund_awaiting_founder`);

m.what_reaches_founder = await many(`select * from public.v_phase_c_what_reaches_the_founder order by surface`);
m.notifies_human = await many(
  `select action_class, kind, risk_tier, advisory_safe, reversible
   from public.org_action_executor where notifies_human and active order by action_class`);

m.command_center = await one(`select
  (select count(*) from public.phase_c_command_rule) rules,
  (select count(*) from public.phase_c_command_intent) intents,
  (select count(*) from public.phase_c_command_specificity_signal) specificity_signals,
  (select count(*) from public.phase_c_command_state) states,
  (select count(*) from public.phase_c_command_transition) transitions,
  (select count(*) from public.phase_c_task_state) task_states,
  (select count(*) from public.phase_c_task_transition) task_transitions,
  (select count(*) from public.phase_c_founder_identity where active) founder_identities,
  (select count(*) from public.founder_command) commands_live,
  (select count(*) from public.phase_c_task) tasks_live,
  (select count(*) from public.founder_command_message) messages_live`);

m.trace_policies = await many(
  `select trace_policy_id, trace_required, completed_without_trace_allowed from public.phase_c_trace_policy order by 1`);
m.system_actors = await many(
  `select a.system_actor_id, a.accountable_role_id,
          (select count(*) from public.phase_c_component c where c.canonical_system_actor = a.system_actor_id) components
   from public.phase_c_system_actor a order by 3 desc`);

m.identity = await one(`select
  (select count(*) from public.org_role_alias) aliases,
  (select count(*) from public.org_role_alias where kind='packaged_role_id') packaged_aliases,
  (select count(*) from public.org_department_alias) dept_aliases,
  (select count(*) from public.phase_c_package_erratum) errata`);

m.cost = await one(`select
  (select count(*) from public.llm_route_health) routes,
  (select count(*) from public.llm_route_health where open_until > now()) held,
  (select min(open_until)::text from public.llm_route_health where open_until > now()) held_until,
  (select max(occurred_at)::text from public.ai_cost_log) last_paid_call,
  (select count(*) from public.ai_cost_log where occurred_at > timestamptz '2026-08-15 09:00:00+00') calls_during_phase_c,
  (select coalesce(sum(cost_aed),0)::text from public.ai_cost_log where occurred_at > timestamptz '2026-08-15 09:00:00+00') cost_aed_during_phase_c`);

m.activation = await one(`select
  (select count(*) from cron.job) cron_jobs,
  (select count(*) from cron.job where active) cron_active,
  (select count(*) from pg_trigger t join pg_class c on c.oid=t.tgrelid
     join pg_namespace n on n.oid=c.relnamespace
     where n.nspname='public' and not t.tgisinternal) triggers,
  (select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public') public_functions`);

m.invariants = await many(`select check_name, expected, actual, ok from public.fn_phase_c_invariants() order by check_name`);
m.invariants_summary = { total: m.invariants.length, passing: m.invariants.filter(r => r.ok).length };

m.wiring_gaps = await many(`select gap_id, gap, measurement from public.phase_b_phase_c_wiring_gap order by gap_id`);

writeFileSync(join(OUT, '_final_measurements.json'), JSON.stringify(m, null, 1), 'utf8');
console.error(`wrote docs/phase-c/_final_measurements.json  invariants ${m.invariants_summary.passing}/${m.invariants_summary.total}`);
console.error(JSON.stringify({ frozen: m.frozen, components: m.components, bindings: m.bindings,
                               authority: m.authority, cost: m.cost }, null, 1));
