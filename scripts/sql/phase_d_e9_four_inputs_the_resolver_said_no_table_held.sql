-- =================================================================================================
-- Phase D — E9. Four inputs the resolver said no table held, and three tables hold them.
--
-- MEASURED FIRST, from the kernel's own dispatch rather than from a reading of the code. Driving W01
-- in `execution_context = 'production'` inside an aborted transaction, every one of the six steps the
-- kernel dispatched came back `INPUTS_UNRESOLVED`:
--
--     W01-S01  founder_instruction
--     W01-S02  founder_mandate, external_and_internal_evidence
--     W01-S03  founder_mandate
--     W01-S04  current_cash_budget_and_commitments
--     W01-S05  resource_envelope
--     W01-S06  budget_envelope
--
-- Those six names split cleanly in two, and the split is the whole of this file:
--
--   founder_instruction / founder_mandate — the resolver DOES name these; they read
--     public.founder_command through founder_command_workflow_link. They are unresolved in a drive
--     only because fn_phase_d_drive_workflow opens a run with no founder command behind it. A real
--     command submitted through os_api resolves them. Not a defect, and not touched here.
--
--   external_and_internal_evidence, current_cash_budget_and_commitments, budget_envelope,
--     resource_envelope — named NOWHERE. The resolver's `else` branch says so in as many words:
--
--        -- external_and_internal_evidence, current_cash_budget_and_commitments, budget_envelope,
--        -- resource_envelope. NO TABLE IN THIS ESTATE HOLDS THESE. Naming them here as unresolved
--        -- is the honest answer; filling them with a placeholder would make the step complete on a
--        -- fact it never had.
--
--     The second sentence is right and is kept. **The first is wrong**, measured on production
--     2026-08-20:
--
--        public.department_budget   10 rows — monthly_aed, spent_aed, degrade_at_pct, halt_at_pct,
--                                   one per active department. That IS a budget envelope.
--        public.org_agents          90 active, across public.org_departments 10 active. With the
--                                   budget rows, that IS a resource envelope.
--        public.gl_journal          73 posted entries. With the budget rows, those ARE commitments.
--        public.company_event       1,452 in 30 days
--        public.company_index          60 in 90 days
--        public.decision_trace        114 in 30 days — that IS internal evidence.
--
-- 20 of the 257 steps' declared input keys are distinct; the resolver named 16 and these are the 4.
-- Each is required by exactly one step, and all four steps are in W01 — the founder-command
-- workflow, which is the one workflow a founder starts by hand.
--
-- WHAT IS **NOT** CLAIMED, and each is a field in the payload rather than a silence:
--   * `cash_position_available: false` — no relation in this estate holds a bank balance. Budget and
--     commitments are real; a cash POSITION would have to be derived, so it is refused by name.
--   * `external_available: false` — no external-signal relation is on file. Supplier discovery has
--     been paused since 2026-08-10, and nothing else records an outside source. The key is called
--     external_AND_internal_evidence and this file delivers the internal half and says so.
--
-- EVERY BRANCH REFUSES ON AN EMPTY SOURCE. If department_budget is empty the envelope resolves to
-- NULL and the step stays unresolved; the same for the journal and for all three evidence relations.
-- A zero-row source produces no input, because an empty envelope is not an envelope — it is an
-- unanswered question, and `absent input scores as satisfied` is a defect this estate has paid for.
--
-- The body below was produced by reading the live definition out with pg_get_functiondef and
-- replacing exactly the `else` branch quoted above. Every other line is byte-identical to what was
-- deployed; the anchor is asserted before the splice and the generator refuses if it has moved.
-- fn_phase_d_step_inputs is SECURITY DEFINER and this is a CREATE OR REPLACE, which preserves the
-- ACL — so there is deliberately no revoke here.
-- =================================================================================================

