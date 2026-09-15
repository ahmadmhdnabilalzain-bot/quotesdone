-- AN OS INCIDENT IS TOLD THROUGH THE MAIL POLICY, NOT TO A FUNCTION THAT DOES NOT EXIST.
--
-- Assigned: it_engineer (seat audit, 15 Sep 2026, finding 3).
--
-- MEASURED 15 Sep 2026. fn_os_incident_open posted every new incident with net.http_post to
-- /functions/v1/alert_founder. No edge function of that name is deployed (the project's function list
-- has no alert_founder), so every post 404'd into pg_net and nobody was told. It was also the last
-- raw HTTP page to the founder in the database: of the public routines only this one names
-- alert_founder beside net.http_post.
--
-- THE FIX. The notice goes through fn_notify_founder, the one founder-mail path. founder_mail_policy
-- decides: kind 'os_incident' is registered with allowed_to_email = false today, so the notice is
-- ROUTED (one open task per condition, fn_founder_mail_route) and not emailed. If the founder ever
-- allows the kind, the same call emails him, once per incident (dedupe key 'os_incident:<id>').
-- customer_support is the owner, so an allowed email is adopted into its delivery loop
-- (fn_customer_support_adopts_untracked_send).
--
-- WHAT THIS DOES NOT CHANGE. The row, the audit line, and the table triggers that give an incident an
-- owner and a due time (incidents_get_an_owner_a_task_and_a_watchdog.sql) are as before. Nothing in the
-- database calls this routine today (0 SQL callers, 0 open incidents, 62 historic). The scheduler-down
-- page, the other half of finding 3, lives in supabase/functions/resilience_ping/index.ts.
--
--   node scripts/apply_sql.mjs scripts/sql/an_os_incident_is_told_through_the_mail_policy_not_a_function_that_does_not_exist.sql --apply --ddl

create or replace function public.fn_os_incident_open(p_title text, p_kind text, p_severity text, p_detail jsonb, p_actor text)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare nid bigint;
begin
  if coalesce(p_title, '') = '' then return jsonb_build_object('ok', false, 'error', 'title_required'); end if;
  insert into public.os_incidents (title, kind, severity, detail, opened_by)
  values (p_title, coalesce(nullif(p_kind, ''), 'other'), coalesce(nullif(p_severity, ''), 'medium'),
          coalesce(p_detail, '{}'::jsonb), coalesce(p_actor, 'os'))
  returning id into nid;
  insert into public.os_audit_log (actor, action, entity, entity_id, detail, ok)
  values (coalesce(p_actor, 'os'), 'incident_open', 'incident', nid::text,
          jsonb_build_object('title', p_title, 'severity', p_severity), true);
  -- Best effort, as before: an incident is recorded even when telling someone about it fails.
  begin
    perform public.fn_notify_founder(
      p_event       => 'OS incident #' || nid || ' (' || coalesce(nullif(p_severity, ''), 'medium') || '): ' || p_title,
      p_detail      => left(coalesce(p_detail->>'description', ''), 300),
      p_level       => coalesce(nullif(p_severity, ''), 'medium'),
      p_kind        => 'os_incident',
      p_dedupe_key  => 'os_incident:' || nid,
      p_owner_agent => 'customer_support');
  exception when others then null;
  end;
  return jsonb_build_object('ok', true, 'id', nid);
end $fn$;

revoke execute on function public.fn_os_incident_open(text, text, text, jsonb, text) from public, anon, authenticated;
