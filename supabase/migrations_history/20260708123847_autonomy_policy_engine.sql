-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260708123847   name: autonomy_policy_engine
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- Central autonomy policy: approval required ONLY for money movement, deletion of
-- supplier/customer records, and flagged (non-clean) supplier approvals. Everything else auto.
create or replace function public.fn_autonomy_check(p_kind text, p_target_table text, p_recommendation text)
returns text language sql immutable set search_path=public,pg_catalog as $$
  select case
    when p_kind ~* 'refund|payout|payment|withdraw|transfer|invoice_pay|money|charge' then 'approve'
    when p_kind ~* 'delete|purge|remove_record' and coalesce(p_target_table,'') in ('leads','customers') then 'approve'
    when p_kind = 'approve_supplier' and coalesce(p_recommendation,'') <> 'approve' then 'approve'
    else 'auto'
  end;
$$;

-- Engine: dispose the pending queue per policy. Auto-approves CLEAN suppliers, auto-clears
-- everything else safe, keeps payments + deletions + flagged suppliers for the founder.
create or replace function public.fn_autonomy_dispose()
returns jsonb language plpgsql security definer set search_path=public,pg_catalog as $$
declare r record; n_appr int:=0; n_auto int:=0; n_keep int:=0;
begin
  for r in select * from public.agent_actions
           where status in ('pending','held_for_review','proposed','open')
  loop
    if public.fn_autonomy_check(r.kind, r.target_table, r.recommendation)='approve' then
      n_keep := n_keep+1; continue;
    end if;
    if r.kind='approve_supplier' and coalesce(r.recommendation,'')='approve' and r.target_id ~ '^\d+$' then
      update public.leads set approval_status='approved', approved_at=now(),
             approval_decided_by='chief_of_staff (auto)', lifecycle_stage='active'
       where id=r.target_id::bigint and approval_status='pending' and coalesce(banned,false)=false;
      update public.agent_actions set status='approved', decided_by='chief_of_staff (auto)', decided_at=now() where id=r.id;
      n_appr := n_appr+1;
    else
      update public.agent_actions set status='auto_done', decided_by='chief_of_staff (auto)', decided_at=now() where id=r.id;
      n_auto := n_auto+1;
    end if;
  end loop;
  return jsonb_build_object('approved_suppliers',n_appr,'auto_cleared',n_auto,'kept_for_founder',n_keep);
end $$;
revoke execute on function public.fn_autonomy_check(text,text,text) from anon, authenticated, public;
revoke execute on function public.fn_autonomy_dispose() from anon, authenticated, public;

-- Chief of Staff: now auto-executes low-risk (via the engine) and only briefs on what truly needs the founder.
create or replace function public.fn_chief_of_staff()
returns jsonb language plpgsql security definer set search_path=public,pg_catalog as $$
declare disp jsonb; exec jsonb; health jsonb; ops jsonb; rev jsonb;
  n_pending int; n_aging int; n_depts int; brief text; recs text; dept_txt text; esc_txt text; owner text;
  prioritized jsonb; run_id bigint;
