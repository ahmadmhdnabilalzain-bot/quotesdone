-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260708124602   name: autonomy_policy_v2_honest
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- Classifier: founder (needs sign-off) | clean_supplier (auto-approve) | ack (auto-clear, logged elsewhere) | keep (stays visible)
create or replace function public.fn_autonomy_class(p_kind text, p_target_table text, p_recommendation text)
returns text language sql immutable set search_path=public,pg_catalog as $$
  select case
    when p_kind ~* 'refund|payout|payment|withdraw|transfer|invoice_pay|money|charge' then 'founder'
    when p_kind ~* 'delete|purge|remove_record' and coalesce(p_target_table,'') in ('leads','customers') then 'founder'
    when p_kind='approve_supplier' and coalesce(p_recommendation,'')='approve' then 'clean_supplier'
    when p_kind='approve_supplier' then 'founder'
    -- logged elsewhere, safe to auto-clear from the queue (founder chose auto-clear for these):
    when p_kind in ('security_alert','compliance_update','incident','supply_health','sla_no_supply') then 'ack'
    -- everything actionable that isn't safely auto-doable stays visible (marketing drafts, BD invites,
    -- inbound-email review, agent handoffs, and anything unknown):
    else 'keep'
  end;
$$;
revoke execute on function public.fn_autonomy_class(text,text,text) from anon, authenticated, public;

-- Engine v2: only auto-approve CLEAN suppliers and auto-clear logged alerts. Never silently drop actionable work.
create or replace function public.fn_autonomy_dispose()
returns jsonb language plpgsql security definer set search_path=public,pg_catalog as $$
declare r record; n_appr int:=0; n_ack int:=0; n_queue int:=0; c text;
begin
  for r in select * from public.agent_actions
           where status in ('pending','held_for_review','proposed','open')
  loop
    c := public.fn_autonomy_class(r.kind, r.target_table, r.recommendation);
    if c='clean_supplier' and r.target_id ~ '^\d+$' then
      update public.leads set approval_status='approved', approved_at=now(),
             approval_decided_by='chief_of_staff (auto)', lifecycle_stage='active'
       where id=r.target_id::bigint and approval_status='pending' and coalesce(banned,false)=false;
      update public.agent_actions set status='approved', decided_by='chief_of_staff (auto)', decided_at=now() where id=r.id;
      n_appr := n_appr+1;
    elsif c='ack' then
      update public.agent_actions set status='auto_done', decided_by='chief_of_staff (auto)', decided_at=now() where id=r.id;
      n_ack := n_ack+1;
    else  -- 'founder' or 'keep' → remains visible in the queue
      n_queue := n_queue+1;
    end if;
  end loop;
  return jsonb_build_object('approved_suppliers',n_appr,'auto_cleared_logged',n_ack,'in_your_queue',n_queue);
end $$;

-- Re-surface anything my first pass wrongly dismissed that should actually be visible (marketing/BD/inbound/to-dos).
update public.agent_actions
   set status='pending', decided_by=null, decided_at=null
 where status='auto_done' and decided_by='chief_of_staff (auto)'
   and public.fn_autonomy_class(kind, target_table, recommendation)='keep';

-- Chief of Staff: report honestly.
create or replace function public.fn_chief_of_staff()
returns jsonb language plpgsql security definer set search_path=public,pg_catalog as $$
declare disp jsonb; exec jsonb; health jsonb; ops jsonb; rev jsonb;
  n_pending int; n_aging int; n_depts int; brief text; recs text; dept_txt text; esc_txt text; owner text;
  prioritized jsonb; run_id bigint;
