-- A MESSAGE CUSTOMER SUPPORT WRITES IS SENT LIKE ANY PERSON MAIL (it_engineer, 19 Nov 2026).
-- Assigned: it_engineer (outbox scheduling; owner of fn_outbox_person_kinds, see
-- a_mail_a_person_waits_for_leaves_within_a_minute_and_a_notice_with_no_route_says_why.sql).
--
-- MEASURED (production, SELECT and catalogue reads only, 19 Nov 2026 13:59-14:03Z):
--   * notifications 150035 (type duty_support_lost_request, e-mail, sender customer_support, to_role customer, kind null,
--     not_before null, attempts 0) was written 13:45:54.40Z by customer support's model-written voice
--     (fn_customer_support_voice_send -> fn_customer_support_duty_send, type = 'duty_' || replace(stage, '.', '_')).
--     At 14:02Z it was still queued, never claimed. It is the only queued notification of the last 7 days.
--   * THE KICK DOES NOT SEE IT. fn_outbox_person_kinds() is a fixed list of 7 kinds (registration_received,
--     company_name_from_licence, supplier_approved, supplier_mailbox_reply, new_message, invoice_ready, reveal_receipt);
--     no type the voice writes is on it, so outbox_person_mail_kick (job 1732, every minute) never posts for it.
--     Its cron log reads "0 rows" every minute whatever the kick did: that is the :17 sweep's empty WHERE, the last statement.
--   * THE HEARTBEAT MISSED IT TWICE OVER. Ordinary mail is drained only by resilience_ping's outbox step (Vercel cron
--     /api/resilience-ping, */15). (a) supportVoice is a DETACHED step that finishes after the outbox step: the 13:45 tick
--     called send_outbox at 13:45:48, and the voice wrote 150035 six seconds later, so every voice message misses its own
--     tick. (b) On the :00 and :30 ticks the outbox step fails: finding duty:heartbeat:outbox, open, seen 380 times,
--     "Rate limit exceeded for trace ... Retry after 22830ms" (14:00:59Z). Last 24 h: 97 heartbeats, send_outbox ran on
--     24 of 24 :15 ticks and 23 of 24 :45 ticks but on 4 :00 and 3 :30 ticks. So general mail leaves every 30 minutes,
--     and voice mail written at :45 waits for the next :15 (30 minutes).
--   * The voice writes seven types today (the stages passed to fn_customer_support_voice_owe in the five callers, plus
--     support.lost_request): duty_after_reveal_widget_filed, duty_complaint_acknowledge, duty_complaint_update,
--     duty_dispute_intake_answer, duty_incident_holding, duty_incident_resolved, duty_support_lost_request. Each answers a
--     person (a complaint, an incident, a dispute, a lost request). Only one is duty_support_%, so a duty_support_% rule
--     would miss six of the seven.
--
-- CHANGE: fn_outbox_person_kinds() keeps its 7 kinds and adds every type customer support's voice has written in the last
--   7 days, read from its own ledger (customer_support_voice_owed.written_at; type = 'duty_' || replace(stage, '.', '_')).
--   A future voice stage is covered the day it first writes, with no edit here. Code-written duty mail (activation.*,
--   winback.dormant, concierge.*: fn_customer_support_duty_send called directly, never through the voice) is not in that
--   ledger, so it keeps the heartbeat's pace, as the allow-list's rule requires. The function now reads a table, so it is
--   STABLE (it was IMMUTABLE); its one caller is fn_outbox_person_mail_kick(), which reads it once a call, and no index,
--   default or generated column depends on it (pg_depend: 0 rows). The list is capped at 20 names, the most
--   send_outbox reads from body.kinds (channels.ts askedKinds: /^[a-z0-9_]{1,64}$/, slice 0..20); a name outside that
--   pattern is dropped here, so the kick never asks for a kind send_outbox would silently ignore.
--   NOTHING ELSE CHANGES: the kick's WHERE (queued, no not_before, created in the last 15 minutes) and send_outbox are as
--   they are, so no deploy. The claim takes only status queued/pending rows and marks them 'sending'; a sent row is
--   never claimed again, so nothing already sent is resent.
-- WHAT IT DOES NOT FIX: the :00/:30 outbox failures (duty:heartbeat:outbox). They are the edge runtime's per-trace limit
--   on function-to-function calls inside one resilience_ping invocation; the kick posts through pg_net, a separate
--   trace, so it is not subject to that limit. That finding is still open and is the next change.
-- ROW 150035: this file does not send it and does not touch it. Its created_at (13:45:54Z) is outside the kick's 15-minute
--   window from 14:00:54Z, so the kick will not count it; the heartbeat's next working drain (:15 or :45) sends it like
--   any queued mail, and the probe below says which state it is in. Rewriting created_at to bring it into the window
--   would falsify the record of when the customer was written to, and is not done.
--
-- SEAT: it_engineer. Apply (after review):
--   node scripts/apply_sql.mjs scripts/sql/a_message_customer_support_writes_is_sent_like_any_person_mail.sql --apply --ddl --seat it_engineer
--   then append the file as the LAST line of scripts/sql/MANIFEST.txt (Edit tool). Until applied it carries
--   scripts/sql/pending/a_message_customer_support_writes_is_sent_like_any_person_mail.txt.
-- ROLLBACK (the body this replaces, live on 19 Nov 2026):
--   create or replace function public.fn_outbox_person_kinds() returns text[] language sql immutable security definer
--     set search_path to 'public', 'pg_temp' as $fn$ select array['registration_received', 'company_name_from_licence',
--     'supplier_approved', 'supplier_mailbox_reply', 'new_message', 'invoice_ready', 'reveal_receipt']::text[] $fn$;
-- Prevented by: the probe below (it fails if the voice's type is missing, the list is over 20, a name breaks the pattern,
--   or the routine is open to anon or authenticated). Its duty_support_lost_request assertion holds while that stage's
--   owed row is inside the 7-day window, i.e. until 26 Nov 2026 13:45Z; apply before then.

