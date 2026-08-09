-- s21-no-polling — the inline dispatcher could only see events younger than sixty seconds.
--
-- MEASURED ON PRODUCTION 2026-08-09. ROW3_STATE recorded "delivery went from a 15-minute scan to
-- 0s measured; the 7-day median converges". The first half is true for a small minority of events.
-- The second half is false and was not converging:
--
--   6 Aug  median 543s     7 Aug  553s     8 Aug  557s     9 Aug  561s
--
--   21 of 508 deliveries over three days were sub-5s (4%). The rest land at 264 / 420-599 / 720 /
--   900 seconds - the cadences of event_dispatch_15min, not of a trigger.
--
-- THE TRIGGER IS NOT THE PROBLEM, AND THE STATEMENT-LEVEL BINDING IS NOT EITHER. Both were
-- suspected and both were cleared by experiment on staging, inserting against a live subscription:
--
--   A  occurred_at = now()          -> delivered inline, 2 deliveries
--   B  occurred_at = now() - 5 min  -> ZERO deliveries
--   C  two rows in ONE statement    -> both delivered, 2 each
--
-- C clears FOR EACH STATEMENT: the function sweeps for undelivered pairs rather than reading NEW,
-- so every row of a multi-row insert is found. B is the defect.
--
-- fn_event_dispatch's argument is p_lookback_minutes, and BOTH of its passes filter
-- `e.occurred_at > now() - make_interval(mins => p_lookback_minutes)`. The trigger passed 1. So an
-- event carrying a real business timestamp more than sixty seconds old is invisible to inline
-- dispatch and waits for the next 15-minute tick. occurred_at is meant to be when the thing
-- happened, not when the row was written, so backdating is correct producer behaviour - the
-- dispatcher was wrong to assume otherwise.
--
-- 20 MINUTES, AND WHY IT IS SAFE. The window must exceed the poller's own 15-minute interval, or
-- there is a band of events the trigger skips and the cron then picks up late - which is the
-- current defect with a smaller number. 20 gives five minutes of margin.
--
-- The latency worry is real and was measured, not waved away: this runs INSIDE the transaction
-- that inserted the event, so a wide window could make an event producer pay for draining a
-- backlog. Production's undelivered backlog right now is ZERO pairs across zero events - the cron
-- keeps up completely - so the loop will find nothing to do on almost every call. And it is
-- bounded anyway: fn_event_dispatch takes `limit c_max_batch` = 50 pairs per call, and the
-- back-pressure cap of 25 open bus tasks per department still governs how much work it may mint.
--
-- Nothing else about the trigger changes. fn_event_dispatch itself is untouched.

create or replace function public.trg_company_event_dispatch()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
begin
  begin
    -- 20, not 1. See the header: at 1 this delivered only events stamped within the last sixty
    -- seconds, which was 4% of them, and everything else fell through to the 15-minute cron.
    perform public.fn_event_dispatch(20);
  exception when others then
    insert into public.agent_runs (agent, started_at, finished_at, status, counts, note)
    values ('event_dispatch_trigger', now(), now(), 'error',
      jsonb_build_object('sqlstate', sqlstate),
      'Inline dispatch from the company_event trigger failed: '||left(sqlerrm, 300)
      ||'. The event is stored and event_dispatch_15min will deliver it on the next tick.');
  end;
  return null;
end $function$;
