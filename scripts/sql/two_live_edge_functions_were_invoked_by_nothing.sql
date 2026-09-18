-- TWO DEPLOYED, OWNED, LIVE EDGE FUNCTIONS WERE INVOKED BY NOTHING.
--
-- MEASURED 17-18 Sep 2026 (it_engineer, wiring audit). pg_cron is empty (one inactive job); since
-- 7 Sep the estate has run off resilience_ping's STEPS list every 15 minutes. Two functions that are
-- deployed, owned and instrumented were left with no caller at all:
--
--   email_cron          -- its own header: "runs every 2 minutes"; it exists to report the one thing
--                          send_outbox structurally CANNOT -- a disabled mail system, which nothing
--                          would invoke to tell you about -- and to auto-detect Resend domain
--                          verification. agent_runs holds exactly ONE row for it, 9 Sep 07:10.
--   wa_templates_watch  -- polls Twilio for WhatsApp template approval and flips wa_templates_ready.
--                          agent_runs holds ONE row, 9 Sep 07:11. WhatsApp is the founder's command
--                          channel.
--
-- WHAT THIS ADDS: the Postgres-side gate for two new resilience_ping steps, in the shape backupTick
-- already uses -- the database decides whether there is work, the tick only acts on the answer. One
-- RPC answers for both, because two round trips inside a 110 s budget that is already overrunning is
-- two round trips too many.
--
-- THE GATES, AND WHY THEY ARE NOT "EVERY TICK".
--
--   email_cron is due only while email_enabled is NOT 'true'. That is precisely the gap it exists to
--   close. When mail is on, resilience_ping's own outboxTick already drains the outbox every tick, so
--   calling email_cron as well would add a second send_outbox flush and one more HTTP hop to a budget
--   that is already tight, and detect nothing that is not already detected. Measured 18 Sep:
--   email_enabled = 'true', so this gate is currently CLOSED and the step costs nothing.
--
--   wa_templates_watch is due only while wa_templates_ready is NOT 'true' -- so the moment Meta
--   approves, it stops polling Twilio instead of calling a third party every 15 minutes for ever.
--   Measured 18 Sep: wa_templates_ready = 'true' already, so this gate is CLOSED too. It is wired
--   anyway because the flag is what re-opens it: a new template submitted for approval sets it back
--   to false, and from then on the watcher runs without anyone having to remember to schedule it.
--
-- NOT CHANGED: neither function's own behaviour, its internal-auth gate, or its throttling. Both
-- already refuse a caller without the shared secret and both already write agent_runs. The defect
-- was never inside them -- it was that nothing said their name.

create or replace function public.fn_resilience_orphan_steps_due()
returns jsonb language sql security definer set search_path to 'public', 'pg_temp' as $fn$
  select jsonb_build_object(
    -- coalesce, not '<>': a missing row must read as "not enabled", which is the state that needs
    -- reporting. A gate that opens only when a key is present and wrong is a gate that a deleted key
    -- switches off silently.
    'email_cron',   coalesce((select value from public.app_secrets where key = 'email_enabled'), '') is distinct from 'true',
    'wa_templates', coalesce((select value from public.app_secrets where key = 'wa_templates_ready'), '') is distinct from 'true'
  )
$fn$;
revoke execute on function public.fn_resilience_orphan_steps_due() from public, anon, authenticated;

-- Read-only probe. This file defines a routine, so it ends in `raise notice`: a `raise exception`
-- would roll the create back with it and the apply would report success over nothing.
do $probe$
declare v jsonb;
begin
  select public.fn_resilience_orphan_steps_due() into v;
  raise notice 'orphan step gates: email_cron due=% wa_templates due=%', v->>'email_cron', v->>'wa_templates';
end $probe$;
