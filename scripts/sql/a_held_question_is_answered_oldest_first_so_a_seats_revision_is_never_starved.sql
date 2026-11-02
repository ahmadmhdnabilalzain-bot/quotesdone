-- A HELD QUESTION IS ANSWERED OLDEST FIRST, SO A SEAT'S REVISION OWED TO THE CEO IS NEVER STARVED BY NEWER ROWS.
-- Seat: it_engineer (the reasoning queue). 27 Oct 2026. NOT APPLIED: see scripts/sql/pending/<this name>.txt.
--
-- MEASURED (production, read-only, 27 Oct 2026 22:08-22:20Z):
--   * fn_reason_held_due (live, canonical file a_refused_turn_is_asked_again_within_minutes_never_left_silent.sql)
--     orders the due rows `last_attempt_at nulls first, created_at desc`: every UNTRIED row before every retry, and
--     the newest untried row first. The 6 Oct header that introduced it (a_held_question_lives_fourteen_days_..._
--     newest_is_answered_first.sql, point 4) says the opposite of what the clause does - "a row already tried still
--     comes before an untried one ... so a retry is never starved" - but NULLS FIRST puts the untried rows first.
--   * The replay claims REPLAY_CLAIM = 2 rows per detached heldReplay run, and the run is kicked by itlater every
--     30 minutes (resilience_step itlater.every = 00:30; last_attempt_at 20:30:43, 21:01:30, 21:31:07, 22:01:29):
--     4 rows an hour. it_engineer.postmortem files 3 new rows every hour (14:00-22:00, measured), so 3 of the 4
--     slots go to new untried rows and the 11 retries share about one slot an hour; an hour with 5 new rows
--     (20:00) leaves them none.
--   * At 22:01 the replay claimed 32940 and 32941 (it_engineer.postmortem, filed 22:00:48, untried) while the four
--     ceo_revision rows filed at 01:05 waited: 28985 (sales_engineer, 2 tries), 28986 and 28987 (marketing, the
--     November month plan the CEO is owed, 1 and 2 tries), 28988 (customer_support, 1 try). 13 rows held at 22:08.
--
-- WHAT THIS CHANGES: fn_reason_held_due only, and in it only the order of the `due` CTE (diffed against the live
-- pg_get_functiondef: two comment lines and the order line). Oldest first, tried or not. Nothing starves: the head
-- of the queue leaves it within three tries (attempts < 3), and a retry still waits 10 minutes after its last try.
-- What this does NOT change: the claim size, the cadence (still kicked by itlater every 30 min), the 3-try bound, the
-- 14-day clock, the hold gate, the re-ask surfaces' exclusion, the fan-out of one answer to its duplicates. It also
-- does not stop it_engineer.postmortem filing three rows an hour, which is the inflow this queue is losing to.
-- The 6 Oct reason for newest-first (284 rows from 23-28 Sep under the founder hold) was answered by the 14-day
-- clock and the 6 Oct expiry of that backlog; at 13 rows the oldest are the ones a seat is blocked on.
--
-- CREATE OR REPLACE keeps the routine's ACL (no revoke needed; it is not re-created). search_path stays pinned.
-- Probe: scripts/sql/a_held_question_is_answered_oldest_first_so_a_seats_revision_is_never_starved_probe.sql
-- Prevented by: scripts/checks/a_held_question_is_answered_newest_first.test.mjs (now asserts oldest first)

CREATE OR REPLACE FUNCTION public.fn_reason_held_due(p_limit integer DEFAULT 3)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_gate jsonb; v jsonb;
begin
  perform public.fn_reason_held_sweep();
  v_gate := public.fn_kernel_paid_provider_gate('hold-probe/not-a-model');
  if coalesce(v_gate->>'rule', '') in ('founder_hold', 'no_paid_ai_switch', 'empty_route_state') then
    return '[]'::jsonb;
  end if;
  with lead as (
    select distinct on (surface, coalesce(qhash, id::text)) id, attempts, last_attempt_at, created_at
      from public.reasoning_held_question
     where status = 'held' and attempts < 3
       and not (surface = any(public.fn_reask_surfaces()))   -- 27 Oct 2026: asked again by fn_reask_due, every minute
     order by surface, coalesce(qhash, id::text), attempts desc, id
  ), due as (
    select h.id from public.reasoning_held_question h
     where h.id in (select id from lead where last_attempt_at is null or last_attempt_at < now() - interval '10 minutes')
     -- 27 Oct: the OLDEST due question first (was: untried first, then newest, 6 Oct). A retry still waits its 10
     -- minutes; after that its age alone decides. The three-try bound keeps one failing row from holding the head.
     order by h.created_at, h.id
     limit greatest(1, least(coalesce(p_limit, 3), 10))
     for update skip locked
  ), claimed as (
    -- 6 Oct: the first claim starts the 14-day clock (a question waits out the hold without ageing)
    update public.reasoning_held_question h set attempts = h.attempts + 1, last_attempt_at = now(),
           expires_at = case when h.attempts = 0 and h.surface not like 'site_assistant.%'
                             then now() + interval '14 days' else h.expires_at end
      from due where h.id = due.id
    returning h.id, h.seat, h.surface, h.request, h.subject, h.created_at
  )
  select coalesce(jsonb_agg(to_jsonb(claimed)), '[]'::jsonb) into v from claimed;
  return v;
end $function$;
