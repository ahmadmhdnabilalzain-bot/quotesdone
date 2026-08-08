-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260709080840   name: fn_supplier_success_agent
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

create or replace function public.fn_supplier_success()
returns jsonb
language plpgsql security definer
set search_path to 'public','pg_temp'
as $fn$
declare
  v_kpis jsonb;
  n_enable int:=0; n_reengage int:=0; n_risk int:=0;
  rec record;
  v_tips text; v_subject text; v_body text;
begin
  -- 1) snapshot portfolio KPIs (one row per day)
  select to_jsonb(k) into v_kpis from public.supplier_kpis k;
  insert into public.supplier_kpi_snapshots(snapshot_date, kpis)
  values (current_date, coalesce(v_kpis,'{}'::jsonb))
  on conflict (snapshot_date) do update set kpis=excluded.kpis, created_at=now();

  -- 2) ENABLEMENT (operational, auto-sends once supplier emails enabled) — low quality/response/compliance
  for rec in
    select h.supplier_id, h.quality, h.response, h.compliance, l.company_name as co,
           coalesce(l.claimed_by,l.email) as to_email
    from public.supplier_health h join public.leads l on l.id=h.supplier_id
    where coalesce(l.banned,false)=false
      and (h.quality < 50 or h.response < 50 or h.compliance < 80)
      and coalesce(l.claimed_by,l.email) like '%@%'
      and not exists (select 1 from notifications n where n.lead_id=h.supplier_id and n.type='supplier_enablement' and n.created_at > now()-interval '30 days')
    limit 200
  loop
    v_tips := '';
    if rec.compliance < 80 then v_tips := v_tips || E'\n• Complete your documents (licence, insurance, TRN, establishment card) so you stay eligible for matches.'; end if;
    if rec.response < 50 then v_tips := v_tips || E'\n• Respond faster to job requests — quick, complete quotes win more often.'; end if;
    if rec.quality < 50 then v_tips := v_tips || E'\n• Add full itemised detail (brand, model, spec, unit price) to every quote — detailed quotes convert best.'; end if;
    v_subject := 'Tips to win more jobs on QuotesDone — ' || coalesce(rec.co,'your business');
    v_body := 'Dear ' || coalesce(rec.co,'there') || E',\n\nHere are a few quick things that will help you win more customer jobs on QuotesDone:' || v_tips || E'\n\nUpdate your profile any time from your supplier portal. We are here to help you grow. Thank you for being part of QuotesDone.';
    insert into notifications(type,to_email,to_role,lead_id,channel,subject,body,status)
    values ('supplier_enablement', rec.to_email, 'supplier', rec.supplier_id, 'email', v_subject, v_body, 'queued');
    n_enable := n_enable + 1;
  end loop;

  -- 3) RETENTION / re-engagement (operational) — dormant suppliers
  for rec in
    select h.supplier_id, l.company_name as co, coalesce(l.claimed_by,l.email) as to_email
    from public.supplier_health h join public.leads l on l.id=h.supplier_id
    where h.dormant and coalesce(l.banned,false)=false
      and coalesce(l.claimed_by,l.email) like '%@%'
      and not exists (select 1 from notifications n where n.lead_id=h.supplier_id and n.type='supplier_reengage' and n.created_at > now()-interval '30 days')
    limit 200
  loop
    v_subject := 'We miss you on QuotesDone — new jobs are waiting';
    v_body := 'Dear ' || coalesce(rec.co,'there') || E',\n\nWe have not seen you quoting recently. Customers are posting jobs in your category on QuotesDone right now. Log in to your supplier portal to see your latest matches and send a quick quote.\n\nMake sure your documents and profile are up to date so you keep receiving matches. We would love to help you win more work.';
    insert into notifications(type,to_email,to_role,lead_id,channel,subject,body,status)
    values ('supplier_reengage', rec.to_email, 'supplier', rec.supplier_id, 'email', v_subject, v_body, 'queued');
    n_reengage := n_reengage + 1;
  end loop;

  -- 4) RISK — high-risk suppliers queued for FOUNDER decision (never auto-suspend/ban/delete)
  for rec in
    select h.supplier_id, h.compliance, h.strikes, h.banned, h.health, h.risk_tier, l.company_name as co
    from public.supplier_health h join public.leads l on l.id=h.supplier_id
    where h.risk_tier='high'
      and not exists (
        select 1 from agent_actions a
        where a.kind='supplier_risk' and a.target_table='leads' and a.target_id=h.supplier_id::text
          and a.status in ('pending','needs_review'))
    limit 100
  loop
    insert into agent_actions(agent, kind, status, risk, title, recommendation, detail, target_table, target_id)
    values ('supplier_success','supplier_risk','pending','high',
      'High-risk supplier: '||coalesce(rec.co,'#'||rec.supplier_id),
      case when rec.banned then 'Already banned — review whether to remove from marketplace.'
           when rec.strikes>=3 then 'Repeated chat strikes — consider suspending matching pending review.'
           when rec.compliance<40 then 'Compliance failing (missing/expired documents) — hold matches until resolved.'
           else 'Low overall health — review account, coach or pause.' end,
      jsonb_build_object('company',rec.co,'health',rec.health,'compliance',rec.compliance,'strikes',rec.strikes,'banned',rec.banned),
      'leads', rec.supplier_id::text);
    n_risk := n_risk + 1;
  end loop;

  return jsonb_build_object('ran_at',now(),'kpis',v_kpis,'enablement_queued',n_enable,'reengage_queued',n_reengage,'risk_flagged',n_risk);
end $fn$;

revoke all on function public.fn_supplier_success() from anon, authenticated, public;

-- register the agent for visibility in os3 AI Ops
insert into public.category_agents(slug,name,emoji,active,persona)
values ('supplier_success','Supplier Success','🤝',true,
  'Manages the supplier lifecycle end to end: onboarding, verification, document review, compliance, performance, enablement (training) and retention. Monitors trade licence, insurance, establishment card, TRN, ISO and manufacturer authorisations (expiring or missing). Tracks KPIs (supplier quality, compliance, response time, retention) and per-supplier health + risk. Auto-sends operational nudges (renewals, enablement tips, dormant re-engagement); queues risky actions (suspend/block) for the founder and NEVER suspends, bans or deletes a supplier on its own.')
on conflict (slug) do update set name=excluded.name, emoji=excluded.emoji, active=excluded.active, persona=excluded.persona;

-- schedule daily at 06:20 UTC
select cron.schedule('supplier_success_daily','20 6 * * *', $$select public.fn_supplier_success();$$);
