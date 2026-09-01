-- THE SECURITY DEPARTMENT ACTS — an autonomous detect → contain → own loop (deterministic, no inference).
--
-- Founder's rule (2 Sep 2026): an agent is an expert human staff member who ACTS — it SOLVES issues in
-- its domain itself, it does not email the founder to solve them. The audit found the security agents
-- could detect/record/alert but could not CONTAIN, the auth-attack detector (v_auth_watch) had zero
-- consumers, and nothing watched the build-mode open door. This wires the acting layer:
--   * fn_secops_close_build_mode_door — the containment hand: closes an open door.
--   * fn_secops_watch — the loop: consumes v_auth_watch + the door, and for each threat the agent
--     ACTS (auto-closes an unauthorized door) and OWNS it (opens an os_incident owned by 'security',
--     never the founder). founder_alerts rows are a RECORD of what the agent did, not a request.
-- Deterministic and safe now; the reasoning/judgment layer adds on top when the runtime is on.
--
--   node scripts/apply_sql.mjs scripts/sql/secops_autonomous_watch.sql --apply --ddl

begin;

-- The containment hand. Closing the door is the agent's response to an unauthorized open. A founder
-- open (actor = his address) is authorized and is never touched here — the agent does not fight the founder.
create or replace function public.fn_secops_close_build_mode_door(p_reason text default 'closed by security')
 returns jsonb language plpgsql security definer set search_path to 'public','pg_temp'
as $fn$
declare v_door record;
begin
  select * into v_door from public.os_open_access_log order by id desc limit 1;
  if v_door.state is distinct from 'open' then
    return jsonb_build_object('ok', true, 'action', 'none', 'reason', 'door already closed');
  end if;
  insert into public.os_open_access_log(at, actor, state, reason, detail)
  values (now(), 'fn_secops_watch', 'closed', coalesce(p_reason,'closed by security'),
          jsonb_build_object('closed_open_id', v_door.id, 'open_actor', v_door.actor));
  return jsonb_build_object('ok', true, 'action', 'closed', 'closed_open_id', v_door.id, 'was_open_by', v_door.actor);
end $fn$;
revoke execute on function public.fn_secops_close_build_mode_door(text) from public;
grant execute on function public.fn_secops_close_build_mode_door(text) to service_role;

-- The loop the security agent runs. Detect → act → own. Idempotent within the hour on repeated signals.
create or replace function public.fn_secops_watch()
 returns jsonb language plpgsql security definer set search_path to 'public','pg_temp'
as $fn$
declare
  v_found int := 0; v_acted int := 0; r record; v_door record;
  v_authorized text[] := array['management@quotesdone.com']; -- founder-authorized door openers
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
end $fn$;
revoke execute on function public.fn_secops_watch() from public;
grant execute on function public.fn_secops_watch() to service_role;

-- Run it autonomously every 10 minutes. It writes founder_alerts/os_incidents ONLY on a real threat,
-- so it is registered in the committed-scenario cron ledger with an honest "produces nothing in a
-- fixture scenario" note (fn_phase_d_committed_scenario_guards passes).
select cron.schedule('secops_watch_10min', '*/10 * * * *', $$select public.fn_secops_watch();$$);
insert into public.phase_d_committed_scenario_cron(jobid, jobname, reaches, quarantine)
select j.jobid, 'secops_watch_10min',
  'public.founder_alerts + public.os_incidents + public.security_events + public.os_open_access_log, but ONLY when a genuine threat is detected: a v_auth_watch high/critical signal (brute force, credential stuffing, OTP/verify abuse, anomalous admin login) or a build-mode open door under an unrecognized actor. No fixture/committed-scenario path produces a real threat signal, so during a Phase D scenario this cron writes nothing.',
  'none required — the security watch writes a watched relation only in response to a real threat, which a committed fixture scenario never produces; a scenario open() therefore has nothing of this cron to remove.'
from cron.job j where j.jobname='secops_watch_10min'
on conflict (jobid) do update set jobname=excluded.jobname, reaches=excluded.reaches, quarantine=excluded.quarantine;

commit;
