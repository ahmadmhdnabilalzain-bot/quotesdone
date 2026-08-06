-- org_agents.improvement_plan: 0 OF 66 POPULATED. The column exists, the spec's employee object
-- (line 372) names it, fn_agent_context emits it when it is non-null — and nothing has ever
-- written one, so the branch was dead.
--
-- An improvement plan invented by a model would be a plausible sentence with no evidence behind it,
-- which is the failure mode this project keeps finding. So it is DERIVED, deterministically, from
-- what actually happened to this employee's department:
--   * deliverables the review chain returned, and the rule they broke — now recorded per task by
--     fn_task_lesson, which is what made this derivable at all;
--   * KPIs the employee owns that are missing their target;
--   * open self_review findings against the department.
-- No model call. If there is no evidence, the plan is NULL rather than an encouraging sentence —
-- an employee with nothing to fix should not be told to fix something.
create or replace function public.fn_improvement_plan_refresh()
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_catalog'
as $function$
declare
  a record; v_parts text[]; v_line text; v_plan text;
  v_written int := 0; v_cleared int := 0;
begin
  for a in select agent_key, department from org_agents where active loop
    v_parts := array[]::text[];

    -- 1. What this department's work has been returned for, most recent first.
    select 'Your department has had ' || count(*) || ' deliverable(s) returned by review recently. '
        || 'The reasons on record: ' || string_agg(distinct left(m.detail, 120), '; ')
      into v_line
      from institutional_memory m
     where m.subject_type = 'org_task' and m.outcome = 'worse'
       and a.department = any(coalesce(m.visible_to, array[]::text[]))
       and m.created_at > now() - interval '30 days';
    if v_line is not null and v_line not like '%has had 0 %' then
      v_parts := v_parts || v_line;
    end if;

    -- 2. KPIs this employee owns that are behind. Their own targets, not the department's.
    select 'You own ' || count(*) || ' KPI(s) with a target you are not currently meeting: '
        || string_agg(k.kpi || ' (target ' || coalesce(k.target_value::text,'?') || ' ' || coalesce(k.unit,'') || ')', '; ')
      into v_line
      from employee_kpi k
     where k.agent_key = a.agent_key and k.active
       and exists (select 1 from goal_period g
                    where g.goal_key = k.serves_goal
                      and g.status in ('at_risk','missed','behind'));
    if v_line is not null and v_line not like '%own 0 KPI%' then
      v_parts := v_parts || v_line;
    end if;

    -- 3. Open findings the organisation has already recorded against this department.
    select 'Open findings against your department: ' || string_agg(left(s.finding, 110), '; ')
      into v_line
      from (select finding from self_review
             where coalesce(status,'open') not in ('done','implemented','rejected')
             order by created_at desc limit 2) s;
    if v_line is not null then v_parts := v_parts || v_line; end if;

    v_plan := nullif(array_to_string(v_parts, ' '), '');

    -- NULL when there is nothing on record. An empty plan is honest; a generic one is noise that
    -- would reach 66 prompts and mean nothing in any of them.
    update org_agents set improvement_plan = left(v_plan, 900) where agent_key = a.agent_key;
    if v_plan is null then v_cleared := v_cleared + 1; else v_written := v_written + 1; end if;
  end loop;

  return jsonb_build_object('agents', v_written + v_cleared,
                            'with_a_plan', v_written, 'nothing_on_record', v_cleared);
end $function$;

comment on function public.fn_improvement_plan_refresh() is
  'Derives org_agents.improvement_plan from evidence — returned deliverables and the rule they '
  'broke, the employee''s own missed KPIs, and open self_review findings. Deterministic, no model '
  'call. Writes NULL where there is nothing on record rather than a generic sentence.';
