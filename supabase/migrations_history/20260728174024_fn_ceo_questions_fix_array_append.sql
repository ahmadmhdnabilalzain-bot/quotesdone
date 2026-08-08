create or replace function public.fn_ceo_questions()
returns jsonb language plpgsql security definer set search_path to 'public','pg_temp'
as $fn$
declare qs text[] := array[]::text[]; n int := 0; q text;
  v_rev numeric; v_sup int; v_inq int; v_worst text; v_cost numeric; v_prev numeric;
begin
  select coalesce(sum(coalesce(reveal_fee,app_fee,0)),0) into v_rev from transactions where revealed_at > now()-interval '30 days';
  select count(*) into v_sup from leads where claimed and approval_status='approved';
  select count(*) into v_inq from inquiries where created_at > now()-interval '30 days';
  select dept_key into v_worst from org_tasks where title like 'KPI missed:%' and status<>'done'
    group by dept_key order by count(*) desc limit 1;
  select coalesce(sum(cost_aed),0) into v_cost from ai_cost_log where occurred_at > now()-interval '7 days';
  select coalesce(sum(cost_aed),0) into v_prev from ai_cost_log where occurred_at between now()-interval '14 days' and now()-interval '7 days';

  if v_rev = 0 then
    qs := array_append(qs, 'Why are we not growing? Revenue is zero over 30 days with '||v_sup||' onboarded suppliers and '||v_inq||' inquiries. What is the single binding constraint, and what would remove it?');
  end if;
  if v_sup = 0 then
    qs := array_append(qs, 'We have 86 fully briefed category experts and no onboarded suppliers. Are we building capability ahead of demand, and is that still the right sequence?');
  end if;
  if v_worst is not null then
    qs := array_append(qs, 'Why is '||v_worst||' missing more targets than any other department this week? Is it capability, capacity, or a target that was never realistic?');
  end if;
  if v_prev > 0 and v_cost > v_prev * 1.25 then
    qs := array_append(qs, 'AI cost rose from '||round(v_prev,2)||' to '||round(v_cost,2)||' AED week on week. What drove it and did it buy anything?');
  end if;
  qs := array_append(qs, 'Which workflow wastes the most employee time, and what would automating it be worth?');
  qs := array_append(qs, 'Which department produced the highest return on its AI spend this month, and what are the others not copying?');
  qs := array_append(qs, 'What are we doing today only because we have always done it?');

  foreach q in array qs loop
    insert into org_tasks (dept_key,title,detail,status,tier,needs_founder,action_class)
    select 'exec','CEO question: '||left(q,80),
           q||E'\n\nAnswer with evidence from company data, not opinion. If the answer implies a change, open it as an initiative with a named metric and a baseline so it can be graded.',
           'proposed','advisory',false,'recommend'
    where not exists (select 1 from org_tasks where title='CEO question: '||left(q,80) and status<>'done');
    if found then n := n + 1; end if;
  end loop;

  insert into agent_runs (agent,started_at,finished_at,status,counts,note)
  values ('ceo_questions',now(),now(),'ok',jsonb_build_object('asked',n),
          'CEO self-questioning: '||n||' strategic question(s) raised from live company data.');
  return jsonb_build_object('asked',n);
end $fn$;
revoke execute on function public.fn_ceo_questions() from public, anon, authenticated;