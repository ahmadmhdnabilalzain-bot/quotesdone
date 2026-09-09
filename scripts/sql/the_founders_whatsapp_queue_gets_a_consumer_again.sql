-- THE FOUNDER'S WHATSAPP QUEUE GETS A CONSUMER AGAIN.
--
-- Measured 9 Sep 2026, while checking why send_outbox reported skipped=1 on every flush:
--
--   public.notifications id 20879 — channel 'whatsapp', kind 'platform_down', to_phone
--   +971509319355, status 'queued' since 2026-09-07 18:15, attempts 0, last_error null.
--
--   public.agent_runs where agent = 'send_whatsapp' — ZERO rows. It has never run, not once.
--
--   Nothing in the repository calls send_whatsapp. It was drained by the pg_cron job wa_flush, and
--   pg_cron was removed on 7 Sep by the founder's instruction — the same day the message stopped
--   moving. The consumer was deleted with the scheduler and no replacement was wired.
--
-- WhatsApp is the founder's command channel. A queue with no consumer there is not cosmetic: every
-- alert routed to WhatsApp since 7 Sep was written and never delivered, and nothing reported it,
-- because attempts = 0 and status = 'queued' look exactly like a message waiting its turn. That is
-- the same shape as a status column standing in for a delivery record.
--
-- send_outbox is NOT the fix: it deliberately skips channel 'whatsapp' rows and leaves them queued
-- (a July 2026 defect destroyed WhatsApp messages by claiming them), so the rows are correctly
-- reserved for a sender that no longer existed.
--
-- THE FIX HAS TWO HALVES AND THIS FILE IS ONLY THE FIRST.
--   1. HERE: fn.resilience_ping may call send_whatsapp. Its scope is send_outbox, alert_founder,
--      dropbox_backup, pdf_native — send_whatsapp is absent, so the tick added in the same change
--      would have 403'd on every run, forever, with nothing on either side saying why. That is
--      precisely how pdf_native was nearly wired dead earlier today.
--   2. IN THE FUNCTION: resilience_ping gains a whatsappTick on the live Vercel-cron path, and
--      send_whatsapp gains the staleness bar send_outbox has had since July. Without that bar,
--      restoring the drainer would immediately deliver the two-day-old "SCHEDULER DOWN" alert to
--      his phone — an outage that had already ended. A stale alert is a lie, not a backlog.
--
-- pg_cron stays dead. The live scheduler is Vercel cron -> /api/resilience-ping.

update public.internal_credential
   set scope = scope || array['send_whatsapp']::text[]
 where context = 'fn.resilience_ping'
   and active
   and not ('send_whatsapp' = any(scope));

insert into public.app_secrets (key, value)
values ('wa_stale_hours', '24')
on conflict (key) do nothing;

comment on table public.internal_credential is
  'One credential per calling context. THE CREDENTIAL DECIDES THE SEAT AND THE REACHABLE FUNCTIONS, '
  'never the caller: scope is the allow-list of functions this context may invoke, and a call to '
  'anything outside it is refused. A missing scope entry fails CLOSED and SILENTLY from the '
  'caller''s point of view -- it reads as a 403 with no explanation of which side is wrong -- so '
  'widening scope is part of wiring a new call, not an afterthought (9 Sep 2026: pdf_native and '
  'send_whatsapp were both nearly wired dead this way).';

do $do$
declare v_scope text[]; v_stale text; v_need text;
begin
  select scope into v_scope from public.internal_credential
   where context = 'fn.resilience_ping' and active;
  if v_scope is null then raise exception 'fn.resilience_ping has no active credential'; end if;
  if not ('send_whatsapp' = any(v_scope)) then
    raise exception 'send_whatsapp is still not in scope: %', v_scope::text;
  end if;
  -- The widening must not have dropped what was already there.
  foreach v_need in array array['send_outbox','alert_founder','dropbox_backup','pdf_native'] loop
    if not (v_need = any(v_scope)) then
      raise exception 'widening the scope LOST an existing entry (%): %', v_need, v_scope::text;
    end if;
  end loop;

  select value into v_stale from public.app_secrets where key = 'wa_stale_hours';
  if v_stale is null then raise exception 'wa_stale_hours was not set'; end if;

  raise notice 'fn.resilience_ping scope = %, wa_stale_hours = %', v_scope::text, v_stale;
end
$do$;
