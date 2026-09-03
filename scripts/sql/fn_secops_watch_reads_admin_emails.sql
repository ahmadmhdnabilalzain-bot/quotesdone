-- fn_secops_watch reads the founder allow-list from app_secrets.admin_emails (3 Sep 2026).
--
-- MASTER_PLAN 5.3: the security watcher hardcoded array['management@quotesdone.com'] as the set of
-- founder-authorized door openers. Every admin-gated edge function already reads that list from
-- app_secrets.admin_emails; the watcher now reads the same row (lower-cased, trimmed), and an unset
-- row authorizes nobody. Every other line is the live definition, unchanged.
--
--   node scripts/apply_sql.mjs scripts/sql/fn_secops_watch_reads_admin_emails.sql --apply --ddl
CREATE OR REPLACE FUNCTION public.fn_secops_watch()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_found int := 0; v_acted int := 0; r record; v_door record;
  -- 3 SEP 2026 (MASTER_PLAN 5.3): the founder allow-list is DATA — app_secrets.admin_emails, the same
  -- list every admin-gated edge function reads — not a literal typed into the watcher. Unset means
  -- nobody is a founder-authorized door opener, never "fall back to a name".
  v_authorized text[] := coalesce(
    (select array_agg(lower(btrim(x))) from public.app_secrets s, unnest(string_to_array(s.value, ',')) x
      where s.key = 'admin_emails' and btrim(x) <> ''),
    '{}'::text[]);
begin
  -- 1. AUTH ATTACKS — consume v_auth_watch (the signature aggregator that had no consumer): brute force,
  --    credential stuffing, OTP/verify abuse, anomalous admin logins. The agent OWNS each as an incident.
  for r in select at, signal, severity, subject, detail from public.v_auth_watch
           where severity in ('high','critical') loop
    if not exists (
      select 1 from public.security_events se
       where se.kind='auth_attack' and coalesce(se.subject,'')=coalesce(r.subject,'')
         and se.detail->>'signal'=r.signal and se.created_at > now() - interval '1 hour') then
      insert into public.security_events(kind, severity, source, subject, detail)
      values ('auth_attack', r.severity, 'fn_secops_watch', r.subject,
              jsonb_build_object('signal', r.signal, 'detail', r.detail, 'observed_at', r.at));
      insert into public.os_incidents(title, kind, severity, status, detail, opened_by, owner, opened_at)
      values (left('Auth attack: '||r.signal||' on '||coalesce(r.subject,'unknown'),200),
              'security', r.severity, 'open',
              jsonb_build_object('signal', r.signal, 'subject', r.subject, 'detail', r.detail, 'source','fn_secops_watch'),
              'fn_secops_watch', 'security', now());
      insert into public.founder_alerts(level, event, detail, channel)
      values (r.severity, 'security: auth attack detected',
              'signal='||r.signal||' subject='||coalesce(r.subject,'unknown')
              ||' — the security agent opened and owns an incident and is responding.', 'log');
      v_found := v_found + 1;
    end if;
  end loop;

  -- 2. BUILD-MODE OPEN DOOR — an open under an UNRECOGNIZED actor is not a founder command; the agent
  --    CLOSES it itself and records the action. A founder-authorized open is left alone (never fight him).
  select * into v_door from public.os_open_access_log order by id desc limit 1;
  if v_door.state = 'open' then
    if v_door.actor is null or lower(v_door.actor) <> all(v_authorized) then
      perform public.fn_secops_close_build_mode_door(
        'Auto-closed by the security watch: build-mode door was open under an unrecognized actor ('
        || coalesce(v_door.actor,'null') || '), which no founder command justifies.');
      insert into public.security_events(kind, severity, source, subject, detail)
      values ('build_mode_door_unauthorized_open', 'critical', 'fn_secops_watch', v_door.actor,
              jsonb_build_object('open_id', v_door.id, 'open_reason', v_door.reason));
      insert into public.os_incidents(title, kind, severity, status, detail, opened_by, owner, opened_at, resolved_by, resolved_at, resolution)
      values ('Unauthorized build-mode door open — auto-closed', 'security', 'critical', 'resolved',
              jsonb_build_object('open_actor', v_door.actor, 'open_id', v_door.id),
              'fn_secops_watch', 'security', now(), 'fn_secops_watch', now(),
              'The security agent auto-closed the unauthorized open door.');
      insert into public.founder_alerts(level, event, detail, channel)
      values ('critical', 'security: unauthorized build-mode door auto-closed',
              'An open build-mode door under actor '||coalesce(v_door.actor,'null')
              ||' was auto-closed by the security agent. No action needed from you.', 'log');
      v_acted := v_acted + 1;
    end if;
  end if;

  return jsonb_build_object('checked_at', now(), 'threats_found', v_found, 'auto_actions', v_acted);
end $function$

