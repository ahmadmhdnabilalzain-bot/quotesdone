-- OVERDUE HANDOFFS GET ESCALATED (autonomy audit, degrading gap 12).
--
-- MEASURED. fn_phase_c_handoff_overdue already finds handoffs past their SLA (some 300+ hours late), but
-- nothing acts on the list — no cron reads it, so a stalled handoff sits silent until a human notices. A
-- company where a dropped baton is never picked up does not run itself.
--
-- THIS FILE adds fn_handoff_watchdog, the handoff mirror of fn_os_incident_watchdog: it reads the overdue
-- list and raises ONE deduped founder alert per stuck handoff (deduped against founder_alerts in the last
-- 24 hours, so a persistently-late handoff is not re-alerted every run). It only ESCALATES for visibility
-- (never an approval; the founder boundary is refunds only) and never writes the frozen kernel handoff run
-- or reassigns it — that is kernel territory. It SELF-PAUSES on the founder stand-down, because during the
-- hold every handoff is stalled by design and escalating them all would only be noise.
--
-- The cron is scheduled DISABLED and documented; enable-ready when the founder resumes. New SECURITY
-- DEFINER function -> revoked from PUBLIC.
--
--   node scripts/apply_sql.mjs scripts/sql/overdue_handoffs_get_escalated.sql --apply --ddl

begin;

CREATE OR REPLACE FUNCTION public.fn_handoff_watchdog()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare r record; v_esc int := 0;
begin
  if exists (select 1 from public.company_stand_down where resumed_at is null) then
    return jsonb_build_object('ok', false, 'status','PAUSED_BY_FOUNDER_STANDDOWN', 'escalated',0);
  end if;

  for r in select * from public.fn_phase_c_handoff_overdue() order by hours_late desc loop
    -- dedup: one alert per stuck handoff run per day
    if exists (select 1 from public.founder_alerts
                where event like '%handoff run #'||r.handoff_run_id||'%'
                  and created_at > now() - interval '24 hours') then
      continue;
    end if;
    perform public.fn_notify_founder(
      'Stalled handoff run #'||r.handoff_run_id||' ('||coalesce(r.handoff_id,'?')||') '
        ||round(r.hours_late)||'h past SLA',
      'From '||coalesce(r.sender,'?')||' to '||coalesce(r.receiver,'?')||', due '
        ||to_char(r.due_at,'YYYY-MM-DD HH24:MI')||' UTC and still not accepted. The receiver has not '
        ||'picked up the baton; the workflow cannot advance until it does.',
      'high');
    v_esc := v_esc + 1;
  end loop;

  insert into public.agent_runs(agent, started_at, finished_at, status, counts, note)
  values ('handoff_watchdog', now(), now(), 'ok',
          jsonb_build_object('escalated', v_esc),
          'Handoff watchdog raised '||v_esc||' alert(s) on overdue handoffs.');
  return jsonb_build_object('ok', true, 'escalated', v_esc);
end $function$;

revoke execute on function public.fn_handoff_watchdog() from public;

-- Every 6 hours. DISABLED (escalates work while the workforce is down; self-pauses regardless).
-- CRON SCHEDULE REMOVED 7 September 2026 on the founder's instruction: "there shouldn't be
-- any job in the code except the stuff that I literally told you for the CEO... Remove it from
-- the code. Delete, not archive." The job it created was deleted from the database in the same
-- change. Do not restore this without his word: an estate reaches 235 scheduled jobs precisely
-- by each build adding one and nothing ever removing one.
select cron.alter_job((select jobid from cron.job where jobname='handoff_watchdog_6h'), active := false);
insert into public.cron_registry (jobname, human_name, category, purpose)
values ('handoff_watchdog_6h', 'Escalate overdue handoffs', 'operations',
  'Every 6 hours: raises a deduped founder alert on every handoff past its SLA that the receiver has not accepted, so a dropped baton is noticed instead of stalling silently. Self-pauses on the founder stand-down; scheduled disabled until resume.')
on conflict (jobname) do update
  set human_name = excluded.human_name, category = excluded.category, purpose = excluded.purpose;

commit;
