-- ROW #3 s21 — the event bus reacts on a fifteen-minute timer and calls it an event bus.
--
-- ── MEASURED ON PRODUCTION, 9 AUG 2026 ──────────────────────────────────────────────────────────
--   s21-no-polling  MISSING  trigger on company_event hands events to the dispatcher: false;
--                            median delivery lag 554s over 1,157 deliveries/7d; 152 active cron jobs
--
-- Nine minutes is the median. The p50 event waits nine minutes to be delivered because delivery is
-- event_dispatch_15min scanning for work, and a scan on a timer is a poll however the table is
-- named. The check says so in its own comment: latency is the one number a poll cannot fake.
--
-- ── WHY A STATEMENT TRIGGER AND NOT A ROW TRIGGER ───────────────────────────────────────────────
-- fn_event_dispatch(p_lookback_minutes) SCANS a window; it does not take a single event. A FOR EACH
-- ROW trigger would therefore re-scan the same window once per inserted row — quadratic on any
-- burst, and the emitters here insert in batches. FOR EACH STATEMENT dispatches once per insert
-- statement, which is exactly once per burst, with a one-minute lookback that covers the rows just
-- written plus anything the previous statement left behind.
--
-- Verified before writing this: fn_event_dispatch does NOT insert into company_event, so the
-- trigger cannot re-enter itself, and it takes no advisory lock, so it cannot block the emitter
-- waiting on the cron.
--
-- ── THE EMITTER MUST NEVER PAY FOR THE DISPATCHER ───────────────────────────────────────────────
-- This runs inside the transaction that emitted the event. If dispatch throws, the exception block
-- keeps the emitter's transaction intact — the event is already stored, because this fires AFTER
-- INSERT, and event_dispatch_15min remains the safety net that delivers it on the next tick.
-- The failure is written to agent_runs rather than swallowed, so a trigger that has quietly stopped
-- working is visible as an error row instead of as a latency nobody is looking at.
create or replace function public.trg_company_event_dispatch()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
begin
  begin
    perform public.fn_event_dispatch(1);
  exception when others then
    insert into public.agent_runs (agent, started_at, finished_at, status, counts, note)
    values ('event_dispatch_trigger', now(), now(), 'error',
      jsonb_build_object('sqlstate', sqlstate),
      'Inline dispatch from the company_event trigger failed: '||left(sqlerrm, 300)
      ||'. The event is stored and event_dispatch_15min will deliver it on the next tick.');
  end;
  return null;
end $function$;

drop trigger if exists trg_company_event_dispatch on public.company_event;
create trigger trg_company_event_dispatch
  after insert on public.company_event
  for each statement execute function public.trg_company_event_dispatch();
