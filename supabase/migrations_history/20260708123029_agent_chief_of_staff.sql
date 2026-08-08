-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260708123029   name: agent_chief_of_staff
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

create or replace function public.fn_chief_of_staff()
returns jsonb language plpgsql security definer set search_path=public,pg_catalog as $$
declare exec jsonb; health jsonb; ops jsonb; rev jsonb;
  n_pending int; n_esc int; n_aging int; n_alerts int; n_depts int;
  brief text; recs text; dept_txt text; esc_txt text; owner text;
  prioritized jsonb; run_id bigint;
  esc_filter text := 'legal|complian|security|fraud|refund|finance|licence_expired|incident';
begin
  exec := public.fn_ws_exec();
  health := exec->'command'->'health';
  ops := exec->'command'->'ops';
  rev := ops->'revenue';

  select count(*) into n_pending from public.agent_actions
    where status in ('pending','held_for_review','proposed','open');
  select count(*) into n_esc from public.agent_actions
    where status in ('pending','held_for_review','proposed','open')
      and (risk='high' or kind ~* esc_filter or coalesce(title,'') ~* esc_filter);
  select count(*) into n_aging from public.agent_actions
    where status in ('pending','held_for_review','proposed','open') and created_at < now()-interval '3 days';
  select count(*) into n_alerts from public.security_events
    where severity='high' and created_at > now()-interval '2 days';
  select count(distinct agent) into n_depts from public.agent_runs where started_at > now()-interval '24 hours';

  select string_agg(line, E'\n' order by line) into dept_txt from (
    select '- '||agent||': '||count(*)||' runs'||
           case when count(*) filter (where status='error')>0
                then ' ('||count(*) filter (where status='error')||' failed)' else '' end as line
    from public.agent_runs where started_at > now()-interval '24 hours' group by agent
  ) d;

  select string_agg('- ['||coalesce(risk,'?')||'] '||coalesce(title,kind)||' ('||agent||')', E'\n') into esc_txt from (
    select agent,risk,title,kind from public.agent_actions
     where status in ('pending','held_for_review','proposed','open')
       and (risk='high' or kind ~* esc_filter or coalesce(title,'') ~* esc_filter)
     order by created_at asc limit 8
  ) e;

  select coalesce(jsonb_agg(x order by pr desc, cat asc),'[]'::jsonb) into prioritized from (
    select jsonb_build_object('id',id,'agent',agent,'risk',risk,'title',title,
             'age_days',round(extract(epoch from (now()-created_at))/86400)) x,
           (case risk when 'high' then 3 when 'medium' then 2 else 1 end) pr, created_at cat
    from public.agent_actions
    where status in ('pending','held_for_review','proposed','open')
    order by pr desc, created_at asc limit 15
  ) s;

  recs := '';
  if n_esc>0 then recs := recs||'1) Clear '||n_esc||' high-priority escalation(s) in Executive HQ today.'||E'\n'; end if;
  if n_aging>0 then recs := recs||'2) '||n_aging||' approval(s) waited >3 days — response time slipping; action or dismiss.'||E'\n'; end if;
  if (health->>'band') is not null and lower(health->>'band')<>'good'
     then recs := recs||'3) Company health is "'||(health->>'band')||'" ('||coalesce(health->>'index','?')||'/100) — focus on the weakest driver.'||E'\n'; end if;
  if recs='' then recs := 'No urgent actions. Maintain cadence; consider a growth push (supplier sourcing or marketing).'; end if;

  brief := 'Chief of Staff — daily briefing ('||to_char(now(),'DD Mon YYYY')||')'||E'\n\n'
    ||'HEADLINE: '||n_esc||' item(s) need you, '||n_pending||' pending total, health '
      ||coalesce(health->>'index','?')||'/100 ('||coalesce(health->>'band','?')||').'||E'\n\n'
    ||'NEEDS YOU TODAY:'||E'\n'||coalesce(esc_txt,'- Nothing high-priority — no open escalations.')||E'\n\n'
    ||'DEPARTMENTS (24h):'||E'\n'||coalesce(dept_txt,'- No agent runs in the last 24h.')||E'\n\n'
    ||'KPIs: revenue month '||coalesce(rev->>'month_aed','0')||' AED, cash received '||coalesce(rev->>'cash_received_aed','0')
      ||' AED, pending fees '||coalesce(rev->>'pending_fees_aed','0')||' AED, active RFQs '
      ||coalesce(ops->'marketplace'->>'active_rfqs','0')||'.'||E'\n\n'
    ||'RECOMMENDATIONS:'||E'\n'||recs;

  insert into public.agent_runs(agent,started_at,finished_at,status,counts,note)
    values('chief_of_staff',now(),now(),'ok',
      jsonb_build_object('departments',n_depts,'pending_approvals',n_pending,'escalations',n_esc,
        'aging',n_aging,'critical_alerts',n_alerts),'daily coordination')
    returning id into run_id;

  insert into public.agent_actions(agent,kind,status,risk,title,recommendation,target_table,target_id,detail)
    values('chief_of_staff','exec_briefing','pending','low',
      'Chief of Staff briefing — '||n_esc||' to escalate, '||n_pending||' pending, health '||coalesce(health->>'index','?'),
      'Review the prioritised queue and clear the '||n_esc||' escalation(s).', null, null,
      jsonb_build_object('briefing',brief,'prioritized',prioritized,'health',health->>'index',
        'pending',n_pending,'escalations',n_esc,'aging',n_aging,'critical_alerts',n_alerts));

  select split_part(coalesce(value,'management@quotesdone.com'),',',1) into owner
    from public.app_secrets where key='admin_emails';
  owner := coalesce(nullif(trim(owner),''),'management@quotesdone.com');
  insert into public.notifications(type,to_email,to_role,channel,subject,body)
    values('chief_of_staff', owner, 'admin','email',
      'Chief of Staff — '||n_esc||' need you, health '||coalesce(health->>'index','?')||'/100', brief);

  return jsonb_build_object('ok',true,'pending',n_pending,'escalations',n_esc,'aging',n_aging,
    'critical_alerts',n_alerts,'departments',n_depts,'run_id',run_id);
end $$;

revoke execute on function public.fn_chief_of_staff() from anon, authenticated, public;

insert into public.category_agents(slug,name,emoji,active,persona) values
 ('chief_of_staff','Chief of Staff','🧭',true,
  'Coordinates the entire company. Monitors company health, all AI departments, pending approvals, critical alerts and daily KPIs; prioritises work, surfaces risks, escalates legal/financial/security/compliance/low-confidence matters to the founder, and produces a daily executive briefing. Never spends money or sends high-risk actions without founder approval.')
on conflict (slug) do update set name=excluded.name, emoji=excluded.emoji, persona=excluded.persona, active=true;

insert into public.prompts(key,owner,description,active_version,updated_at) values
 ('chief_of_staff','founder','Chief of Staff — company coordinator & escalation owner',1, now())
on conflict (key) do update set description=excluded.description, active_version=excluded.active_version, updated_at=now();
