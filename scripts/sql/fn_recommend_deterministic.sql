-- THE `recommend` ACTION CLASS IS A DETERMINATION FROM NUMBERS, NOT A PROMPT (MASTER_PLAN §5.3, 5 Sep 2026).
--
-- MEASURED before this file: 40 of 219 workflow steps carry action_class 'recommend', and every one of
-- them routed to the edge executor analytics_recommend, which imports _shared/llm.ts and asks the paid
-- model to "turn the live data into a decision". With the model held, 109 recommend steps closed
-- advisory on 4 Sep with stranded_reason 'executor runs on the held paid model; not queued' and 14 more
-- with 'left status=held' - the step was documented, never worked (see the memory
-- the-deterministic-close-documents-rather-than-performs). The doctrine says this reasoning is
-- ~95% deterministic code: a recommendation about a department's metrics is arithmetic over
-- employee_kpi (119 active, 89 measured daily at 03:30 UTC), employee_kpi_history (daily since
-- 11 Aug), metric_definition + metric_snapshot (14 company metrics, v_bi_scorecard) and
-- meta_insights (2 seed rows today; real rows when meta_sync runs). No model is needed to say
-- "attainment 71.1% of a 90% target, down 2.3 points since yesterday, owner bi_analyst".
--
-- CONTRACT with fn_action_invoke_rpc: it calls `select ... from public.<target>() t`, so every
-- parameter here has a default. When called with no step id it locates its own action_execution
-- row: the invoker walks queued rows of one action class in created_at order and marks each
-- succeeded/failed inside the same transaction before it reaches the next, so the FIRST queued
-- 'recommend' row of kind rpc is the one being executed. A direct call passes p_step_run_id.
--
-- THREE RETURN SHAPES, never the same one for different truths (error-and-empty-must-not-return-
-- the-same-value):
--   determination = 'recommendation'  -> `recommendations` is a non-empty jsonb array, every entry
--                                        stating the numbers it is built from;
--   determination = 'no_data'         -> `recommendations` is NULL; `inputs` states the zero counts
--                                        for the scope that was searched;
--   determination = 'no_scope'        -> the caller could not be located (no step, no actor, no
--                                        department); `inputs` says what was tried.
-- A step whose scope has KPIs but none of them measured is 'no_data' with inputs.kpi_rows > 0 and
-- inputs.kpi_measured = 0 - the reader can tell "nothing exists" from "nothing was measured".
--
-- The recommendation VARIES with its input: scope is the step's employee's department (via
-- fn_workflow_actor_resolve), the framing follows the step's own words (variance / root cause /
-- revise-or-retire / options / baseline / monitor-and-grade), and the ranked movers come from that
-- department's numbers. Proven on three departments in the PR that ships this.
--
-- Escalation: none to the model. Reading meta_insights is reading a table this company already
-- synced; the doctrine's "marketing agents reading ONLINE data" clause is the sync itself
-- (meta_sync), not the arithmetic over what it wrote. The previous edge executor remains deployed
-- and callable by hand; org_action_executor.params records it as model_escalation_target.

create or replace function public.fn_recommend_deterministic(p_step_run_id bigint default null, p_record boolean default true)
returns table(
  determination text, employee text, department text, workflow_key text, step_no integer, step text,
  outcome text, deliverable text, inputs jsonb, recommendations jsonb, used_llm boolean)
language plpgsql security definer set search_path to 'public', 'pg_temp' as $$
declare
  v_sid bigint := p_step_run_id;
  v_actor text; v_employee text; v_dept text; v_wf text; v_wfname text; v_step_no int; v_step text;
  v_run uuid; v_ctx jsonb := '{}'::jsonb; v_located text := 'p_step_run_id';
  v_framing text;
  v_kpis jsonb; v_kpi_rows int := 0; v_kpi_measured int := 0; v_kpi_missed int := 0; v_kpi_met int := 0;
  v_sc jsonb; v_sc_rows int := 0; v_sc_off int := 0;
  v_meta jsonb; v_meta_rows int := 0;
  v_recs jsonb; v_n int := 0;
  v_text text; v_one text; rec record;
  v_old_depts text[];
