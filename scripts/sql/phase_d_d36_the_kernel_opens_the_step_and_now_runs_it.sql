-- =================================================================================================
-- Phase D — D36. The kernel opens the step, and now it runs it.
--
-- THE FINDING. fn_phase_d_handler_execute had two real callers, fn_phase_d_drive_workflow and
-- fn_phase_d_step_cases, and both are harnesses. The driver says so in its own header: "IT IS NOT A
-- BUSINESS PATH AND DOES NOT CLAIM TO BE ONE." So 257 of 257 frozen steps carried a handler binding,
-- an effect contract and two typed schemas, and public.phase_d_effect_ledger held 0 rows, because
-- nothing a customer, a founder or a cron job can cause ever reached the handler.
--
-- THE ACCEPTANCE AUDIT DIAGNOSED THIS AS "the kernel has no application caller either" — measured as
-- 0 edge-function callers, 0 active cron and 0 triggers on fn_kernel_workflow_start,
-- fn_kernel_signal_submit and fn_kernel_step_complete. Re-measured with comments and string literals
-- stripped, that is not what is there. Fifteen of the twenty "callers" name the routine inside a
-- comment, an error hint or a `where proname = '...'` board query. A mention is not a call. What IS
-- there, one hop further out:
--
--     18 trigger functions on live tables  ->  fn_kernel_source_emit
--                                          ->  fn_kernel_signal_submit / fn_kernel_trigger_submit
--                                          ->  fn_kernel_workflow_start / fn_kernel_step_complete
--
--       inquiries      trg_inquiry_received, trg_customer_abandon_ban
--       transactions   qd_notify_refund_request, qd_on_refund_resolved, trg_reveal_receipt
--       quotes         notify_new_quote_sms
--       notifications  fn_invite_status_on_send
--       + quote_items, inquiry_matches, agent_actions, supplier_dues, assistant_logs,
--         contact_messages, documents, inbound_messages, leads, pdpl_requests, wa_messages
--
--     supabase/functions/os_api/index.ts   ->  fn_founder_command_submit / fn_founder_command_clarify
--                                          ->  fn_kernel_workflow_start
--
--     cron job 278 phase_c_outbox_deliver_1min, every minute
--                                          ->  fn_kernel_outbox_deliver -> fn_kernel_event_consume
--                                          ->  fn_kernel_workflow_start + fn_kernel_step_complete
--
-- The estate reaches the kernel. It did not reach Phase D, because Phase D built its executor BESIDE
-- the kernel's advance path instead of inside it. (fn_phase_c_step_advance, which the remediation
-- plan called the connected sibling, is retired: its entire body raises.)
--
-- WHERE THE DISPATCH GOES, AND THE FIRST ATTEMPT THAT WAS WRONG. It looked like fn_kernel_open_step
-- was the single choke point every step passes through. It is not. Wiring the dispatch there alone
-- was applied, and its own control refused it: starting W05 produced no dispatch row at all, because
-- fn_kernel_workflow_start opens a run's FIRST step INLINE and never calls fn_kernel_open_step. Two
-- openers, not one — and the first step is precisely the step an autonomous arrival causes, so the
-- one-site version would have missed the path this whole phase is about. The dispatch therefore
-- lives in ONE routine, fn_phase_d_dispatch_step, called from BOTH, so the two cannot drift.
--
--     fn_kernel_workflow_start   -> inline first step run        -> fn_phase_d_dispatch_step
--     fn_kernel_step_complete    -> fn_kernel_open_step (successor) -> fn_phase_d_dispatch_step
--     fn_kernel_handoff_accept   -> fn_kernel_open_step (received)  -> fn_phase_d_dispatch_step
--
-- WHAT THE HANDLER IS GIVEN, AND WHY IT IS NOT A FIXTURE. fn_phase_d_drive_workflow builds its
-- inputs as `'ZZ DEMO — ' || key`, one demo string per declared key. That is correct for a harness
-- and disqualifying for a business path. Measured across all 257 input schemas there are only 20
-- distinct declared keys, and 249 of the 257 steps declare the same three:
--
--       workflow_record         249    the run, its frozen workflow and this step
--       prior_accepted_outputs  249    the completed step runs of THIS run and their effects
--       applicable_policy       249    the rules, gates and founder gate THIS step is bound to
--
-- All three resolve from real state. The remaining 17 keys belong to W01's eight strategy steps;
-- those that resolve from a real table are resolved, and those that do not — external evidence, a
-- cash budget nothing records — are left UNRESOLVED and the step refuses naming them. An unresolved
-- key is never filled with a placeholder. A handler given an invented input produces an invented
-- effect, and this phase exists to remove exactly that.
--
-- A DISPATCH MUST NOT KILL THE BUSINESS WRITE THAT CAUSED IT. A customer inserting an inquiry fires
-- trg_inquiry_received; if a Phase D handler five frames down refuses at the capability boundary,
-- the insert must still commit. fn_kernel_source_emit already solved this — it records the fault in
-- kernel_adapter_failure and returns — and this follows it. The refusal is not swallowed: every
-- dispatch, executed or refused, lands in public.phase_d_dispatch with its refusal code, and
-- fn_phase_d_dispatch_state() reads those rows.
-- =================================================================================================


-- ---- 1. THE DISPATCH LEDGER ---------------------------------------------------------------------
-- Gate 3 asks whether a real application path reaches the handler. That question needs evidence with
-- a row per attempt, not a status column someone typed. A refusal is evidence too: "21 steps refuse
-- at the capability boundary" is only a measurement if the 21 refusals exist somewhere.

create table if not exists public.phase_d_dispatch (
  dispatch_id     bigint generated always as identity primary key,
  step_run_id     bigint      not null,
  run_id          bigint      not null,
  step_id         text        not null,
  workflow_id     text        not null,
  opened_by_kind  text        not null,
  opened_by_ref   text        not null,
  actor_role_id   text        not null,
  outcome         text        not null
    check (outcome in ('EXECUTED','REFUSED','INPUTS_UNRESOLVED','DEPTH_LIMIT','DISPATCH_OFF')),
  refusal_code    text        not null default '',
  sqlstate_code   text        not null default '',
  reason          text        not null default '',
  unresolved_keys text[]      not null default '{}',
  inputs_provenance jsonb     not null default '{}'::jsonb,
  effect_id       bigint,
  dispatch_depth  int         not null default 0,
  dispatched_at   timestamptz not null default now()
);

create index if not exists phase_d_dispatch_step_idx    on public.phase_d_dispatch (step_id, dispatched_at desc);
create index if not exists phase_d_dispatch_run_idx     on public.phase_d_dispatch (run_id, dispatched_at desc);
create index if not exists phase_d_dispatch_outcome_idx on public.phase_d_dispatch (outcome, dispatched_at desc);

alter table public.phase_d_dispatch enable row level security;
revoke all on public.phase_d_dispatch from public, anon, authenticated;
grant select, insert on public.phase_d_dispatch to service_role;

comment on table public.phase_d_dispatch is
  'One row per Phase D dispatch attempted from a kernel opener. A refused dispatch is recorded with '
  'its refusal code rather than raised, so a handler refusal cannot roll back the business write '
  'that caused the step to open. This table is the evidence for the application-connection '
  'measurement; a step with no row here has never been reached by any path.';


-- ---- 2. THE INPUTS, RESOLVED FROM REAL STATE ----------------------------------------------------
-- Returns {inputs, provenance, resolved, unresolved}. It resolves; it never invents. A key it cannot
-- back with a real row is returned in `unresolved` and left OUT of `inputs`, which makes
-- fn_phase_d_schema_validate refuse the call by name — the refusal the caller needs to read.