begin
  disp := public.fn_autonomy_dispose();
  exec := public.fn_ws_exec();
  health := exec->'command'->'health'; ops := exec->'command'->'ops'; rev := ops->'revenue';

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
     where status in ('pending','held_for_review','proposed','open') order by created_at asc limit 10
  ) e;

  select coalesce(jsonb_agg(x order by cat asc),'[]'::jsonb) into prioritized from (
    select jsonb_build_object('id',id,'agent',agent,'risk',risk,'title',title,
             'age_days',round(extract(epoch from (now()-created_at))/86400)) x, created_at cat
    from public.agent_actions where status in ('pending','held_for_review','proposed','open')
    order by created_at asc limit 15
  ) s;

  recs := '';
  if n_pending>0 then recs := recs||'1) '||n_pending||' item(s) in your queue (payments, deletions, flagged suppliers, marketing to post, BD to enable, to-dos).'||E'\n'; end if;
  if n_aging>0 then recs := recs||'2) '||n_aging||' waited >3 days — action or dismiss.'||E'\n'; end if;
  if (health->>'band') is not null and lower(health->>'band')<>'good'
     then recs := recs||'3) Health "'||(health->>'band')||'" ('||coalesce(health->>'index','?')||'/100).'||E'\n'; end if;
  if recs='' then recs := 'Queue clear. Everything auto-handled where safe.'; end if;

  brief := 'Chief of Staff — daily briefing ('||to_char(now(),'DD Mon YYYY')||')'||E'\n\n'
    ||'HEADLINE: auto-approved '||coalesce(disp->>'approved_suppliers','0')||' clean supplier(s), auto-cleared '
      ||coalesce(disp->>'auto_cleared_logged','0')||' logged alert(s). '||n_pending||' item(s) in your queue. Health '
      ||coalesce(health->>'index','?')||'/100 ('||coalesce(health->>'band','?')||').'||E'\n\n'
    ||'YOUR QUEUE:'||E'\n'||coalesce(esc_txt,'- Empty.')||E'\n\n'
    ||'DEPARTMENTS (24h):'||E'\n'||coalesce(dept_txt,'- No agent runs in the last 24h.')||E'\n\n'
    ||'KPIs: revenue month '||coalesce(rev->>'month_aed','0')||' AED, cash received '||coalesce(rev->>'cash_received_aed','0')
      ||' AED, pending fees '||coalesce(rev->>'pending_fees_aed','0')||' AED, active RFQs '||coalesce(ops->'marketplace'->>'active_rfqs','0')||'.'||E'\n\n'
    ||'RECOMMENDATIONS:'||E'\n'||recs;

  insert into public.agent_runs(agent,started_at,finished_at,status,counts,note)
    values('chief_of_staff',now(),now(),'ok',
      jsonb_build_object('approved_suppliers',disp->>'approved_suppliers','auto_cleared',disp->>'auto_cleared_logged',
        'in_queue',n_pending,'aging',n_aging,'departments',n_depts),'coordination + autonomy v2')
    returning id into run_id;

  insert into public.agent_actions(agent,kind,status,risk,title,recommendation,target_table,target_id,detail)
    values('chief_of_staff','exec_briefing','auto_done','low',
      'Chief of Staff briefing — '||n_pending||' in queue, '||coalesce(disp->>'auto_cleared_logged','0')||' auto-cleared',
      'Informational.', null, null,
      jsonb_build_object('briefing',brief,'prioritized',prioritized,'autonomy',disp,'health',health->>'index','in_queue',n_pending));

  select split_part(coalesce(value,'management@quotesdone.com'),',',1) into owner from public.app_secrets where key='admin_emails';
  owner := coalesce(nullif(trim(owner),''),'management@quotesdone.com');
  insert into public.notifications(type,to_email,to_role,channel,subject,body)
    values('chief_of_staff', owner, 'admin','email',
      'Chief of Staff — '||n_pending||' in your queue, health '||coalesce(health->>'index','?')||'/100', brief);

  return jsonb_build_object('ok',true,'autonomy',disp,'in_queue',n_pending,'aging',n_aging,'departments',n_depts,'run_id',run_id);
end $$;

update public.category_agents set persona=
 'Coordinates the company and runs the autonomy policy honestly. AUTO-APPROVES only clean new suppliers (no flags/complete docs). AUTO-CLEARS only alerts already logged elsewhere (security, compliance, agent incidents, supply metrics). KEEPS VISIBLE everything actionable the founder should decide or that has external effects: payments, record deletions, flagged suppliers, marketing drafts (to post), BD invites (to enable), inbound emails, and to-dos. Never posts content, sends cold emails, moves money, or deletes records on its own. Produces a daily briefing.'
 where slug='chief_of_staff';