begin
  used_llm := false;
  -- 1. WHO IS ASKING. The step, or the queued action_execution row this invocation is running.
  if v_sid is null then
    select x.workflow_step_run_id, x.request->>'actor'
      into v_sid, v_actor
      from public.action_execution x
      join public.org_action_executor e on e.action_class = x.action_class and e.kind = 'rpc'
     where x.action_class = 'recommend' and x.status = 'queued'
     order by x.created_at limit 1;
    v_located := case when v_sid is not null then 'action_execution.workflow_step_run_id'
                      when v_actor is not null then 'action_execution.request.actor' else 'nothing queued' end;
  end if;
  if v_sid is not null then
    select s.actor, s.step_no, s.input->>'step', s.workflow_run_id, r.workflow_key, coalesce(r.context,'{}'::jsonb), w.name
      into v_actor, v_step_no, v_step, v_run, v_wf, v_ctx, v_wfname
      from public.workflow_step_run s
      join public.workflow_run r on r.id = s.workflow_run_id
      left join public.workflow w on w.workflow_key = r.workflow_key
     where s.id = v_sid;
    v_employee := public.fn_workflow_actor_resolve(v_run, v_actor);
  elsif v_actor is not null then
    v_employee := public.fn_org_agent_resolve(v_actor);
  end if;
  select o.department into v_dept from public.org_agents o where o.agent_key = v_employee and o.active;
  if v_dept is null then
    determination := 'no_scope'; employee := v_employee; department := null; workflow_key := v_wf; step_no := v_step_no; step := v_step;
    outcome := 'no determination: the caller resolves to no active employee, so there is no department whose numbers to read';
    deliverable := outcome;
    inputs := jsonb_build_object('located_by', v_located, 'step_run_id', v_sid, 'actor', v_actor, 'employee', v_employee);
    recommendations := null;
    return next; return;
  end if;
  -- metric_definition.owner_dept still speaks the pre-merge vocabulary (marketing, it, knowledge ...);
  -- org_departments.merged_into is the crosswalk, so a growth step also reads 'marketing' metrics.
  select coalesce(array_agg(d.dept_key), '{}') into v_old_depts
    from public.org_departments d where d.merged_into = v_dept or d.dept_key = v_dept;

  -- 2. THE STEP'S OWN WORDS choose the framing; the numbers are the same engine.
  v_framing := case
    when v_step ilike '%variance%' then 'variance'
    when v_step ilike '%root cause%' then 'root_cause'
    when v_step ilike '%revise%' or v_step ilike '%retire%' then 'revise_or_retire'
    when v_step ilike '%option%' then 'options'
    when v_step ilike '%grade%' or v_step ilike '%monitor%' then 'grade'
    when v_step ilike '%baseline%' then 'baseline'
    when v_step ilike '%define the metric%' then 'define'
    else 'recommend' end;

  -- 3. THE DEPARTMENT'S KPIs, with yesterday's (or the last recorded) value beside today's.
  with k as (
    select k.id, k.agent_key, k.metric, k.kpi, k.unit, k.cadence, k.target_value t, k.actual_value v,
           k.measured_at, k.no_measure_reason, k.serves_goal,
           (select h.actual_value from public.employee_kpi_history h
             where h.kpi_id = k.id and (k.measured_at is null or h.measured_at < k.measured_at - interval '1 hour')
             order by h.measured_at desc limit 1) prev,
           (select h.measured_on from public.employee_kpi_history h
             where h.kpi_id = k.id and (k.measured_at is null or h.measured_at < k.measured_at - interval '1 hour')
             order by h.measured_at desc limit 1) prev_on,
           (select count(*) from public.employee_kpi_history h
             where h.kpi_id = k.id and h.verdict = 'MISSED' and h.measured_on >= current_date - 14) missed_14d
      from public.employee_kpi k join public.org_agents a on a.agent_key = k.agent_key
     where k.active and a.department = v_dept
  ), s as (
    select k.*,
      case when v is null or t is null then null
           when t = 0 then case when v <= 0 then 100.0 else 0.0 end
           when unit = 'percent_max' then round(least(100.0, 100.0 * t / nullif(v,0)), 1)
           else round(100.0 * v / t, 1) end attainment
      from k
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'kpi_id', id, 'agent', agent_key, 'metric', metric, 'unit', unit, 'cadence', cadence,
           'target', t, 'actual', v, 'attainment', attainment,
           'verdict', case when v is null then 'NO DATA' when attainment is null then 'NO TARGET'
                           when attainment >= 100 then 'MET' when attainment >= 90 then 'NEAR' else 'MISSED' end,
           'measured_at', measured_at, 'previous', prev, 'previous_on', prev_on,
           'delta', case when v is not null and prev is not null then round(v - prev, 2) end,
           'missed_days_14d', missed_14d, 'no_measure_reason', no_measure_reason, 'serves_goal', serves_goal)
           order by (v is null), attainment nulls last, id), '[]'::jsonb),
         count(*), count(*) filter (where v is not null),
         count(*) filter (where v is not null and attainment is not null and attainment < 90),
         count(*) filter (where attainment >= 100)
    into v_kpis, v_kpi_rows, v_kpi_measured, v_kpi_missed, v_kpi_met
    from s;

  -- 4. THE COMPANY SCORECARD rows this department owns, with the prior snapshot beside the latest.
  select coalesce(jsonb_agg(jsonb_build_object(
           'metric_key', b.metric_key, 'label', b.label, 'owner_dept', b.owner_dept, 'value', b.value,
           'target', b.target, 'direction', b.direction, 'state', b.state, 'taken_at', b.taken_at,
           'previous', (select m.value from public.metric_snapshot m where m.metric_key = b.metric_key
                          and m.taken_at < b.taken_at - interval '20 hours' and m.error is null
                          order by m.taken_at desc limit 1),
           'delta', case when b.value is not null then round(b.value - (select m.value from public.metric_snapshot m
                          where m.metric_key = b.metric_key and m.taken_at < b.taken_at - interval '20 hours' and m.error is null
                          order by m.taken_at desc limit 1), 2) end)
           order by case b.state when 'OFF_TARGET' then 0 when 'BEHIND' then 1 when 'ERROR' then 2 when 'UNMEASURED' then 3 else 4 end, b.metric_key), '[]'::jsonb),
         count(*), count(*) filter (where b.state in ('OFF_TARGET','BEHIND'))
    into v_sc, v_sc_rows, v_sc_off
    from public.v_bi_scorecard b
   where b.owner_dept = any (v_old_depts);

  -- 5. AD DATA, when the sync has written any. Only the growth scope reads it; it is that department's.
  if v_dept = 'growth' then
    select coalesce(jsonb_agg(jsonb_build_object('campaign', m.campaign_name, 'status', m.effective_status,
             'window', m.time_window, 'spend', m.spend, 'currency', m.currency, 'impressions', m.impressions,
             'clicks', m.clicks, 'ctr', m.ctr, 'cpc', m.cpc, 'results', m.results, 'synced_at', m.synced_at,
             'synced_via', m.synced_via) order by m.synced_at desc), '[]'::jsonb), count(*)
      into v_meta, v_meta_rows
      from (select distinct on (campaign_id, time_window) * from public.meta_insights order by campaign_id, time_window, synced_at desc) m;
  end if;

  inputs := jsonb_build_object(
    'located_by', v_located, 'step_run_id', v_sid, 'actor', v_actor, 'employee', v_employee, 'department', v_dept,
    'scorecard_owner_depts', to_jsonb(v_old_depts), 'framing', v_framing,
    'kpi_rows', v_kpi_rows, 'kpi_measured', v_kpi_measured, 'kpi_missed', v_kpi_missed, 'kpi_met', v_kpi_met,
    'scorecard_rows', v_sc_rows, 'scorecard_off_target', v_sc_off, 'meta_rows', v_meta_rows,
    'kpis', v_kpis, 'scorecard', v_sc, 'meta', coalesce(v_meta, '[]'::jsonb),
    'run_context', case when v_ctx ? 'failing_metrics' or v_ctx ? 'goals_at_risk' or v_ctx ? 'title'
                        then v_ctx - 'at' - 'ref' - 'functions' else null end,
    'measured_at', now());

  employee := v_employee; department := v_dept; workflow_key := v_wf; step_no := v_step_no; step := v_step;

  -- 6. NO DATA is its own answer, in its own shape.
  if v_kpi_measured = 0 and v_sc_rows = 0 and v_meta_rows = 0 then
    determination := 'no_data';
    outcome := format('no determination for %s: %s KPI row(s) in scope and %s of them measured, %s scorecard metric(s) owned, %s ad-insight row(s)',
                      v_dept, v_kpi_rows, v_kpi_measured, v_sc_rows, v_meta_rows);
    deliverable := outcome || case when v_kpi_rows > 0 then '. The KPIs exist but carry no measurement: '
        || (select string_agg(x->>'metric' || coalesce(' (' || (x->>'no_measure_reason') || ')', ''), '; ') from jsonb_array_elements(v_kpis) x)
        || '. Instrument the measure before asking for a recommendation.' else '.' end;
    recommendations := null;
    return next; return;
  end if;

  -- 7. THE RANKED MOVERS. Missed KPIs by attainment, off-target company metrics, then anything worsening.
  with cand as (
    select 'kpi' src, x->>'metric' metric, x->>'agent' owner, (x->>'actual')::numeric actual, (x->>'target')::numeric target,
           x->>'unit' unit, (x->>'attainment')::numeric attainment, x->>'verdict' verdict,
           (x->>'previous')::numeric previous, (x->>'delta')::numeric delta, x->>'measured_at' measured_at,
           (x->>'missed_days_14d')::int missed_14d, x->>'serves_goal' goal,
           case x->>'verdict' when 'MISSED' then 0 when 'NEAR' then 1 when 'NO TARGET' then 3 else 4 end sev
      from jsonb_array_elements(v_kpis) x where x->>'verdict' <> 'NO DATA'
    union all
    select 'scorecard', x->>'label', x->>'owner_dept', (x->>'value')::numeric, (x->>'target')::numeric, x->>'direction',
           case when (x->>'target')::numeric is null or (x->>'value')::numeric is null then null
                when (x->>'direction') = 'down' then round(least(100.0, 100.0 * (x->>'target')::numeric / nullif((x->>'value')::numeric,0)), 1)
                else round(100.0 * (x->>'value')::numeric / nullif((x->>'target')::numeric,0), 1) end,
           x->>'state', (x->>'previous')::numeric, (x->>'delta')::numeric, x->>'taken_at', null, null,
           case x->>'state' when 'OFF_TARGET' then 0 when 'BEHIND' then 1 when 'ERROR' then 2 else 4 end
      from jsonb_array_elements(v_sc) x where x->>'state' not in ('UNMEASURED')
  ), ranked as (
    select c.*, row_number() over (order by sev, attainment nulls last, delta nulls last, metric) rk from cand c
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'rank', rk, 'source', src, 'metric', metric, 'owner', owner, 'actual', actual, 'target', target, 'unit', unit,
           'attainment_pct', attainment, 'verdict', verdict, 'previous', previous, 'delta', delta, 'measured_at', measured_at,
           'missed_days_14d', missed_14d, 'serves_goal', goal,
           'trend', case when delta is null then 'no prior measurement' when delta > 0 then 'up ' || delta when delta < 0 then 'down ' || abs(delta) else 'flat' end,
           'determination', case v_framing
             when 'variance' then case when verdict in ('MISSED','OFF_TARGET','BEHIND')
                 then format('variance: %s at %s against target %s (%s%% attainment); %s',
                             metric, actual, target, attainment, case when delta is null then 'no prior point to trend' when delta < 0 then 'worsened by ' || abs(delta) || ' since the previous measurement' when delta > 0 then 'improved by ' || delta || ' but still short' else 'unchanged' end)
                 else format('within tolerance: %s at %s against target %s (%s%%)', metric, actual, target, attainment) end
             when 'root_cause' then case
                 when verdict in ('MET','ON_TARGET','NEAR') then format('%s is at %s%% of target: no gap to explain', metric, attainment)
                 when coalesce(missed_14d, 0) >= 10 and coalesce(delta, 0) <= 0 then format('the TARGET: %s missed on %s of the last 14 measured days with no improving trend (actual %s vs target %s); propose a revised target with the run of actuals as evidence', metric, missed_14d, actual, target)
                 when delta is not null and delta > 0 then format('the WORK: %s is moving toward target (%s -> %s, target %s); keep the current plan and re-measure on cadence', metric, previous, actual, target)
                 else format('the WORK: %s at %s vs target %s (%s%%) with %s missed day(s) in 14; the gap is recent enough to be closed by the owner %s', metric, actual, target, attainment, coalesce(missed_14d,0), owner) end
             when 'revise_or_retire' then case
                 when coalesce(missed_14d, 0) >= 14 then format('REVISE: %s missed every one of the last 14 measured days (actual %s vs target %s); the target does not describe this business yet', metric, actual, target)
                 when verdict in ('MET','ON_TARGET') and coalesce(missed_14d, 0) = 0 then format('KEEP: %s met at %s against %s and never missed in 14 days', metric, actual, target)
                 else format('KEEP and watch: %s at %s%% attainment, %s missed day(s) in 14', metric, attainment, coalesce(missed_14d,0)) end
             when 'options' then format('option: close the gap on %s (actual %s, target %s, gap %s %s); cost proxy = gap size, risk = %s', metric, actual, target, round(abs(coalesce(target,0) - coalesce(actual,0)), 2), coalesce(unit,''), case when attainment is null then 'unknown' when attainment < 50 then 'high (below half of target)' when attainment < 90 then 'medium' else 'low' end)
             when 'grade' then format('grade: %s %s (%s -> %s against target %s)', metric, case when delta is null then 'UNGRADED, no prior measurement' when (unit = 'percent_max' or unit = 'down') and delta < 0 then 'BETTER' when (unit = 'percent_max' or unit = 'down') and delta > 0 then 'WORSE' when delta > 0 then 'BETTER' when delta < 0 then 'WORSE' else 'FLAT' end, previous, actual, target)
             when 'baseline' then format('baseline captured: %s = %s (%s) measured %s, target %s', metric, actual, coalesce(unit,''), measured_at, target)
             else format('%s: %s at %s against target %s (%s%%), owner %s', verdict, metric, actual, target, attainment, owner) end)
           order by rk), '[]'::jsonb), count(*)
    into v_recs, v_n
    from ranked where rk <= 5;

  determination := 'recommendation';
  recommendations := v_recs;
  v_one := coalesce((select x->>'determination' from jsonb_array_elements(v_recs) x order by (x->>'rank')::int limit 1), 'nothing in scope moved');
  outcome := left(format('%s: %s of %s KPIs measured, %s missed, %s met; %s of %s owned scorecard metrics off target%s. Top mover: %s',
                    v_dept, v_kpi_measured, v_kpi_rows, v_kpi_missed, v_kpi_met, v_sc_off, v_sc_rows,
                    case when v_meta_rows > 0 then format('; %s ad-insight row(s) read', v_meta_rows) else '' end, v_one), 600);
  v_text := format(E'%s\nWorkflow %s step %s (%s), worked by %s for %s on %s.\nInputs: %s KPI rows (%s measured, %s missed, %s met), %s scorecard metrics (%s off target), %s ad-insight rows.\n',
                   case v_framing when 'variance' then 'VARIANCE AGAINST TARGET' when 'root_cause' then 'ROOT CAUSE: THE WORK OR THE TARGET' when 'revise_or_retire' then 'REVISE OR RETIRE' when 'options' then 'OPTIONS WITH COST AND RISK' when 'grade' then 'GRADE AGAINST BASELINE' when 'baseline' then 'BASELINE' when 'define' then 'METRIC DEFINITION REVIEW' else 'RECOMMENDATION' end,
                   coalesce(v_wfname, v_wf, '(no workflow)'), coalesce(v_step_no::text, '-'), coalesce(v_step, 'direct call'), v_employee, v_dept, to_char(now() at time zone 'utc', 'YYYY-MM-DD HH24:MI') || ' UTC',
                   v_kpi_rows, v_kpi_measured, v_kpi_missed, v_kpi_met, v_sc_rows, v_sc_off, v_meta_rows);
  for rec in select x from jsonb_array_elements(v_recs) x order by (x->>'rank')::int loop
    v_text := v_text || format(E'%s. %s [%s; trend %s; measured %s]\n', rec.x->>'rank', rec.x->>'determination', rec.x->>'source', rec.x->>'trend', coalesce(left(rec.x->>'measured_at', 16), '?'));
  end loop;
  if v_meta_rows > 0 then
    v_text := v_text || 'Ad data: ' || (select string_agg(format('%s [%s] %s: spend %s %s, %s impressions, %s clicks, ctr %s, cpc %s (synced %s via %s)',
        m->>'campaign', m->>'status', m->>'window', m->>'spend', m->>'currency', m->>'impressions', m->>'clicks', coalesce(m->>'ctr','-'), coalesce(m->>'cpc','-'), left(m->>'synced_at',10), m->>'synced_via'), '; ')
        from jsonb_array_elements(v_meta) m) || E'\n';
  end if;
  if v_ctx ? 'failing_metrics' then
    v_text := v_text || 'Trigger context named failing metrics ' || (v_ctx->'failing_metrics')::text || coalesce(' and goals at risk ' || (v_ctx->'goals_at_risk')::text, '') || E'.\n';
  end if;
  v_text := v_text || 'Basis: employee_kpi actual/target as measured, employee_kpi_history for the previous point and the 14-day miss count, v_bi_scorecard + metric_snapshot for company metrics' || case when v_dept = 'growth' then ', meta_insights for ad data' else '' end || '. No model call.';
  deliverable := v_text;

  if p_record then
    insert into public.org_memory(scope, kind, content, source)
    values ('analytics', 'insight', left(coalesce(v_wf,'direct') || ' step ' || coalesce(v_step_no::text,'-') || ' — ' || outcome, 500) || E'\n\n' || left(v_text, 3000), 'fn_recommend_deterministic');
  end if;
  return next;
end $$;

revoke execute on function public.fn_recommend_deterministic(bigint, boolean) from public;
revoke execute on function public.fn_recommend_deterministic(bigint, boolean) from anon;
grant execute on function public.fn_recommend_deterministic(bigint, boolean) to service_role;
