-- The outbox stall watcher counts only the rows send_outbox owns.
-- Seat: it_engineer. Raised by: watch:queue_stalled:notifications_outbox, open since
-- 2026-09-17T14:16Z, 226 sightings by 2026-09-17T23:46Z.
--
-- WHAT THE FINDING SAID: "notifications: 3 undrained row(s), the oldest waiting 5 hours against a
-- 1-hour threshold". WHAT WAS MEASURED (2026-09-17 23:48 UTC, production, read-only):
--
--   channel   status    n    oldest
--   email     queued    0    —
--   whatsapp  queued    3    2026-09-17 18:31:27Z
--
-- Every queued row is a WhatsApp row. send_outbox does not own WhatsApp: since 15 Sep its queue
-- query excludes channel in ('sms','whatsapp') (supabase/functions/send_outbox/channels.ts,
-- OWNED_CHANNEL_FILTER) precisely so rows of another channel cannot take an email slot, and
-- send_whatsapp drains them instead. send_whatsapp IS running — agent_runs shows it every 15
-- minutes through 2026-09-17 23:45 — and it is deliberately NOT sending these three:
--
--   * app_secrets.wa_per_recipient_24h = 1. One business-initiated WhatsApp per number per 24h,
--     a sender-reputation limit the founder's own Twilio number depends on. Over-cap rows are
--     LEFT 'queued' on purpose ("nothing is lost - it just goes out tomorrow").
--   * the email twin of each alert was sent — send_outbox logged sent:1 at 18:31, 19:31 and 20:46,
--     matching the three rows' created_at to the second. The founder has the alerts.
--
-- So the detector fired on a system that was working, and the registry row is where it was wrong:
-- the predicate is `status = 'queued'` over the WHOLE notifications table, and the threshold is
-- 60 minutes — one twenty-fourth of the window of the policy that parks the rows. Worse, the
-- finding's own founder alert is itself a WhatsApp row subject to the same cap, so each tick
-- re-queued the thing being counted. 226 sightings of a self-feeding loop.
--
-- THE FIX IS THE PREDICATE, NOT THE THRESHOLD. WhatsApp gets its own registry row with its own
-- threshold, and the row named after send_outbox keeps everything else.
--
-- THE TWO PREDICATES ARE COMPLEMENTS, ON PURPOSE. The first cut named the excluded channels —
-- `coalesce(channel,'email') not in ('whatsapp','sms')` — to mirror send_outbox's own filter, and
-- an independent review found the hole immediately: a row of channel 'sms' (or any channel added
-- later) matched NEITHER predicate and would sit queued, undrained and unwatched, indefinitely.
-- Splitting one watcher into two is exactly how a queue ends up watched by nobody. So the split is
-- on `channel = 'whatsapp'` and `channel is distinct from 'whatsapp'`, which partitions every row
-- there can ever be. An SMS row queued for an hour is a real stall — nothing drains channel 'sms'
-- today — and it now reports as one instead of vanishing between two registry rows.
--
-- THE STATUS SET MATCHES THE DRAINERS, NOT THE OLD ROW. send_outbox selects
-- `status.eq.queued,status.eq.pending,status.is.null` (channels.ts selectQueue); the old predicate
-- watched only 'queued', so a row stuck at 'pending' was invisible to the watcher AND would be
-- picked up by the sender — the pairing that hides a stall rather than reporting it. Both rows now
-- use coalesce(status,'queued') in ('queued','pending').
--
-- WHY 1560 MINUTES (26h) FOR WHATSAPP, AND WHY THAT IS NOT A DEAD GUARD. send_whatsapp flips any
-- queued WhatsApp row older than app_secrets.wa_stale_hours (24) to 'held' — an alert that old
-- describes a situation that has probably changed. So while the drainer runs, a queued WhatsApp
-- row CANNOT reach 26 hours: the cap parks it, the staleness bar retires it. The only way the age
-- passes 26 hours is that nothing is draining the queue at all, which is exactly the condition
-- this detector exists to find. It fired for real on 7-9 Sep 2026, when pg_cron's wa_flush was
-- deleted and no consumer replaced it.
--
-- The queue_key 'notifications_outbox' is KEPT so the open finding
-- watch:queue_stalled:notifications_outbox closes itself on the first tick that no longer sees it,
-- rather than being left open under a key nothing writes any more.
--
-- No routine and no table is created here, so there is no revoke and no search_path to pin: the
-- file updates two rows of public.it_watch_queue, which fn_it_detect already reads under its own
-- pinned search_path. RLS and grants on that table are unchanged.

update public.it_watch_queue
   set pending_predicate = $p$coalesce(status, 'queued') in ('queued', 'pending') and channel is distinct from 'whatsapp'$p$,
       note = 'Everything except WhatsApp — the rows send_outbox itself selects (channels.ts '
              'selectQueue), plus any future channel with no drainer, so no queued row falls '
              'between this row and notifications_whatsapp. Counting WhatsApp here fired 226 '
              'times on 17 Sep 2026 against a queue that was working.'
 where queue_key = 'notifications_outbox';