begin
  disp := public.fn_autonomy_dispose();               -- auto-handle low-risk first
  exec := public.fn_ws_exec();
  health := exec->'command'->'health'; ops := exec->'command'->'ops'; rev := ops->'revenue';

  -- remaining pending are, by policy, the founder-only items (payments, deletions, flagged suppliers)
  select count(*) into n_pending from public.agent_actions where status in ('pending','held_for_review','proposed','open');
  select count(*) into n_aging from public.agent_actions
    where status in ('pending','held_for_review','proposed','open') and created_at < now()-interval '3 days';
  select count(distinct agent) into n_depts from public.agent_runs where started_at > now()-interval '24 hours';

  select string_agg(line, E'\n' order by line) into dept_txt from (
    select '- '||agent||': '||count(*)||' runs'||
           case when count(*) filter (where status='error')>0 then ' ('||count(*) filter (where status='error')||' failed)' else '' end as line
    from public.agent_runs where started_at > now()-interval '24 hours' group by agent
  ) d;

  select string_agg('- ['||coalesce(risk,'?')||'] '||coalesce(title,kind)||' ('||agent||')', E'\n') into esc_txt from (
    select agent,risk,title,kind from public.agent_actions
     where status in ('pending','held_for_review','proposed','open') order by created_at asc limit 8
  ) e;

  select coalesce(jsonb_agg(x order by cat asc),'[]'::jsonb) into prioritized from (
    select jsonb_build_object('id',id,'agent',agent,'risk',risk,'title',title,
             'age_days',round(extract(epoch from (now()-created_at))/86400)) x, created_at cat
    from public.agent_actions where status in ('pending','held_for_review','proposed','open')
    order by created_at asc limit 15
  ) s;

  recs := '';
  if n_pending>0 then recs := recs||'1) '||n_pending||' item(s) need your sign-off (payments / deletions / flagged suppliers).'||E'\n'; end if;
  if n_aging>0 then recs := recs||'2) '||n_aging||' waited >3 days — action or dismiss.'||E'\n'; end if;
  if (health->>'band') is not null and lower(health->>'band')<>'good'
     then recs := recs||'3) Health "'||(health->>'band')||'" ('||coalesce(health->>'index','?')||'/100) — focus on the weakest driver.'||E'\n'; end if;
  if recs='' then recs := 'Nothing needs you. Everything low-risk was auto-handled. Consider a growth push.'; end if;

  brief := 'Chief of Staff — daily briefing ('||to_char(now(),'DD Mon YYYY')||')'||E'\n\n'
    ||'HEADLINE: I auto-handled '||coalesce(disp->>'auto_cleared','0')||' low-risk item(s) and auto-approved '
      ||coalesce(disp->>'approved_suppliers','0')||' clean supplier(s). '||n_pending||' item(s) need you. Health '
      ||coalesce(health->>'index','?')||'/100 ('||coalesce(health->>'band','?')||').'||E'\n\n'
    ||'NEEDS YOU (payments / deletions / flagged suppliers):'||E'\n'||coalesce(esc_txt,'- Nothing — your queue is clear.')||E'\n\n'
    ||'DEPARTMENTS (24h):'||E'\n'||coalesce(dept_txt,'- No agent runs in the last 24h.')||E'\n\n'
    ||'KPIs: revenue month '||coalesce(rev->>'month_aed','0')||' AED, cash received '||coalesce(rev->>'cash_received_aed','0')
      ||' AED, pending fees '||coalesce(rev->>'pending_fees_aed','0')||' AED, active RFQs '||coalesce(ops->'marketplace'->>'active_rfqs','0')||'.'||E'\n\n'
    ||'RECOMMENDATIONS:'||E'\n'||recs;

  insert into public.agent_runs(agent,started_at,finished_at,status,counts,note)
    values('chief_of_staff',now(),now(),'ok',
      jsonb_build_object('auto_cleared',disp->>'auto_cleared','approved_suppliers',disp->>'approved_suppliers',
        'needs_founder',n_pending,'aging',n_aging,'departments',n_depts),'coordination + autonomy')
    returning id into run_id;

  insert into public.agent_actions(agent,kind,status,risk,title,recommendation,target_table,target_id,detail)
    values('chief_of_staff','exec_briefing','auto_done','low',
      'Chief of Staff briefing — '||n_pending||' need you, '||coalesce(disp->>'auto_cleared','0')||' auto-handled',
      'Informational; auto-logged.', null, null,
      jsonb_build_object('briefing',brief,'prioritized',prioritized,'autonomy',disp,'health',health->>'index','needs_founder',n_pending));

  select split_part(coalesce(value,'management@quotesdone.com'),',',1) into owner from public.app_secrets where key='admin_emails';
  owner := coalesce(nullif(trim(owner),''),'management@quotesdone.com');
  insert into public.notifications(type,to_email,to_role,channel,subject,body)
    values('chief_of_staff', owner, 'admin','email',
      'Chief of Staff — '||n_pending||' need you, '||coalesce(disp->>'auto_cleared','0')||' auto-handled', brief);

  return jsonb_build_object('ok',true,'autonomy',disp,'needs_founder',n_pending,'aging',n_aging,'departments',n_depts,'run_id',run_id);
end $$;

update public.category_agents set persona=
 'Coordinates the entire company and runs the autonomy policy. Auto-executes all low-risk work without approval (clears the queue, auto-approves CLEAN new suppliers). Escalates to the founder ONLY: payments/money movement, deletion of supplier or customer records, and flagged (non-clean) supplier approvals. Produces a daily executive briefing; monitors health, departments, KPIs and alerts.'
 where slug='chief_of_staff';

-- run the autonomy engine hourly so low-risk work clears without the founder waiting for the daily run
select cron.schedule('autonomy_dispose_hourly','45 * * * *', $$select public.fn_autonomy_dispose()$$);
