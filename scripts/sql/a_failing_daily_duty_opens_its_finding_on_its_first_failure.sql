-- A FAILING DAILY DUTY OPENS ITS FINDING ON ITS FIRST FAILURE, NOT ON THE THIRD DAY (it_engineer, 3 Nov 2026, drill D9).
--
-- Measured: docs/release/qualification_matrix.md §5.1 D9 expects a throwing duty to be isolated and a finding to open
-- within 15 minutes. supabase/functions/resilience_ping/drill_seat_duty_throws.test.ts runs the real fn_seat_duties_tick
-- and fn_seat_duty_health on a throwaway Postgres 16 with a ZZ DEMO duty forced to raise: the isolation holds (the two
-- healthy duties run in the same tick), but no finding opened after the first failure. fn_seat_duty_health raised a
-- failing duty only at failures >= 3, and fn_seat_duty_run adds one failure per RUN, which happens once per `every`:
-- a daily duty was reported on its third day, a weekly one in its third week, while nobody knew it had stopped working.
--
-- What this changes: a duty whose interval is an hour or longer is raised on its first failure. Sub-hourly duties keep
-- three (a 15-minute duty's third failure is 30 minutes in; one transient error there is not worth a page). The finding
-- still closes itself on the first run that passes (fn_seat_duties_tick, unchanged).
-- What this does NOT change: fn_seat_duty_run and fn_seat_duties_tick, and resilience_ping's seatDuties step, which
-- still does not read the tick's per-duty results (the finding is the record). CREATE OR REPLACE keeps the routine's ACL
-- (revoked from public, anon, authenticated; granted to service_role), so no grant is repeated here.
-- Seat: it_engineer (duties and infrastructure).
-- prevented by: supabase/functions/resilience_ping/drill_seat_duty_throws.test.ts

create or replace function public.fn_seat_duty_health()
returns jsonb
language sql stable security definer
set search_path to 'public', 'pg_temp'
as $fn$
  select coalesce(jsonb_agg(jsonb_build_object('duty', d.duty, 'owner_seat', d.owner_seat, 'routine', d.routine,
           'problem', x.problem, 'last_ok_at', d.last_ok_at, 'failures', d.failures, 'last_error', d.last_error)
           order by d.duty), '[]'::jsonb)
    from public.seat_duty d
    cross join lateral (select case
        when not public.fn_seat_duty_routine_exists(d.routine) then 'its routine public.' || d.routine || '() does not exist'
        when not exists (select 1 from public.org_role r where r.role_id = d.owner_seat and r.status = 'active')
          then 'its owner ' || d.owner_seat || ' is not an active seat'
        -- an hourly-or-slower duty is raised on its FIRST failure: its next try is a whole interval away (see the header)
        when d.failures >= case when d.every >= interval '1 hour' then 1 else 3 end
          then 'failed ' || d.failures || ' times running: ' || coalesce(left(d.last_error, 200), '?')
        -- overdue: no success within twice the interval plus one 15-minute tick (a new row gets the same grace)
        when coalesce(d.last_ok_at, d.created_at) < now() - (2 * d.every) - interval '15 minutes'
          then 'no successful run since ' || coalesce(to_char(d.last_ok_at, 'YYYY-MM-DD HH24:MI'), 'it was registered')
      end as problem) x
   where d.enabled and x.problem is not null;
$fn$;