insert into public.it_watch_queue (queue_key, table_name, pending_predicate, ts_column, stall_minutes, surface, enabled, note)
values ('notifications_whatsapp', 'notifications',
        $p$coalesce(status, 'queued') in ('queued', 'pending') and channel = 'whatsapp'$p$,
        'created_at', 1560, 'customer', true,
        'send_whatsapp parks over-cap rows at queued (wa_per_recipient_24h = 1) and retires anything '
        'past wa_stale_hours (24h) to held, so a queued WhatsApp row can only pass 26 hours if nothing '
        'is draining the queue at all — which is what happened 7-9 Sep 2026 when pg_cron''s wa_flush '
        'was deleted with no replacement.')
on conflict (queue_key) do update
   set table_name        = excluded.table_name,
       pending_predicate = excluded.pending_predicate,
       ts_column         = excluded.ts_column,
       stall_minutes     = excluded.stall_minutes,
       surface           = excluded.surface,
       enabled           = excluded.enabled,
       note              = excluded.note;

-- ── PROBE ────────────────────────────────────────────────────────────────────────────────────
-- This file carries a change, so the probe must not abort the transaction on success (a raise
-- exception would roll the two rows above back while the apply still reported success). It writes
-- nothing of its own, so there is nothing to clean up; it asserts against the real rows and raises
-- ONLY on failure — in which case rolling the change back is the correct outcome.
--
-- EVERY ASSERTION IS STRUCTURAL, NOT A SNAPSHOT. The first cut asserted "the email queue counts 0
-- rows", which was true when it was measured and would have rolled this fix back the moment a
-- perfectly healthy email row happened to be queued at apply time. A probe whose failure condition
-- is unrelated to the change is a way to fail a correct change.
do $probe$
declare
  v_email_n   int;
  v_wa_n      int;
  v_wa_old    timestamptz;
  v_wa_age_h  numeric;
  v_leak      int;
  v_total     int;
  r           record;
  v_cnt       int;
  v_oldest    timestamptz;
begin
  -- 1. Every registered predicate still parses and runs the way fn_it_detect runs it. A predicate
  --    that throws is swallowed there as an 'unreadable' note, so the queue silently stops being
  --    watched; here it fails the apply instead.
  for r in select * from public.it_watch_queue where enabled order by queue_key loop
    execute format('select count(*), min(%I) from public.%I where %s', r.ts_column, r.table_name, r.pending_predicate)
      into v_cnt, v_oldest;
    raise notice 'queue % -> % pending, oldest %', r.queue_key, v_cnt, coalesce(v_oldest::text, 'none');
  end loop;

  execute (select format('select count(*) from public.%I where %s', table_name, pending_predicate)
             from public.it_watch_queue where queue_key = 'notifications_outbox')
    into v_email_n;
  execute (select format('select count(*), min(%I) from public.%I where %s', ts_column, table_name, pending_predicate)
             from public.it_watch_queue where queue_key = 'notifications_whatsapp')
    into v_wa_n, v_wa_old;

  -- 2. THE DEFECT ITSELF: the row named after send_outbox must count no WhatsApp row. This is the
  --    thing that fired 226 times, and it is true or false regardless of how busy the queue is.
  execute (select format('select count(*) from public.%I where (%s) and channel = ''whatsapp''', table_name, pending_predicate)
             from public.it_watch_queue where queue_key = 'notifications_outbox')
    into v_leak;
  if v_leak <> 0 then
    raise exception 'CHK<<the notifications_outbox predicate still counts % WhatsApp row(s); those rows are parked by send_whatsapp''s 24h per-recipient cap and send_outbox will never take them>>', v_leak;
  end if;

  -- 3. NO ROW FALLS BETWEEN THE TWO PREDICATES, for any channel value that exists or is ever added.
  --    The two predicates partition on channel = 'whatsapp' / is distinct from 'whatsapp', so this
  --    must hold for every drainable status, not merely for today's three rows.
  select count(*) into v_total from public.notifications
   where coalesce(status, 'queued') in ('queued', 'pending');
  if v_email_n + v_wa_n <> v_total then
    raise exception 'CHK<<% drainable notification row(s) exist but the two registry rows match only % + %: a channel is watched by nobody>>', v_total, v_email_n, v_wa_n;
  end if;

  -- 4. The WhatsApp bar is above what a WORKING send_whatsapp can produce (it retires anything past
  --    wa_stale_hours = 24h to 'held'), so a row past 26h means the drainer itself is down.
  v_wa_age_h := case when v_wa_old is null then 0 else extract(epoch from (now() - v_wa_old)) / 3600 end;
  if v_wa_n > 0 and v_wa_age_h > 26 then
    raise exception 'CHK<<a WhatsApp row has been queued % hours, past the 26-hour bar: send_whatsapp is neither sending nor retiring the queue — the real stall this row exists to catch>>', round(v_wa_age_h, 1);
  end if;

  raise notice 'PROBE OK — notifications_outbox % pending with 0 WhatsApp rows leaking into it, notifications_whatsapp % pending, oldest %h against a 26h bar, and % + % = % covers every drainable row',
    v_email_n, v_wa_n, round(v_wa_age_h, 1), v_email_n, v_wa_n, v_total;
end
$probe$;
