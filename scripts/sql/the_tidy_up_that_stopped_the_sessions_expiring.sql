-- fn_control_mode_sweep has been failing every five minutes since 11 Aug, and the thing it stopped
-- was not the tidying up.
--
-- MEASURED on production 13 Aug 2026: cron job control_mode_sweep_5min, 377 consecutive failures,
-- first at 2026-08-11 13:50:00Z, latest at 2026-08-12 21:15:00Z, all of them
--   ERROR: update or delete on table "control_mode_challenge" violates foreign key constraint
--          "control_mode_session_mfa_ref_fk"
-- The constraint is FOREIGN KEY (mfa_ref) REFERENCES control_mode_challenge(id) ON DELETE RESTRICT,
-- and there is exactly one challenge row, consumed more than seven days ago, referenced by the one
-- session row. So the retention DELETE at the end of this function can never succeed and never will.
--
-- WHY THAT MATTERS MORE THAN IT LOOKS. A plpgsql function is one transaction. The DELETE raises, so
-- the two statements ABOVE it roll back with it - and the first of those is the one that closes
-- expired control-mode sessions. The founder's command channel has had no working session timeout
-- for thirty-one hours. Nothing has leaked, because there are zero open sessions right now and the
-- only one on record is already closed; the expiry path simply cannot run, and would not have run
-- the moment it was needed. Another recovery path guarded by a condition that always throws.
--
-- Two changes, in the order they matter:
--   1. Retention can no longer VETO expiry. It sits in its own exception block, so a housekeeping
--      failure is recorded and the security-relevant work still commits.
--   2. The DELETE skips challenges a session still references, which is what ON DELETE RESTRICT was
--      telling it. Those rows are part of that session's audit trail; their code_hash is a hash of a
--      six-digit code that is already consumed, and code_hash and nonce are both NOT NULL so there
--      is nothing to scrub without inventing a retention policy nobody asked for.
create or replace function public.fn_control_mode_sweep()
 returns integer
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
declare v_sessions int; v_deleted int := 0;
begin
  with c as (
    update public.control_mode_session set closed_at = now(), closed_reason = 'expired'
     where closed_at is null and expires_at <= now() returning id, actor_email
  ), a as (
    insert into public.control_mode_audit (actor_email, event, session_id, allowed, reason)
    select actor_email, 'expired', id, true, 'session timed out' from c
  )
  select count(*)::int into v_sessions from c;

  update public.control_mode_challenge
     set consumed_at = now(), consumed_why = 'expired'
   where consumed_at is null and expires_at <= now();

  -- RETENTION, RING-FENCED. Everything above this point is the sweep's actual job; everything
  -- inside is tidying. A failure here is recorded and swallowed so it can never again roll back a
  -- session that was supposed to close.
  begin
    delete from public.control_mode_challenge c
     where c.consumed_at < now() - interval '7 days'
       and not exists (select 1 from public.control_mode_session s where s.mfa_ref = c.id);
    get diagnostics v_deleted = row_count;
  exception when others then
    insert into public.agent_runs(agent, status, counts, note, started_at, finished_at)
    values ('control_mode_sweep', 'error',
            jsonb_build_object('sessions_expired', v_sessions, 'retention_failed', true),
            'Control-mode challenge retention failed but the sweep still expired its sessions: '
            || replace(coalesce(sqlerrm,'unknown'), '''', ''), now(), now());
  end;

  return v_sessions;
end
$function$;