set local lock_timeout = '1500ms';

create or replace function public.fn_outbox_person_kinds()
returns text[] language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  select (array['registration_received', 'company_name_from_licence', 'supplier_approved',
                'supplier_mailbox_reply', 'new_message', 'invoice_ready', 'reveal_receipt']::text[]
          || coalesce((select array_agg(v.k order by v.k)
                         from (select distinct 'duty_' || replace(o.stage, '.', '_') k
                                 from public.customer_support_voice_owed o
                                where o.written_at > now() - interval '7 days') v
                        where v.k ~ '^[a-z0-9_]{1,64}$'
                          and v.k <> all (array['registration_received', 'company_name_from_licence', 'supplier_approved',
                                                'supplier_mailbox_reply', 'new_message', 'invoice_ready', 'reveal_receipt'])),
                      '{}'::text[]))[1:20]
$fn$;

revoke execute on function public.fn_outbox_person_kinds() from public, anon, authenticated;

-- PROBE: read-only; returns its verdict as a row (the file holds DDL, so it must not raise). It sends nothing and changes
-- no notification: it evaluates the kick's WHERE against row 150035 instead of calling the kick.
with k as (select public.fn_outbox_person_kinds() v),
     r as (select n.id, n.status, n.sent_at, n.created_at,
                  (n.status = 'queued' and (n.channel is null or n.channel not in ('sms', 'whatsapp'))
                   and coalesce(n.kind, n.type) = any ((select v from k)::text[]) and n.not_before is null) kinds_match,
                  n.created_at > now() - interval '15 minutes' in_window
             from public.notifications n where n.id = 150035),
     f as (select count(*) n from pg_proc p join pg_namespace s on s.oid = p.pronamespace
            where s.nspname = 'public' and p.proname = 'fn_outbox_person_kinds' and p.prosecdef and p.provolatile = 's'
              and exists (select 1 from unnest(p.proconfig) cfg where cfg like 'search_path=%')
              and not has_function_privilege('anon', p.oid, 'execute')
              and not has_function_privilege('authenticated', p.oid, 'execute'))
select case
  when (select n from f) <> 1 then 'PROBE FAILED: fn_outbox_person_kinds is not a stable security definer with a pinned search_path closed to anon/authenticated'
  when not ('duty_support_lost_request' = any ((select v from k)::text[])) then 'PROBE FAILED: duty_support_lost_request is not in fn_outbox_person_kinds()'
  when cardinality((select v from k)) > 20 then 'PROBE FAILED: ' || cardinality((select v from k)) || ' kinds, over send_outbox''s 20'
  when exists (select 1 from unnest((select v from k)) x where x !~ '^[a-z0-9_]{1,64}$') then 'PROBE FAILED: a kind send_outbox would drop'
  when (select status from r) = 'queued' and not (select kinds_match from r) then 'PROBE FAILED: 150035 is queued and the kick''s WHERE still does not match it'
  else 'PROBE OK: ' || cardinality((select v from k)) || ' kinds incl. duty_support_lost_request; 150035 '
       || coalesce((select case when status = 'queued'
                                then 'queued, kinds match, ' || case when in_window then 'inside' else 'OUTSIDE' end
                                     || ' the 15-min window (created ' || created_at || '): '
                                     || case when in_window then 'the next kick sends it'
                                             else 'the kick will not count it; the next heartbeat drain sends it' end
                                else status || coalesce(' at ' || sent_at, '') || ': not queued, so nothing claims or resends it' end
                     from r), 'not found')
  end as verdict;