create or replace function public.fn_phase_d_step_inputs(p_step_run_id bigint)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $fn$
declare
  sr public.phase_c_workflow_step_run%rowtype;
  r  public.phase_c_workflow_run%rowtype;
  w  public.phase_b_workflow%rowtype;
  s  public.phase_b_workflow_step%rowtype;
  b  public.phase_d_handler_binding%rowtype;
  v_keys   text[];
  v_k      text;
  v_val    jsonb;
  v_src    text;
  v_in     jsonb := '{}'::jsonb;
  v_prov   jsonb := '{}'::jsonb;
  v_res    text[] := '{}';
  v_unres  text[] := '{}';
  v_cmd    bigint;
begin
  select * into sr from public.phase_c_workflow_step_run where step_run_id = p_step_run_id;
  if not found then
    raise exception 'fn_phase_d_step_inputs: no step run %', p_step_run_id using errcode = '23503';
  end if;
  select * into r  from public.phase_c_workflow_run    where run_id  = sr.run_id;
  select * into s  from public.phase_b_workflow_step   where step_id = sr.step_id;
  select * into w  from public.phase_b_workflow        where workflow_id = r.workflow_id;
  select * into b  from public.phase_d_handler_binding where step_id = sr.step_id;

  select coalesce(sc.required_keys, '{}') into v_keys
    from public.phase_d_handler_schema sc
   where sc.step_id = sr.step_id and sc.schema_kind = 'input';
  if v_keys is null then v_keys := '{}'; end if;

  -- The founder command that caused this run, if one did. W01 is started by
  -- fn_founder_command_submit through os_api, so for that workflow this is the real instruction.
  select l.command_id into v_cmd
    from public.founder_command_workflow_link l where l.run_id = sr.run_id limit 1;
  if v_cmd is null then v_cmd := r.command_id; end if;

  foreach v_k in array v_keys loop
    v_val := null; v_src := null;

    if v_k = 'workflow_record' then
      v_src := 'phase_c_workflow_run + phase_b_workflow + phase_b_workflow_step';
      v_val := jsonb_build_object(
        'run_id', r.run_id, 'workflow_id', r.workflow_id, 'workflow_name', w.workflow_name,
        'domain', w.domain, 'criticality', w.criticality, 'primary_object', w.primary_object,
        'business_object_id', nullif(btrim(coalesce(r.business_object_id,'')),''),
        'object_version', r.object_version, 'run_state', r.state, 'start_event', r.start_event,
        'run_accountable_role_id', r.accountable_role_id, 'opened_at', r.opened_at,
        'step_id', sr.step_id, 'step_name', s.step_name,
        'step_accountable_role_id', sr.accountable_role_id,
        'required_inputs', s.required_inputs, 'required_output', s.required_output,
        'acceptance_criteria', s.acceptance_criteria, 'closure_criteria', s.closure_criteria);

    elsif v_k = 'prior_accepted_outputs' then
      -- THE RECORD of what this run has already accepted. The kernel stores the accepted output's
      -- sha256, never the payload, so the hash IS the identity of the accepted output and the
      -- effect ledger row IS what it produced. Nothing here is reconstructed from prose.
      -- A count of 0 is a fact about a first step, not an absence: the object is returned with
      -- count 0 rather than an empty array, because fn_phase_d_schema_validate reads [] as missing.
      v_src := 'phase_c_workflow_step_run(completed) + phase_d_effect_ledger, this run only';
      select jsonb_build_object(
               'count', count(*),
               'run_id', sr.run_id,
               'outputs', coalesce(jsonb_agg(jsonb_build_object(
                   'step_id', pr.step_id, 'step_run_id', pr.step_run_id,
                   'output_hash', pr.output_hash, 'authority_result', pr.authority_result,
                   'gates_evaluated', pr.gates_evaluated, 'finished_at', pr.finished_at,
                   'effects', coalesce((select jsonb_agg(jsonb_build_object(
                                  'effect_id', el.effect_id, 'effect_type', el.effect_type,
                                  'effect_object_id', el.effect_object_id,
                                  'result_reference', el.result_reference,
                                  'state_after', el.state_after) order by el.effect_id)
                                from public.phase_d_effect_ledger el
                               where el.step_run_id = pr.step_run_id), '[]'::jsonb))
                 order by pr.step_run_id), '[]'::jsonb))
        into v_val
        from public.phase_c_workflow_step_run pr
       where pr.run_id = sr.run_id
         and pr.state = 'completed'
         and pr.step_run_id < sr.step_run_id;

    elsif v_k = 'applicable_policy' then
      v_src := 'phase_d_rule_enforcement + phase_d_gate_contract, in scope for this step';
      v_val := jsonb_build_object(
        'step_id', sr.step_id, 'founder_gate', b.founder_gate,
        'rule_count', coalesce(cardinality(b.rule_ids), 0),
        'gate_count', coalesce(cardinality(b.gate_ids), 0),
        'rules', coalesce((select jsonb_agg(jsonb_build_object(
                    'rule_id', re.rule_id, 'rule_type', re.rule_type,
                    'enforcement_kind', re.enforcement_kind, 'enforcement_point', re.enforcement_point,
                    'refusal_code', re.refusal_code, 'applies_when', re.applies_when,
                    'status', re.status) order by re.rule_id)
                  from public.phase_d_rule_enforcement re
                 where re.rule_id = any (coalesce(b.rule_ids,'{}'))), '[]'::jsonb),
        'gates', coalesce((select jsonb_agg(jsonb_build_object(
                    'gate_id', gc.gate_id, 'predicate_kind', gc.predicate_kind,
                    'refusal_code', gc.refusal_code, 'evidence_keys', to_jsonb(gc.evidence_keys),
                    'correction_owner', gc.correction_owner) order by gc.gate_id)
                  from public.phase_d_gate_contract gc
                 where gc.gate_id = any (coalesce(b.gate_ids,'{}'))), '[]'::jsonb));

    elsif v_k in ('founder_instruction','founder_mandate') then
      v_src := 'founder_command via founder_command_workflow_link / phase_c_workflow_run.command_id';
      select jsonb_build_object(
               'command_id', fc.command_id, 'outcome', fc.outcome, 'state', fc.state,
               'priority', fc.priority, 'command_owner_role_id', fc.command_owner_role_id,
               'primary_role_id', fc.primary_role_id,
               'founder_initiated_only', fc.founder_initiated_only,
               'refund_semantics', fc.refund_semantics, 'created_at', fc.created_at)
        into v_val
        from public.founder_command fc where fc.command_id = v_cmd;

    elsif v_k = 'current_approved_founder_policies' then
      v_src := 'governance_policy + policy_rules(active)';
      select jsonb_build_object(
               'governance_policy_count', (select count(*) from public.governance_policy),
               'governance_policy', coalesce((select jsonb_agg(jsonb_build_object(
                   'id', gp.id, 'domain', gp.domain, 'policy', gp.policy, 'rule', gp.rule,
                   'enforced_by', gp.enforced_by, 'enforcement', gp.enforcement,
                   'owner_dept', gp.owner_dept) order by gp.id)
                   from public.governance_policy gp), '[]'::jsonb),
               'policy_rules', coalesce((select jsonb_agg(jsonb_build_object(
                   'id', pr2.id, 'name', pr2.name, 'severity', pr2.severity, 'scope', pr2.scope)
                   order by pr2.id) from public.policy_rules pr2 where pr2.active), '[]'::jsonb))
        into v_val;

    elsif v_k in ('current_company_objective','approved_company_objectives_and_department_mandates') then
      v_src := 'company_goals(active) + org_departments(active)';
      select jsonb_build_object(
               'goal_count', (select count(*) from public.company_goals where active),
               'goals', coalesce((select jsonb_agg(jsonb_build_object(
                   'key', cg.key, 'goal', cg.goal, 'metric', cg.metric,
                   'target_value', cg.target_value, 'unit', cg.unit, 'period', cg.period,
                   'owner_dept', cg.owner_dept, 'horizon', cg.horizon, 'deadline', cg.deadline)
                   order by cg.sort, cg.key) from public.company_goals cg where cg.active), '[]'::jsonb),
               'departments', coalesce((select jsonb_agg(jsonb_build_object(
                   'dept_key', od.dept_key, 'name', od.name) order by od.dept_key)
                   from public.org_departments od where od.active), '[]'::jsonb))
        into v_val;

    elsif v_k = 'department_mandates' then
      v_src := 'org_departments(active)';
      select jsonb_build_object(
               'count', count(*),
               'departments', coalesce(jsonb_agg(jsonb_build_object(
                   'dept_key', od.dept_key, 'name', od.name, 'charter', od.charter,
                   'north_star', od.north_star) order by od.dept_key), '[]'::jsonb))
        into v_val
        from public.org_departments od where od.active;

    elsif v_k = 'kpi_tree' then
      v_src := 'company_goals(active) grouped by owner_dept';
      select jsonb_build_object(
               'metric_count', (select count(*) from public.company_goals where active),
               'by_department', coalesce(jsonb_object_agg(q.dept, q.metrics), '{}'::jsonb))
        into v_val
        from (select coalesce(nullif(btrim(cg.owner_dept),''),'(unassigned)') as dept,
                     jsonb_agg(jsonb_build_object('key', cg.key, 'metric', cg.metric,
                       'target_value', cg.target_value, 'unit', cg.unit) order by cg.key) as metrics
                from public.company_goals cg where cg.active group by 1) q;

    elsif v_k = 'current_company_state' then
      v_src := 'measured counts: active goals, active departments, open runs, open tasks';
      select jsonb_build_object(
               'measured_at', now(),
               'active_goals', (select count(*) from public.company_goals where active),
               'active_departments', (select count(*) from public.org_departments where active),
               'open_workflow_runs', (select count(*) from public.phase_c_workflow_run
                                       where closed_at is null),
               'open_tasks', (select count(*) from public.phase_c_task where closed_at is null))
        into v_val;

    elsif v_k in ('strategy_options','strategy_option','current_baseline','issued_initiatives',
                  'complete_ownership_and_measurement_setup') then
      -- These are produced by an EARLIER step of the same run. They resolve only once that step has
      -- completed; before that they are genuinely absent and the step must wait, not guess.
      v_src := 'prior completed step runs of this run';
      select jsonb_build_object(
               'produced_by_count', count(*),
               'produced_by', coalesce(jsonb_agg(jsonb_build_object(
                 'step_id', pr.step_id, 'output_hash', pr.output_hash,
                 'finished_at', pr.finished_at) order by pr.step_run_id), '[]'::jsonb))
        into v_val
        from public.phase_c_workflow_step_run pr
       where pr.run_id = sr.run_id and pr.state = 'completed' and pr.step_run_id < sr.step_run_id;
      if coalesce((v_val->>'produced_by_count')::int, 0) = 0 then
        v_val := null;   -- nothing has produced it yet: unresolved, not an empty pass
      end if;

    else
      -- external_and_internal_evidence, current_cash_budget_and_commitments, budget_envelope,
      -- resource_envelope. NO TABLE IN THIS ESTATE HOLDS THESE. Naming them here as unresolved is
      -- the honest answer; filling them with a placeholder would make the step complete on a fact
      -- it never had.
      v_val := null;
      v_src := null;
    end if;

    if v_val is null or v_val = 'null'::jsonb then
      v_unres := v_unres || v_k;
    else
      v_in   := v_in   || jsonb_build_object(v_k, v_val);
      v_prov := v_prov || jsonb_build_object(v_k, v_src);
      v_res  := v_res  || v_k;
    end if;
  end loop;

  return jsonb_build_object(
    'step_run_id', p_step_run_id, 'step_id', sr.step_id, 'run_id', sr.run_id,
    'declared_keys', to_jsonb(v_keys),
    'inputs', v_in, 'provenance', v_prov,
    'resolved', to_jsonb(v_res), 'unresolved', to_jsonb(v_unres));
