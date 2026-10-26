-- fn_report_recommendation_approve — approve a recommendation from inside the report.
--
-- Screen 10: "Recommended actions can be approved from inside the report." 33 of 40 exec_reports
-- carry recommendations and there was no path from reading one to acting on it — the founder had
-- to leave the report, find the thing, and approve it somewhere else.
--
-- This records the approval as an agent_action pointing back at the report, which is the same
-- ledger every other approval in the company lands in, AND routes it as real work: an approval that
-- produces no task is a marked ledger entry nobody acts on. The approved recommendation becomes an
-- owned org_task in the accountable officer's department (a05_org_task_fill_ownership assigns the
-- owner and ties it to the objective it names), so "approved" turns into someone doing it.
--
--   node scripts/apply_sql.mjs scripts/sql/fn_report_recommendation_approve.sql --promote
create or replace function public.fn_report_recommendation_approve(
  p_report_id bigint, p_index integer, p_by text, p_source text default 'exec_reports')
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_catalog'
as $function$
declare v_rec jsonb; v_title text; v_id bigint; v_officer text; v_dept text; v_task bigint;
begin
  if p_source = 'exec_reports' then
    select r.recommendations -> p_index, r.officer into v_rec, v_officer
      from public.exec_reports r where r.id = p_report_id;
  else
    select r.kpis -> p_index, 'board' into v_rec, v_officer
      from public.board_reports r where r.id = p_report_id;
  end if;
  if v_rec is null then
    return jsonb_build_object('ok', false, 'error', 'no recommendation at that index');
  end if;
  v_title := coalesce(v_rec ->> 'title', v_rec ->> 'recommendation', left(v_rec::text, 160));

  insert into public.agent_actions(agent, kind, status, risk, title, recommendation,
      target_table, target_id, decided_by, decided_at, detail)
    values (coalesce(v_officer, 'exec'), 'report_recommendation', 'approved',
      coalesce(v_rec ->> 'risk', 'medium'), v_title, v_rec::text,
      p_source, p_report_id::text, p_by, now(),
      jsonb_build_object('report_id', p_report_id, 'index', p_index, 'source', p_source, 'recommendation', v_rec))
    returning id into v_id;

  -- ROUTE IT AS REAL WORK. The department is the accountable officer's; a05_org_task_fill_ownership
  -- gives it an owner and, when the recommendation names a goal, ties it to that objective. Idempotent
  -- on the report+index marker, so approving the same recommendation twice does not double the work.
  v_dept := coalesce((select department from public.org_agents
                        where agent_key = coalesce(public.fn_org_agent_resolve(v_officer), v_officer)), 'exec');
  select id into v_task from public.org_tasks t
   where t.action_class = 'report_recommendation'
     and t.detail like '%report #'||p_report_id||' rec '||p_index||' by %'
     and t.status <> 'done'
   order by id limit 1;
  if v_task is null then
    insert into public.org_tasks (dept_key, title, detail, status, tier, needs_founder, action_class)
    values (v_dept, v_title,
      coalesce(v_rec ->> 'why', v_rec ->> 'recommendation', v_title)
        ||'  [Approved from the '||p_source||' report #'||p_report_id||' rec '||p_index||' by '||p_by
        ||'. Do it, or bring evidence the standard is wrong.]',
      'assigned', 'advisory', false, 'report_recommendation')
    returning id into v_task;
    update public.agent_actions set detail = detail || jsonb_build_object('org_task_id', v_task) where id = v_id;
  end if;

  return jsonb_build_object('ok', true, 'action_id', v_id, 'org_task_id', v_task,
                            'title', v_title, 'report_id', p_report_id);
end $function$;
