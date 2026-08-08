create or replace function public.fn_company_reflect()
returns jsonb language plpgsql security definer set search_path to 'public','pg_temp'
as $fn$
declare a jsonb; n_concern int := 0; n_act int := 0;
  v_learned int; v_errors int; v_wrong int; v_dept text; v_improved text;
  v_stale int; v_missed int; v_comp int; v_worst text;
begin
  select count(*) into v_learned from institutional_memory where created_at > now()-interval '24 hours';
  select count(*) into v_errors  from agent_runs where status='error' and started_at > now()-interval '24 hours';
  select count(*) into v_wrong   from outcome_record where verdict='worse' and closed_at > now()-interval '24 hours';
  select dept_key into v_dept from org_tasks where status<>'done' group by dept_key order by count(*) desc limit 1;
  select string_agg(actor,', ') into v_improved from (
    select distinct actor from outcome_record where verdict='improved' and closed_at > now()-interval '7 days' limit 3) x;
  select count(*) into v_stale from agent_knowledge where validation_status in ('stale','quarantined');
  select count(*) into v_missed from v_supply_gap where status='READY - not yet invited';
  select count(*) into v_comp from competitor;
  select name into v_worst from v_supply_gap where status like 'NO POOL%' limit 1;

  a := jsonb_build_object(
    'what_did_i_learn', v_learned||' lesson(s) entered institutional memory in the last 24 hours.',
    'what_mistakes_did_i_make', v_errors||' agent run(s) errored.',
    'which_decisions_were_wrong', v_wrong||' graded improvement(s) made things worse and were flagged for reversal.',
    'which_departments_are_struggling', coalesce('Heaviest open backlog: '||v_dept,'No department is carrying an unusual backlog.'),
    'which_employees_improved', coalesce('Improvements that worked came from: '||v_improved,'No graded improvement has closed successfully yet.'),
    'which_knowledge_became_outdated', v_stale||' knowledge item(s) are stale or quarantined.',
    'which_opportunities_did_i_miss', v_missed||' category/categories have a viable supplier pool and no invitations sent.',
    'which_competitor_became_stronger', v_comp||' competitor(s) tracked but 0 market signals captured, so this cannot be answered honestly yet.',
    'how_can_i_be_better_tomorrow', coalesce('Close the supply gap starting with '||v_worst,'Close the open KPI gaps before taking on new work.'));

  if v_errors > 10 then n_concern := n_concern + 1; end if;
  if v_wrong  > 0  then n_concern := n_concern + 1; end if;
  if v_stale  > 50 then n_concern := n_concern + 1; end if;

  if v_missed > 0 then
    insert into org_tasks (dept_key,title,detail,status,tier,needs_founder,action_class)
    select 'procurement','Nightly reflection: '||v_missed||' category(ies) ready but uninvited',
      'The company noticed overnight that '||v_missed||' category(ies) hold a viable supplier pool with no invitations sent. Queue them, or record why not.',
      'proposed','advisory',false,'invite'
    where not exists (select 1 from org_tasks where title like 'Nightly reflection: % ready but uninvited' and status<>'done');
    if found then n_act := n_act + 1; end if;
  end if;

  insert into company_reflection (reflected_on,answers,concerns,actions)
  values (current_date,a,n_concern,n_act)
  on conflict (reflected_on) do update set answers=excluded.answers, concerns=excluded.concerns, actions=excluded.actions;

  insert into agent_runs (agent,started_at,finished_at,status,counts,note)
  values ('company_reflect',now(),now(),'ok',jsonb_build_object('concerns',n_concern,'actions',n_act),
    'Nightly self-reflection: '||n_concern||' concern(s), '||n_act||' action(s) opened. Nobody asked for this.');
  return jsonb_build_object('concerns',n_concern,'actions',n_act,'answers',a);
end $fn$;
revoke execute on function public.fn_company_reflect() from public, anon, authenticated;