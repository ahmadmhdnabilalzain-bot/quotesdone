-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260709105131   name: fn_reporting_ai_agent
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- De-duped founder flag helper for the Reporting AI
create or replace function public.fn_report_flag(p_title text, p_risk text, p_rec text)
returns void language plpgsql security definer set search_path to 'public','pg_temp' as $$
begin
  if not exists (
    select 1 from public.agent_actions
    where agent='reporting_ai' and kind='report_task' and title=p_title
      and status in ('pending','needs_review')
  ) then
    insert into public.agent_actions(agent, kind, status, risk, title, recommendation, created_at)
    values ('reporting_ai','report_task','needs_review',p_risk,p_title,p_rec, now());
  end if;
end $$;
revoke all on function public.fn_report_flag(text,text,text) from anon, authenticated, public;

-- The Reporting AI: keeps the report set fresh, catalogs everything, flags gaps.
-- OVERSIGHT-FIRST: generates internal report documents only. It NEVER emails, sends to the
-- board, or publishes a report externally — distribution stays a founder action.
create or replace function public.fn_reporting_ai()
returns jsonb language plpgsql security definer set search_path to 'public','pg_temp' as $$
declare k record; v_gen text[] := '{}'; v_flags int := 0; kind text;
begin
  -- Refresh the four agent-owned report types once per calendar day (no intra-day duplicates)
  foreach kind in array array['department','supplier','customer','ai'] loop
    if not exists (select 1 from public.board_reports where report_type=kind and created_at::date=current_date) then
      perform public.fn_report_generate(kind);
      v_gen := v_gen || kind;
    end if;
  end loop;

  select * into k from public.report_kpis;
  insert into public.report_kpi_snapshots(kpis) values (to_jsonb(k));

  -- Flag any scheduled report that is stale or missing (founder-visible, de-duped)
  if coalesce(k.daily_fresh,false) = false then
    perform public.fn_report_flag('Daily briefing is stale or missing','high',
      'No founder daily briefing in the last 36 hours — check the founder_brief_daily cron and fn_founder_brief.'); v_flags:=v_flags+1;
  end if;
  if coalesce(k.weekly_fresh,false) = false then
    perform public.fn_report_flag('Weekly board report overdue','medium',
      'No weekly board report in the last 8 days — check the board_report_weekly cron and fn_board_report.'); v_flags:=v_flags+1;
  end if;
  if coalesce(k.monthly_fresh,false) = false then
    perform public.fn_report_flag('Monthly report not generated this month','medium',
      'No monthly report for the current month yet — fn_monthly_report / monthly_report cron.'); v_flags:=v_flags+1;
  end if;
  if coalesce(k.quarterly_fresh,false) = false then
    perform public.fn_report_flag('Quarterly report missing','medium',
      'No quarterly report in the last ~95 days — run fn_quarterly_report() or check the quarterly_report cron.'); v_flags:=v_flags+1;
  end if;

  return jsonb_build_object('generated', to_jsonb(v_gen), 'new_flags', v_flags,
    'stale_count', k.stale_count, 'total_reports', k.total_reports, 'report_types', k.report_types);
end $$;
revoke all on function public.fn_reporting_ai() from anon, authenticated, public;

-- Register the agent
insert into public.category_agents(slug, name, emoji, active, persona)
values ('reporting_ai','Reporting AI','📊', true,
  'I generate and keep fresh every business report — daily briefing, weekly board report, monthly and quarterly reports, and department, supplier, customer, financial and AI reports plus executive summaries. I catalog every report in one place and flag any scheduled report that is stale or missing. I only ever produce internal report documents; sending a report to the board or anyone external is always your call.')
on conflict (slug) do update set name=excluded.name, emoji=excluded.emoji, active=true, persona=excluded.persona;

-- Daily schedule (04:20 UTC ~ 08:20 UAE), after the KPI agents have snapshotted
select cron.schedule('reporting_ai_daily','20 4 * * *', $cron$
  select net.http_post(
    url:='https://htdblwldjkcgjvmqkbeh.supabase.co/functions/v1/agent_run',
    headers:=jsonb_build_object('Content-Type','application/json'),
    body:=jsonb_build_object('agent','reporting_ai','__secret',(select value from public.app_secrets where key='inbound_secret'))
  );
$cron$);