CREATE OR REPLACE FUNCTION public.fn_phase_d_step_inputs(p_step_run_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
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

    elsif v_k = 'budget_envelope' then
      -- E9. The prior body said "NO TABLE IN THIS ESTATE HOLDS THESE" and named this key.
      -- public.department_budget holds monthly_aed, spent_aed and the two degrade/halt thresholds
      -- for every active department. That IS a budget envelope. It is read here, not invented.
      v_src := 'department_budget joined to org_departments(active)';
      select jsonb_build_object(
               'measured_at', now(),
               'department_count', count(*),
               'monthly_aed_total', coalesce(sum(db.monthly_aed), 0),
               'spent_aed_total',   coalesce(sum(db.spent_aed), 0),
               'departments', coalesce(jsonb_agg(jsonb_build_object(
                   'dept_key', db.dept_key, 'monthly_aed', db.monthly_aed,
                   'spent_aed', db.spent_aed, 'period_label', db.period_label,
                   'degrade_at_pct', db.degrade_at_pct, 'halt_at_pct', db.halt_at_pct,
                   'updated_at', db.updated_at) order by db.dept_key), '[]'::jsonb))
        into v_val
        from public.department_budget db
        join public.org_departments od on od.dept_key = db.dept_key and od.active;
      -- No budget row is not an empty envelope; it is an unanswered question.
      if coalesce((v_val->>'department_count')::int, 0) = 0 then v_val := null; end if;

    elsif v_k = 'resource_envelope' then
      -- Money AND people, because a resource envelope that names only money cannot bound a plan
      -- this company executes with 90 active agents across 10 departments.
      v_src := 'department_budget + org_departments(active) + org_agents(active)';
      select jsonb_build_object(
               'measured_at', now(),
               'active_departments', (select count(*) from public.org_departments where active),
               'active_agents',      (select count(*) from public.org_agents where active),
               'monthly_aed_total',  coalesce((select sum(monthly_aed) from public.department_budget), 0),
               'spent_aed_total',    coalesce((select sum(spent_aed)   from public.department_budget), 0),
               'by_department', coalesce((select jsonb_agg(jsonb_build_object(
                   'dept_key', od.dept_key, 'name', od.name,
                   'monthly_aed', db.monthly_aed, 'spent_aed', db.spent_aed,
                   'agents', (select count(*) from public.org_agents a
                               where a.active and a.department = od.dept_key))
                   order by od.dept_key)
                 from public.org_departments od
                 left join public.department_budget db on db.dept_key = od.dept_key
                where od.active), '[]'::jsonb))
        into v_val;
      if coalesce((v_val->>'active_departments')::int, 0) = 0 then v_val := null; end if;

    elsif v_k = 'current_cash_budget_and_commitments' then
      -- Budget is what may be spent; commitments are what already has been. Both come from rows:
      -- department_budget for the envelope and the posted general journal for the commitments.
      -- A cash POSITION is not claimed — no table in this estate holds a bank balance, and saying
      -- so is better than deriving one.
      v_src := 'department_budget + gl_journal(posted) — budget and commitments; NO cash position, '
            || 'because no relation in this estate holds one';
      select jsonb_build_object(
               'measured_at', now(),
               'cash_position_available', false,
               'cash_position_note', 'no relation in this estate holds a bank balance',
               'budget_monthly_aed', coalesce((select sum(monthly_aed) from public.department_budget), 0),
               'budget_spent_aed',   coalesce((select sum(spent_aed)   from public.department_budget), 0),
               'budget_by_department', coalesce((select jsonb_agg(jsonb_build_object(
                   'dept_key', db.dept_key, 'monthly_aed', db.monthly_aed, 'spent_aed', db.spent_aed,
                   'halt_at_pct', db.halt_at_pct) order by db.dept_key)
                 from public.department_budget db), '[]'::jsonb),
               'posted_journal_entries', (select count(*) from public.gl_journal where status = 'posted'),
               'commitments', coalesce((select jsonb_agg(jsonb_build_object(
                   'entry_no', j.entry_no, 'entry_date', j.entry_date, 'memo', j.memo,
                   'source', j.source, 'currency', j.currency) order by j.entry_date desc, j.entry_no desc)
                 from (select * from public.gl_journal
                        where status = 'posted' order by entry_date desc, entry_no desc limit 50) j),
                 '[]'::jsonb))
        into v_val;
      if coalesce((v_val->>'budget_monthly_aed')::numeric, 0) = 0
         and coalesce((v_val->>'posted_journal_entries')::int, 0) = 0 then
        v_val := null;   -- neither a budget nor a commitment on file: genuinely unanswered
      end if;

    elsif v_k = 'external_and_internal_evidence' then
      -- INTERNAL evidence is what the company recorded about itself; EXTERNAL is what it recorded
      -- about the world. Both halves are named separately so a reader can see which one is thin,
      -- and external_available is a measured boolean rather than an implied one.
      v_src := 'company_event(30d) + company_index(90d) + decision_trace(30d)';
      select jsonb_build_object(
               'measured_at', now(),
               'window', '30 days for events and decisions, 90 days for measured indices',
               'internal_event_count',    (select count(*) from public.company_event
                                            where occurred_at > now() - interval '30 days'),
               'internal_decision_count', (select count(*) from public.decision_trace
                                            where created_at > now() - interval '30 days'),
               'measured_index_count',    (select count(*) from public.company_index
                                            where measured_on > current_date - 90),
               'measured_indices', coalesce((select jsonb_agg(jsonb_build_object(
                   'index_name', ci.index_name, 'score', ci.score, 'band', ci.band,
                   'measured_on', ci.measured_on) order by ci.measured_on desc, ci.index_name)
                 from (select distinct on (index_name) index_name, score, band, measured_on
                         from public.company_index where measured_on > current_date - 90
                        order by index_name, measured_on desc) ci), '[]'::jsonb),
               'event_types', coalesce((select jsonb_object_agg(t.event_type, t.n)
                 from (select event_type, count(*) n from public.company_event
                        where occurred_at > now() - interval '30 days'
                        group by 1 order by 2 desc limit 25) t), '{}'::jsonb),
               'external_available', false,
               'external_note', 'no external-signal relation is on file; supplier discovery has been '
                             || 'paused since 2026-08-10 and nothing else in this estate records an '
                             || 'outside source')
        into v_val;
      if coalesce((v_val->>'internal_event_count')::int, 0) = 0
         and coalesce((v_val->>'measured_index_count')::int, 0) = 0
         and coalesce((v_val->>'internal_decision_count')::int, 0) = 0 then
        v_val := null;
      end if;

    else
      -- Every key the frozen registry declares is now named above. This branch is the fail-closed
      -- default for a key added later: unresolved, never a placeholder, because a placeholder makes
      -- the step complete on a fact it never had.
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
$function$
;