end
$fn$;

-- A fresh CREATE is granted EXECUTE to PUBLIC. PUBLIC is named first: a revoke from anon alone is a
-- silent no-op while the grant is held through PUBLIC.
revoke execute on function public.fn_phase_d_step_inputs(bigint) from public, anon, authenticated;
grant  execute on function public.fn_phase_d_step_inputs(bigint) to service_role;

comment on function public.fn_phase_d_step_inputs(bigint) is
  'Resolves the input keys a step declares from real database state, and returns the ones it cannot '
  'back with a real row in `unresolved` rather than filling them. fn_phase_d_drive_workflow builds '
  'the same keys as ZZ DEMO strings, which is correct for a harness and disqualifying for a '
  'business path.';


-- ---- 3. THE DISPATCH ITSELF ---------------------------------------------------------------------
-- ONE routine, called from BOTH openers. It never raises for a business reason: every outcome,
-- including a refusal, becomes a row in public.phase_d_dispatch and the caller carries on.

create or replace function public.fn_phase_d_dispatch_step(p_input jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $fn$
declare
  sr public.phase_c_workflow_step_run%rowtype;
  v_step_run bigint := nullif(p_input->>'step_run_id','')::bigint;
  v_actor    text   := nullif(btrim(coalesce(p_input->>'actor_role_id','')),'');
  v_kind     text   := coalesce(nullif(btrim(p_input->>'opened_by_kind'),''),'(unstated)');
  v_ref      text   := coalesce(nullif(btrim(p_input->>'opened_by_ref'),''),'(unstated)');
  v_idem     text   := coalesce(nullif(btrim(p_input->>'idempotency_key'),''),'');
  v_wf       text;
  v_on       text;
  v_depth    int;
  v_in       jsonb;
  v_res      jsonb;
  v_unres    text[];
  v_err      text;
  v_code     text;
begin
  if v_step_run is null or v_actor is null then
    raise exception 'fn_phase_d_dispatch_step: step_run_id and actor_role_id are required (got %, %)',
      coalesce(v_step_run::text,'(null)'), coalesce(v_actor,'(null)') using errcode = '22023';
  end if;

  select * into sr from public.phase_c_workflow_step_run where step_run_id = v_step_run;
  if not found then
    raise exception 'fn_phase_d_dispatch_step: no step run %', v_step_run using errcode = '23503';
  end if;

  -- A step with no binding or no effect contract is not a Phase D step. Say so and return; it is
  -- not a refusal and does not belong in the ledger as one.
  if not exists (select 1 from public.phase_d_handler_binding hb where hb.step_id = sr.step_id)
     or not exists (select 1 from public.phase_d_step_effect se where se.step_id = sr.step_id) then
    return jsonb_build_object('dispatched', false, 'outcome', 'NO_BINDING', 'step_id', sr.step_id);
  end if;

  select b2.workflow_id into v_wf from public.phase_d_handler_binding b2 where b2.step_id = sr.step_id;
  if v_idem = '' then v_idem := 'kernel|' || sr.run_id || '|' || sr.step_id; end if;

  v_on    := lower(coalesce(nullif(btrim(current_setting('app.phase_d_dispatch', true)),''), 'on'));
  v_depth := coalesce(nullif(btrim(current_setting('app.phase_d_dispatch_depth', true)),'')::int, 0);

  if v_on = 'off' then
    insert into public.phase_d_dispatch
      (step_run_id, run_id, step_id, workflow_id, opened_by_kind, opened_by_ref, actor_role_id,
       outcome, refusal_code, reason, dispatch_depth)
    values (v_step_run, sr.run_id, sr.step_id, v_wf, v_kind, v_ref, v_actor,
            'DISPATCH_OFF', 'pd_dispatch_off',
            'app.phase_d_dispatch is off for this transaction', v_depth);
    return jsonb_build_object('dispatched', false, 'outcome', 'DISPATCH_OFF');
  end if;

  if v_depth >= 64 then
    -- The handler completes the step, which opens the successor, which arrives back here. That is
    -- the workflow driving itself and it is intended; 64 is far past the longest frozen workflow
    -- and exists so a cycle in the registry cannot exhaust the stack instead of reporting itself.
    insert into public.phase_d_dispatch
      (step_run_id, run_id, step_id, workflow_id, opened_by_kind, opened_by_ref, actor_role_id,
       outcome, refusal_code, reason, dispatch_depth)
    values (v_step_run, sr.run_id, sr.step_id, v_wf, v_kind, v_ref, v_actor,
            'DEPTH_LIMIT', 'pd_dispatch_depth_limit',
            format('dispatch depth %s reached at step %s', v_depth, sr.step_id), v_depth);
    return jsonb_build_object('dispatched', false, 'outcome', 'DEPTH_LIMIT', 'depth', v_depth);
  end if;

  perform set_config('app.phase_d_dispatch_depth', (v_depth + 1)::text, true);

  begin
    v_in := public.fn_phase_d_step_inputs(v_step_run);
    select array_agg(x) into v_unres
      from jsonb_array_elements_text(coalesce(v_in->'unresolved','[]'::jsonb)) x;
    v_unres := coalesce(v_unres, '{}');

    if cardinality(v_unres) > 0 then
      -- NOT filled in. A step whose declared inputs no real source produces is a measurement of how
      -- far the application actually reaches, and it belongs in the ledger as one.
      insert into public.phase_d_dispatch
        (step_run_id, run_id, step_id, workflow_id, opened_by_kind, opened_by_ref, actor_role_id,
         outcome, refusal_code, reason, unresolved_keys, inputs_provenance, dispatch_depth)
      values (v_step_run, sr.run_id, sr.step_id, v_wf, v_kind, v_ref, v_actor,
              'INPUTS_UNRESOLVED', 'pd_input_unresolved',
              format('%s of the %s declared input keys resolve from no real source: %s',
                     cardinality(v_unres),
                     jsonb_array_length(coalesce(v_in->'declared_keys','[]'::jsonb)),
                     array_to_string(v_unres, ', ')),
              v_unres, coalesce(v_in->'provenance','{}'::jsonb), v_depth);
      perform set_config('app.phase_d_dispatch_depth', v_depth::text, true);
      return jsonb_build_object('dispatched', false, 'outcome', 'INPUTS_UNRESOLVED',
                                'unresolved', to_jsonb(v_unres));
    end if;

    v_res := public.fn_phase_d_handler_execute(jsonb_build_object(
      'step_run_id',       v_step_run,
      'actor_role_id',     v_actor,
      'idempotency_key',   v_idem || '|phase_d',
      'inputs',            v_in->'inputs',
      'execution_context', 'production',
      'correlation_id',    p_input->>'correlation_id',
      'causation_id',      'kernel_dispatch:' || v_kind || ':' || v_ref));

    insert into public.phase_d_dispatch
      (step_run_id, run_id, step_id, workflow_id, opened_by_kind, opened_by_ref, actor_role_id,
       outcome, inputs_provenance, effect_id, dispatch_depth)
    values (v_step_run, sr.run_id, sr.step_id, v_wf, v_kind, v_ref, v_actor,
            'EXECUTED', coalesce(v_in->'provenance','{}'::jsonb),
            nullif(v_res#>>'{phase_d,business_effect,effect_id}','')::bigint, v_depth);

    perform set_config('app.phase_d_dispatch_depth', v_depth::text, true);
    return jsonb_build_object('dispatched', true, 'outcome', 'EXECUTED',
             'handler_id', v_res#>>'{phase_d,handler_id}',
             'effect_id',  v_res#>'{phase_d,business_effect,effect_id}');

  exception
    when others then
      -- A HANDLER REFUSAL MUST NOT ROLL BACK THE BUSINESS WRITE THAT CAUSED THE STEP TO OPEN.
      -- A customer inserting an inquiry fires trg_inquiry_received; if the handler five frames down
      -- refuses at the capability boundary, the insert still commits and the refusal is recorded
      -- here with its code. This is fn_kernel_source_emit's own pattern, not a new leniency:
      -- nothing is swallowed, and fn_phase_d_dispatch_state() reads these rows.
      v_err  := SQLERRM;
      v_code := coalesce((regexp_match(v_err, '\((pd_[a-z0-9_]+|k[0-9]+_[a-z0-9_]+)\)'))[1], 'pd_unclassified');
      insert into public.phase_d_dispatch
        (step_run_id, run_id, step_id, workflow_id, opened_by_kind, opened_by_ref, actor_role_id,
         outcome, refusal_code, sqlstate_code, reason, dispatch_depth)
      values (v_step_run, sr.run_id, sr.step_id, v_wf, v_kind, v_ref, v_actor,
              'REFUSED', v_code, SQLSTATE, left(v_err, 1000), v_depth);
      perform set_config('app.phase_d_dispatch_depth', v_depth::text, true);
      return jsonb_build_object('dispatched', false, 'outcome', 'REFUSED',
                                'refusal_code', v_code, 'sqlstate', SQLSTATE);
  end;
end
$fn$;

revoke execute on function public.fn_phase_d_dispatch_step(jsonb) from public, anon, authenticated;
grant  execute on function public.fn_phase_d_dispatch_step(jsonb) to service_role;

comment on function public.fn_phase_d_dispatch_step(jsonb) is
  'The single Phase D dispatch. Called from fn_kernel_workflow_start (which opens a run first step '
  'inline) and from fn_kernel_open_step (successors and accepted handoffs). Never raises for a '
  'business reason: every outcome becomes a row in public.phase_d_dispatch.';


-- ---- 4. THE TWO OPENERS -------------------------------------------------------------------------
-- Both bodies below are the LIVE definitions read out with pg_get_functiondef and spliced, so every
-- line except the declared local and the dispatch call is byte-identical to what was running.
-- GENERATED SPLICE — fn_kernel_open_step
CREATE OR REPLACE FUNCTION public.fn_kernel_open_step(p_input jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_pd_dispatch jsonb := '{}'::jsonb;  -- D36
  s public.phase_b_workflow_step%rowtype;
  v_run       bigint := nullif(p_input->>'run_id','')::bigint;
  v_step      text   := nullif(btrim(coalesce(p_input->>'step_id','')), '');
  v_owner     text   := nullif(btrim(coalesce(p_input->>'owner_role_id','')), '');
  v_src_kind  text   := coalesce(nullif(p_input->>'source_kind',''), 'workflow_progression');
  v_src_ref   text   := coalesce(nullif(p_input->>'source_ref',''), 'kernel:step_engine');
  v_command   bigint := nullif(p_input->>'command_id','')::bigint;
  v_priority  text   := coalesce(nullif(p_input->>'priority',''), 'P2');
  v_object    text   := coalesce(nullif(p_input->>'business_object_id',''), '');
  v_in_hash   text   := coalesce(nullif(p_input->>'input_hash',''), '');
  v_reason    text   := coalesce(nullif(p_input->>'opened_because',''), '(no reason stated)');
  v_step_run  bigint;
  v_task      bigint;
  v_st_trace  bigint;
  v_tk_trace  bigint;
  v_tk_parent bigint;
  v_wf        text;
  v_idem      text;
begin
  if v_run is null or v_step is null or v_owner is null then
    raise exception 'fn_kernel_open_step: run_id, step_id and owner_role_id are all required (got %, %, %)',
      coalesce(v_run::text,'(null)'), coalesce(v_step,'(null)'), coalesce(v_owner,'(null)')
      using errcode = '22023';
  end if;

  select * into s from public.phase_b_workflow_step where step_id = v_step;
  if not found then
    raise exception 'fn_kernel_open_step: % is not in the frozen Phase B step registry — fail closed',
      v_step using errcode = '23503';
  end if;
  select workflow_id into v_wf from public.phase_c_workflow_run where run_id = v_run;
  if v_wf is null then
    raise exception 'fn_kernel_open_step: no workflow run %', v_run using errcode = '23503';
  end if;
  if v_wf is distinct from s.workflow_id then
    raise exception 'fn_kernel_open_step: run % is workflow % and step % belongs to % — refused',
      v_run, v_wf, v_step, s.workflow_id using errcode = '23514';
  end if;
  -- Owners are never defaulted. A step whose owner does not resolve is not opened.
  if not public.fn_phase_c_actor_may_own(v_owner) then
    raise exception 'fn_kernel_open_step: % does not resolve to an active canonical role, so step % is not opened',
      v_owner, v_step using errcode = '23514';
  end if;

  -- phase_c_step_run_live_uk is UNIQUE (run_id, step_id) WHERE state is not terminal, so a second
  -- live step run for the same step is refused by the index. Report it as the specific thing it is.
  if exists (select 1 from public.phase_c_workflow_step_run r
              where r.run_id = v_run and r.step_id = v_step
                and r.state not in ('completed','cancelled','failed','superseded','skipped')) then
    raise exception 'fn_kernel_open_step: run % already has a live step run for % — a second one would be a duplicate of work in flight',
      v_run, v_step using errcode = '23505';
  end if;

  v_idem := s.idempotency_scope || '|' || v_run || '|' || v_step || '|kernel';

  -- No trace_id on the insert: z90_phase_c_step_run_trace_subject mints TRACE-STEP AFTER INSERT
  -- and parents it to the run's root trace.
  insert into public.phase_c_workflow_step_run
    (run_id, step_id, accountable_role_id, reviewer_role_id, state, attempt_no,
     input_hash, output_hash, gates_evaluated, authority_result, idempotency_key)
  values (v_run, v_step, v_owner, coalesce(s.independent_reviewer_role_id,''), 'active', 1,
          v_in_hash, '', '[]'::jsonb, 'pending: the step has not been executed yet', v_idem)
  returning step_run_id into v_step_run;
  if v_step_run is null then
    raise exception 'fn_kernel_open_step: the step run insert produced no row for %', v_step
      using errcode = '23502';
  end if;

  select trace_id into v_st_trace from public.phase_c_workflow_step_run where step_run_id = v_step_run;
  if v_st_trace is null then
    raise exception 'fn_kernel_open_step: step run % has no trace', v_step_run using errcode = '23502';
  end if;

  -- EXACTLY ONE task, on the same deterministic key fn_kernel_workflow_start uses. That key is
  -- also what makes the legacy delivery fan-out a no-op rather than a duplicate.
  v_task := public.fn_phase_c_task_create(jsonb_build_object(
    'source_kind', v_src_kind, 'source_ref', v_src_ref,
    'command_id', v_command, 'run_id', v_run, 'workflow_id', s.workflow_id, 'step_id', v_step,
    'accountable_role_id', v_owner,
    'objective', format('%s (%s) for %s — opened because %s',
                        s.step_id, s.step_name, coalesce(nullif(v_object,''),'this run'), v_reason),
    'required_inputs', s.required_inputs,
    'requested_output', s.required_output,
    'acceptance_criteria', s.acceptance_criteria,
    'closure_criteria', s.closure_criteria,
    'priority', v_priority,
    'reviewer_required', (coalesce(s.independent_reviewer_role_id,'') <> ''),
    'reviewer_role_id', coalesce(s.independent_reviewer_role_id,''),
    'idempotency_key', 'run:' || v_run || ':step:' || v_step));
  if v_task is null then
    raise exception 'fn_kernel_open_step: no task was created for run % step %', v_run, v_step
      using errcode = '23502';
  end if;

  select trace_id into v_tk_trace from public.phase_c_task where task_id = v_task;
  select parent_trace_id into v_tk_parent from public.phase_c_trace where trace_id = v_tk_trace;
  if v_tk_trace is null or v_tk_parent is null then
    raise exception 'fn_kernel_open_step: task % has trace % with parent % — a task without its parented trace is refused',
      v_task, coalesce(v_tk_trace::text,'null'), coalesce(v_tk_parent::text,'null')
      using errcode = '23502';
  end if;

  -- ---- PHASE D DISPATCH (D36) ------------------------------------------------------------------
  -- The step is open, owned, tasked and traced. If the frozen registry binds a deterministic Phase D
  -- handler to it, this is where that handler runs — not in a harness, and not behind an endpoint
  -- nothing calls. fn_phase_d_dispatch_step never raises: a refusal is recorded in
  -- public.phase_d_dispatch, because a handler refusing five frames down must not roll back the
  -- business write that caused the step to open.
  v_pd_dispatch := public.fn_phase_d_dispatch_step(jsonb_build_object(
    'step_run_id', v_step_run, 'actor_role_id', v_owner,
    'opened_by_kind', v_src_kind, 'opened_by_ref', v_src_ref,
    'idempotency_key', v_idem, 'correlation_id', p_input->>'correlation_id'));

  return jsonb_build_object('step_run_id', v_step_run, 'task_id', v_task, 'step_id', v_step,
    'owner_role_id', v_owner, 'step_trace_id', v_st_trace, 'task_trace_id', v_tk_trace,
    'reviewer_required', (coalesce(s.independent_reviewer_role_id,'') <> ''),
    'reviewer_role_id', coalesce(s.independent_reviewer_role_id,''),
    'idempotency_key', v_idem);
end $function$
;

-- GENERATED SPLICE — fn_kernel_workflow_start
CREATE OR REPLACE FUNCTION public.fn_kernel_workflow_start(p_input jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_pd_dispatch jsonb := '{}'::jsonb;  -- D36
  w  public.phase_b_workflow%rowtype;
  s  public.phase_b_workflow_step%rowtype;
  v_wf        text   := nullif(btrim(coalesce(p_input->>'workflow_id','')), '');
  v_object    text   := nullif(btrim(coalesce(p_input->>'business_object_id','')), '');
  v_source_k  text   := nullif(btrim(coalesce(p_input->>'source_kind','')), '');
  v_source_r  text   := nullif(btrim(coalesce(p_input->>'source_ref','')), '');
  v_by        text   := nullif(btrim(coalesce(p_input->>'requested_by','')), '');
  v_command   bigint := nullif(p_input->>'command_id','')::bigint;
  v_version   bigint := coalesce(nullif(p_input->>'object_version','')::bigint, 1);
  v_priority  text   := coalesce(nullif(p_input->>'priority',''), 'P2');
  v_ctx       jsonb  := coalesce(p_input->'trigger_ctx', '{}'::jsonb);
  v_corr      text;
  v_caus      text;
  v_dedupe    text;
  v_run       bigint;
  v_step_run  bigint;
  v_task      bigint;
  v_outbox    bigint;
  v_run_trace bigint;
  v_step_trace bigint;
  v_task_trace bigint;
  v_task_parent bigint;
  v_owner     text;
  v_step_owner text;
  v_kind      text;
  v_start_event text;
  v_input_hash text;
  -- Scalars, not a RECORD: a plpgsql record read after a SELECT INTO that matched nothing is a
  -- trap this estate has already paid for once.
  v_prior_run   bigint;
  v_prior_state text;
  v_prior_trace bigint;
  v_prior_step  bigint;
  v_prior_task  bigint;
begin
  -- ---- 0. a consumer may not re-enter the producer ----------------------------------------
  perform public.fn_kernel_assert_not_in_delivery('fn_kernel_workflow_start');

  if v_wf is null or v_object is null or v_source_r is null or v_by is null then
    raise exception 'fn_kernel_workflow_start: workflow_id, business_object_id, source_ref and requested_by are all required (got %, %, %, %)',
      coalesce(v_wf,'(null)'), coalesce(v_object,'(null)'), coalesce(v_source_r,'(null)'), coalesce(v_by,'(null)')
      using errcode = '22023';
  end if;
  if v_source_k not in ('founder_command','autonomous') then
    raise exception 'fn_kernel_workflow_start: source_kind must be founder_command or autonomous, got %',
      coalesce(v_source_k,'(null)') using errcode = '22023';
  end if;
  if v_source_k = 'founder_command' and v_command is null then
    raise exception 'fn_kernel_workflow_start: source_kind founder_command requires a command_id'
      using errcode = '22023';
  end if;
  v_corr := coalesce(nullif(btrim(p_input->>'correlation_id'),''), v_source_r);
  v_caus := coalesce(nullif(btrim(p_input->>'causation_id'),''), v_source_r);

  -- ---- (a) the workflow run ---------------------------------------------------------------
  select * into w from public.phase_b_workflow where workflow_id = v_wf;
  if not found then
    raise exception 'fn_kernel_workflow_start (a): % is not in the frozen Phase B workflow registry — fail closed',
      v_wf using errcode = '23503';
  end if;

  -- The accountable role comes from the registry and must RESOLVE. Never defaulted; there is no
  -- chief_of_staff fallback here and there will not be one.
  select kind, role_id into v_kind, v_owner from public.fn_phase_c_resolve_actor(w.accountable_role_id);
  if v_owner is null or v_kind is distinct from 'canonical' then
    raise exception 'fn_kernel_workflow_start (a): workflow % names accountable role %, which resolves to % — no run created',
      v_wf, w.accountable_role_id, coalesce(v_kind,'nothing') using errcode = '23514';
  end if;

  -- The start event is read from the frozen registry, never concatenated. A literal
  -- 'EV-W01-STARTED' once announced W01 for every command the company had ever received.
  v_start_event := public.fn_phase_c_lifecycle_event(v_wf, 'started');
  if v_start_event is null then
    raise exception 'fn_kernel_workflow_start (f): workflow % declares no .started event in phase_b_event',
      v_wf using errcode = '23503';
  end if;

  -- Idempotency, unchanged in shape from fn_phase_c_workflow_start so existing runs still match.
  v_dedupe := v_wf || ':' || v_object || ':' || v_version::text;
  select r.run_id, r.state, r.trace_id
    into v_prior_run, v_prior_state, v_prior_trace
    from public.phase_c_workflow_run r where r.dedupe_key = v_dedupe;
  if v_prior_run is not null then
    select sr.step_run_id into v_prior_step from public.phase_c_workflow_step_run sr
     where sr.run_id = v_prior_run order by sr.step_run_id limit 1;
    select t.task_id into v_prior_task from public.phase_c_task t
     where t.run_id = v_prior_run order by t.task_id limit 1;
    -- A second call creates NOTHING. Not a new run, not a second task, not a second event.
    return jsonb_build_object('ok', true, 'duplicate', true, 'run_id', v_prior_run,
      'workflow_id', v_wf, 'business_object_id', v_object, 'object_version', v_version,
      'state', v_prior_state, 'step_run_id', v_prior_step,
      'task_id', v_prior_task, 'trace_id', v_prior_trace,
      'dedupe_key', v_dedupe, 'created', '{}'::jsonb);
  end if;

  v_input_hash := encode(sha256(convert_to(
    v_wf || '|' || v_object || '|' || v_version::text || '|' || v_ctx::text, 'UTF8')), 'hex');

  insert into public.phase_c_workflow_run
    (workflow_id, business_object_id, object_version, start_event, accountable_role_id,
     state, dedupe_key, command_id)
  values (v_wf, v_object, v_version, v_start_event, v_owner, 'queued', v_dedupe, v_command)
  returning run_id into v_run;
  if v_run is null then
    raise exception 'fn_kernel_workflow_start (a): the workflow run insert produced no row for %', v_wf
      using errcode = '23502';
  end if;

  -- ---- (d.1) the ROOT trace, before anything hangs from it ---------------------------------
  v_run_trace := public.fn_phase_c_trace_write('TRACE-WORKFLOW', jsonb_build_object(
    'subject_kind','workflow_run', 'subject_ref', v_run::text, 'run_id', v_run,
    'command_id', v_command,
    'actor_role_id', v_owner, 'system_actor_id','system.workflow_engine',
    'input_hash', v_input_hash,
    'evidence_refs', jsonb_build_array(jsonb_build_object(
      'business_object_id', v_object, 'dedupe_key', v_dedupe, 'source_kind', v_source_k,
      'source_ref', v_source_r, 'requested_by', v_by, 'trigger_ctx', v_ctx)),
    'event_ids', jsonb_build_array(v_start_event),
    'state_before','', 'state_after','queued', 'status','open'));
  update public.phase_c_workflow_run set trace_id = v_run_trace where run_id = v_run;
  if v_run_trace is null then
    raise exception 'fn_kernel_workflow_start (d): the run has no root trace' using errcode = '23502';
  end if;

  -- The run is ACTIVE because its first step run is opened in this same transaction. The move is
  -- made as a declared transition (queued -> active) so z20_phase_c_workflow_state_guard and
  -- phase_b_workflow_transition are load-bearing rather than decorative.
  update public.phase_c_workflow_run set state = 'active' where run_id = v_run;

  -- ---- (b) the initial step run, at the REGISTRY entry step --------------------------------
  select * into s from public.phase_b_workflow_step
   where workflow_id = v_wf and step_no = 1;               -- UNIQUE (workflow_id, step_no)
  if not found then
    raise exception 'fn_kernel_workflow_start (b): workflow % declares no step_no = 1', v_wf
      using errcode = '23502';
  end if;

  select kind, role_id into v_kind, v_step_owner from public.fn_phase_c_resolve_actor(s.accountable_role_id);
  if v_step_owner is null or v_kind is distinct from 'canonical' then
    raise exception 'fn_kernel_workflow_start (c): step % names owner %, which resolves to % — no task created',
      s.step_id, s.accountable_role_id, coalesce(v_kind,'nothing') using errcode = '23514';
  end if;

  insert into public.phase_c_workflow_step_run
    (run_id, step_id, accountable_role_id, reviewer_role_id, state, attempt_no,
     input_hash, output_hash, gates_evaluated, authority_result, idempotency_key)
  values (v_run, s.step_id, v_step_owner, coalesce(s.independent_reviewer_role_id,''), 'active', 1,
          v_input_hash, '', '[]'::jsonb, 'pending: the step has not been executed yet',
          s.idempotency_scope || '|' || v_run || '|' || s.step_id || '|kernel')
  returning step_run_id into v_step_run;
  if v_step_run is null then
    raise exception 'fn_kernel_workflow_start (b): the step run insert produced no row for %', s.step_id
      using errcode = '23502';
  end if;

  -- The step run gets its own TRACE-STEP, parented to the run's root. phase_c_workflow_step_run
  -- has no trace guard trigger (only phase_c_task does), so an active step run with trace_id NULL
  -- is exactly what nobody notices — the first rehearsal of this file measured 6 of 11 step runs
  -- in that state, two of them created by this function.
  v_step_trace := public.fn_phase_c_trace_write('TRACE-STEP', jsonb_build_object(
    'subject_kind','step_run', 'subject_ref', v_step_run::text,
    'run_id', v_run, 'step_run_id', v_step_run, 'command_id', v_command,
    'actor_role_id', v_step_owner, 'system_actor_id','system.workflow_engine',
    'reviewer_role_id', coalesce(s.independent_reviewer_role_id,''),
    'authority_result','pending: the step has not been executed yet',
    'input_hash', v_input_hash,
    'evidence_refs', jsonb_build_array(jsonb_build_object(
      'step_id', s.step_id, 'step_name', s.step_name, 'entry_condition', s.entry_condition)),
    'state_before','', 'state_after','active', 'status','open'));
  update public.phase_c_workflow_step_run set trace_id = v_step_trace where step_run_id = v_step_run;
  update public.phase_c_trace set parent_trace_id = v_run_trace where trace_id = v_step_trace;
  if v_step_trace is null then
    raise exception 'fn_kernel_workflow_start (d): step run % has no trace', v_step_run
      using errcode = '23502';
  end if;

  -- ---- (c) EXACTLY ONE operational task -----------------------------------------------------
  -- Deterministic key. It is also the key the invariant check looks for: a founder command may
  -- have run:N:step:* work or cmd:N:* plan rows, never both.
  v_task := public.fn_phase_c_task_create(jsonb_build_object(
    'source_kind', v_source_k, 'source_ref', v_source_r,
    'command_id', v_command, 'run_id', v_run, 'workflow_id', v_wf, 'step_id', s.step_id,
    'accountable_role_id', v_step_owner,
    'objective', format('%s — %s: perform %s (%s) for %s.',
                        w.workflow_name, v_start_event, s.step_id, s.step_name, v_object),
    'required_inputs', s.required_inputs,
    'requested_output', s.required_output,
    'acceptance_criteria', s.acceptance_criteria,
    'closure_criteria', s.closure_criteria,
    'priority', v_priority,
    'reviewer_required', (coalesce(s.independent_reviewer_role_id,'') <> ''),
    'reviewer_role_id', coalesce(s.independent_reviewer_role_id,''),
    'idempotency_key', 'run:' || v_run || ':step:' || s.step_id));
  if v_task is null then
    raise exception 'fn_kernel_workflow_start (c): no operational task was created for run % step %',
      v_run, s.step_id using errcode = '23502';
  end if;

  -- ---- (d.2) the CHILD trace for the task, parented -----------------------------------------
  -- a00_phase_c_task_trace_guard mints it on INSERT and parents it to the command trace when the
  -- task carries a command_id, otherwise to the run trace. Both are roots; what is refused here is
  -- a task hanging from nothing.
  select trace_id into v_task_trace from public.phase_c_task where task_id = v_task;
  select parent_trace_id into v_task_parent from public.phase_c_trace where trace_id = v_task_trace;
  if v_task_trace is null or v_task_parent is null then
    raise exception 'fn_kernel_workflow_start (d): task % has trace % with parent % — a task without its parented trace is refused',
      v_task, coalesce(v_task_trace::text,'null'), coalesce(v_task_parent::text,'null')
      using errcode = '23502';
  end if;

  -- ---- (e) NO HANDOFF AT START -- K14 -------------------------------------------------------
  -- Deliberately empty, and named so a reader looking for the block that used to be here finds the
  -- reason rather than a gap. The entry step's outgoing handoff run is created by
  -- fn_kernel_step_complete when that step completes, from its accepted output. Creating it here
  -- as well produced TWO open handoff runs on one registry edge the moment the entry step
  -- completed, and the successor step could then never be opened.

  -- ---- (f) ONE factual event ----------------------------------------------------------------
  -- Emitted LAST, after the state it describes exists. Its consumer may not create any of it.
  v_outbox := public.fn_kernel_outbox_emit(jsonb_build_object(
    'event_id', v_start_event, 'producer', 'kernel:workflow_start',
    'object_version', v_version,
    'correlation_id', v_corr, 'causation_id', v_caus, 'source_id', v_source_r,
    'command_id', v_command, 'workflow_run_id', v_run, 'step_run_id', v_step_run,
    'trace_id', v_run_trace,
    'dedupe_value', 'kernel:started:' || v_dedupe,
    'payload', jsonb_build_object(
      'fact','workflow.started',
      'workflow_id', v_wf, 'workflow_run_id', v_run, 'step_id', s.step_id,
      'step_run_id', v_step_run, 'task_id', v_task, 'handoff_run_id', null,
      'business_object_id', v_object, 'object_version', v_version,
      'accountable_role_id', v_owner, 'step_accountable_role_id', v_step_owner,
      'source_kind', v_source_k, 'source_ref', v_source_r, 'requested_by', v_by,
      'trace_id', v_run_trace, 'input_hash', v_input_hash)));
  if v_outbox is null then
    raise exception 'fn_kernel_workflow_start (f): no event row was written for run %', v_run
      using errcode = '23502';
  end if;

  -- ---- all or nothing -----------------------------------------------------------------------
  if v_run is null or v_step_run is null or v_task is null or v_outbox is null
     or v_run_trace is null or v_step_trace is null or v_task_trace is null then
    raise exception 'fn_kernel_workflow_start incomplete: run=% step_run=% task=% outbox=% run_trace=% step_trace=% task_trace=%',
      v_run, v_step_run, v_task, v_outbox, v_run_trace, v_step_trace, v_task_trace
      using errcode = '23502';
  end if;

  -- ---- (g) PHASE D DISPATCH (D36) --------------------------------------------------------------
  -- THE FIRST STEP OF A RUN IS OPENED HERE, INLINE — this routine does not call fn_kernel_open_step.
  -- Wiring the dispatch only into fn_kernel_open_step therefore reached successors and handoffs and
  -- missed every run's first step, which is the step an autonomous arrival actually causes. Both
  -- openers call the same routine so the two paths cannot drift apart.
  v_pd_dispatch := public.fn_phase_d_dispatch_step(jsonb_build_object(
    'step_run_id', v_step_run, 'actor_role_id', v_step_owner,
    'opened_by_kind', v_source_k, 'opened_by_ref', v_source_r,
    'idempotency_key', s.idempotency_scope || '|' || v_run || '|' || s.step_id || '|kernel',
    'correlation_id', v_corr));

  return jsonb_build_object(
    'ok', true, 'duplicate', false,
    'run_id', v_run, 'workflow_id', v_wf, 'workflow_name', w.workflow_name,
    'business_object_id', v_object, 'object_version', v_version, 'dedupe_key', v_dedupe,
    'state','active', 'accountable_role_id', v_owner,
    'step_id', s.step_id, 'step_run_id', v_step_run, 'step_accountable_role_id', v_step_owner,
    'task_id', v_task, 'task_idempotency_key', 'run:' || v_run || ':step:' || s.step_id,
    'handoff_run_id', null, 'handoff_id', null,
    'run_trace_id', v_run_trace, 'step_trace_id', v_step_trace,
    'task_trace_id', v_task_trace, 'handoff_trace_id', null,
    'event_id', v_start_event, 'outbox_id', v_outbox,
    'correlation_id', v_corr, 'causation_id', v_caus, 'source_id', v_source_r,
    'command_id', v_command, 'source_kind', v_source_k, 'requested_by', v_by,
    'created', jsonb_build_object('run',1, 'step_run',1, 'task',1, 'traces',
      3,
      'handoff', 0, 'event',1));
end $function$
;

-- ---- 5. THE BOARD -------------------------------------------------------------------------------

-- ROUTINE REMOVED 7 September 2026. public.fn_phase_d_dispatch_state was dropped from the database with
-- everything else that did not belong to the new structure, and its definition is cut from
-- this file so re-applying the file cannot recreate it. The other routines defined here are
-- still running and are untouched.


revoke execute on function public.fn_phase_d_dispatch_state() from public, anon, authenticated;
grant  execute on function public.fn_phase_d_dispatch_state() to service_role;


-- ---- 6. THE CONTROL — PROVE IT FIRES, AND PROVE IT CANNOT SILENTLY NOT FIRE ---------------------
-- Everything the control creates is rolled back by a deliberate raise inside its own block. A check
-- that has never been seen to fail is not a check, so the negative direction is exercised too: with
-- app.phase_d_dispatch set to off, the same start must record DISPATCH_OFF and must NOT execute.
-- The first version of this file wired the dispatch into fn_kernel_open_step alone and THIS control
-- refused it — that is the only reason the missing first-step opener was found before it shipped.

do $ctl$
declare
  v_start   jsonb;
  v_run     bigint;
  v_wired   boolean;
  v_exec    int;
  v_unres   int;
  v_refused int;
  v_off     int;
  v_effects int;
  v_sample  text;
  v_report  text;
begin
  select bool_and(p.prosrc ~ '\mfn_phase_d_dispatch_step\s*\(') into v_wired
    from pg_proc p where p.pronamespace='public'::regnamespace
      and p.proname in ('fn_kernel_open_step','fn_kernel_workflow_start');
  if not coalesce(v_wired,false) then
    raise exception 'D36: one of the two openers does not name fn_phase_d_dispatch_step — the splice did not land.';
  end if;

  -- ---- POSITIVE CONTROL: a real workflow start must produce dispatch rows ----------------------
  begin
    v_start := public.fn_kernel_workflow_start(jsonb_build_object(
      'workflow_id', 'W05',
      'business_object_id', 'ZZ DEMO — d36 control ' || clock_timestamp()::text,
      'source_kind', 'autonomous',
      'source_ref', 'phase_d_d36_control:' || clock_timestamp()::text,
      'requested_by', 'phase_d_d36_control'));
    v_run := nullif(v_start->>'run_id','')::bigint;

    select count(*) filter (where outcome='EXECUTED'),
           count(*) filter (where outcome='INPUTS_UNRESOLVED'),
           count(*) filter (where outcome='REFUSED')
      into v_exec, v_unres, v_refused
      from public.phase_d_dispatch where run_id = v_run;
    select count(*) into v_effects from public.phase_d_effect_ledger where run_id = v_run;
    select string_agg(format('%s=%s%s', step_id, outcome,
             case when refusal_code not in ('','(none)') then '/'||refusal_code else '' end), ' '
             order by dispatch_id)
      into v_sample from public.phase_d_dispatch where run_id = v_run;

    v_report := format('POSITIVE run %s W05: EXECUTED=%s UNRESOLVED=%s REFUSED=%s effect_ledger=%s | %s',
                       v_run, v_exec, v_unres, v_refused, v_effects, coalesce(v_sample,'(none)'));

    if (v_exec + v_unres + v_refused) = 0 then
      raise exception 'D36 POSITIVE CONTROL FAILED: starting W05 opened a step and produced no phase_d_dispatch row. The dispatch is not on the open path.';
    end if;

    raise exception 'D36_CONTROL_ROLLBACK %', v_report;
  exception
    when others then
      if SQLERRM like 'D36_CONTROL_ROLLBACK%' then
        raise notice 'D36 %', substr(SQLERRM, 22);
      else
        raise exception 'D36 POSITIVE CONTROL FAILED: % (%)', SQLERRM, SQLSTATE;
      end if;
  end;

  -- ---- NEGATIVE CONTROL: the switch must actually switch it off -------------------------------
  begin
    perform set_config('app.phase_d_dispatch', 'off', true);
    v_start := public.fn_kernel_workflow_start(jsonb_build_object(
      'workflow_id', 'W05',
      'business_object_id', 'ZZ DEMO — d36 control off ' || clock_timestamp()::text,
      'source_kind', 'autonomous',
      'source_ref', 'phase_d_d36_control_off:' || clock_timestamp()::text,
      'requested_by', 'phase_d_d36_control'));
    v_run := nullif(v_start->>'run_id','')::bigint;

    select count(*) filter (where outcome='DISPATCH_OFF'),
           count(*) filter (where outcome='EXECUTED')
      into v_off, v_exec
      from public.phase_d_dispatch where run_id = v_run;

    if v_off = 0 then
      raise exception 'D36 NEGATIVE CONTROL FAILED: app.phase_d_dispatch=off produced no DISPATCH_OFF row — the switch does nothing.';
    end if;
    if v_exec > 0 then
      raise exception 'D36 NEGATIVE CONTROL FAILED: app.phase_d_dispatch=off still executed % handler(s).', v_exec;
    end if;

    raise exception 'D36_CONTROL_ROLLBACK NEGATIVE run %: DISPATCH_OFF=% EXECUTED=%', v_run, v_off, v_exec;
  exception
    when others then
      if SQLERRM like 'D36_CONTROL_ROLLBACK%' then
        raise notice 'D36 %', substr(SQLERRM, 22);
      else
        raise exception 'D36 NEGATIVE CONTROL FAILED: % (%)', SQLERRM, SQLSTATE;
      end if;
  end;
  perform set_config('app.phase_d_dispatch', 'on', true);

  -- ---- NO RESIDUE -----------------------------------------------------------------------------
  if (select count(*) from public.phase_d_dispatch) <> 0 then
    raise exception 'D36: the controls left % rows in phase_d_dispatch — they were meant to roll back.',
      (select count(*) from public.phase_d_dispatch);
  end if;
  if (select count(*) from public.phase_c_workflow_run
       where business_object_id like 'ZZ DEMO — d36 control%') <> 0 then
    raise exception 'D36: the controls left a workflow run behind.';
  end if;

  raise notice 'D36: the dispatch is wired into both kernel openers, fires on a real workflow start, refuses to fire when switched off, and left no residue.';
end
$ctl$;
