-- THE DEPARTMENT DISPATCHER'S TRIGGER GOES, ALONE. Seat: ceo. 13 Nov 2026 (fix round W3, third iteration).
-- every_seat_reads_one_pool_and_every_hand_over_comes_back.sql made public.trg_company_event_dispatch() a no-op (its body is
-- `return null`; the ceo.company_pool duty dispatches events now) instead of dropping its trigger, because DROP TRIGGER takes
-- ACCESS EXCLUSIVE on company_event, which blocks every reader and writer of the event stream while it waits (review of
-- 13 Nov evening, item 6: a concurrent event insert waited 1,350 ms behind it, LOCAL). This file removes the dead trigger
-- and its function, on its own, at a quiet minute.
-- APPLY ONLY AFTER the pool file is applied and its trigger function is the no-op (the guard below refuses otherwise).
-- LOCKS: ACCESS EXCLUSIVE on public.company_event for the drop only (milliseconds once granted); lock_timeout 1500ms makes
-- it fail fast instead of queueing the event writers behind it: on a timeout wait 30 s and re-run, at most 3 times.
-- prevented by: scripts/checks/every_seat_reads_one_pool.test.mjs (the pool file never drops a trigger on a busy table)
set local lock_timeout = '1500ms';
do $guard$
begin
  if to_regprocedure('public.trg_company_event_dispatch()') is not null then
    if pg_get_functiondef(to_regprocedure('public.trg_company_event_dispatch()')) !~ 'RETIRED' then
      raise exception 'trg_company_event_dispatch() still has its old body: apply every_seat_reads_one_pool_and_every_hand_over_comes_back.sql first';
    end if;
  end if;
end $guard$;
drop trigger if exists trg_company_event_dispatch on public.company_event;
drop function if exists public.trg_company_event_dispatch();
