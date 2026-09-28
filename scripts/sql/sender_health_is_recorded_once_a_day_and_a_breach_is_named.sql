-- SENDER HEALTH IS RECORDED ONCE A DAY, AND A BREACH IS NAMED IN THE ROW.
-- Seat: it_engineer. 28 Sep 2026.
--
-- Gap: duty 10 ('sender', daily, fn_it_duties_scheduled) already reads SPF/DKIM/DMARC, the
-- blocklists, the bounce and complaint rates and the WhatsApp quality rating, and raises a finding
-- on each breach. It keeps no history: the reading is settled into findings and discarded, so
-- "what was our complaint rate last Tuesday" had no answer and a slow drift under the threshold was
-- invisible. This file adds one row per day and a single verdict function that names every breach.
--
-- The verdict uses the SAME thresholds duty 10 uses (it_engineer_threshold via fn_it_threshold):
--   sender_complaint_rate_max 0.003  (Gmail/Yahoo bulk-sender rule, Feb 2024: under 0.3%)
--   sender_bounce_rate_max    0.02   (hard bounces under 2%)
--   sender_min_sends_7d       20     (below this the rates are not evaluated)
-- The rate thresholds are FRACTIONS (0.003 = 0.3%) and are compared unscaled against
-- complaints / sent, exactly as duty 10 compares them. (Review of #992: an earlier draft multiplied
-- the complaint threshold by 10, so a breach fired only at 3%.)
-- Findings stay with duty 10; this row does not raise a second copy of the same finding.
--
-- DMARC aggregate reports: MEASURED 28 Sep 2026, _dmarc.quotesdone.com is
-- "v=DMARC1; p=quarantine; rua=mailto:management@quotesdone.com". That mailbox is not a store this
-- estate reads (inbound_messages keeps no attachments, and the rua address is not routed to
-- inbound_email), so the aggregate XML cannot be parsed here. The row records the rua target the
-- reading found and says 'unavailable' rather than inventing a pass. What would move it: point rua
-- at an address routed to inbound_email and keep the .xml.gz attachment.
--
-- Called by resilience_ping right after fn_it_duties_scheduled, with the same reading.
-- Prevented by: scripts/checks/sender_health_verdict_names_every_breach.test.mjs
--
--   node scripts/apply_sql.mjs scripts/sql/sender_health_is_recorded_once_a_day_and_a_breach_is_named.sql --apply --ddl

create table if not exists public.it_sender_health_daily (
  day              date primary key,
  sent_7d          integer not null,
  hard_bounces_7d  integer not null,
  complaints_7d    integer not null,
  bounce_rate      numeric,
  complaint_rate   numeric,
  whatsapp_quality text,
  blocklisted      integer not null default 0,
  dmarc            jsonb,
  breaches         text[] not null default '{}',
  recorded_at      timestamptz not null default now()
);
alter table public.it_sender_health_daily enable row level security;
drop policy if exists it_sender_health_daily_service_role_only on public.it_sender_health_daily;
create policy it_sender_health_daily_service_role_only on public.it_sender_health_daily
  as permissive for all to public using (false) with check (false);
revoke all on public.it_sender_health_daily from anon, authenticated;

-- Pure: the numbers in, every breach out. A rate below the minimum sample is not evaluated.
create or replace function public.fn_it_sender_health_verdict(
  p_sent numeric, p_hard_bounces numeric, p_complaints numeric, p_whatsapp_quality text, p_blocklisted integer)
 returns text[]
 language sql
 stable
 security definer
 set search_path to 'public', 'pg_temp'
as $fn$
  select array_remove(array[
    case when p_sent >= coalesce(public.fn_it_threshold('sender_min_sends_7d'), 20)
          and p_complaints / nullif(p_sent, 0) > coalesce(public.fn_it_threshold('sender_complaint_rate_max'), 0.003)
         then 'complaint_rate' end,
    case when p_sent >= coalesce(public.fn_it_threshold('sender_min_sends_7d'), 20)
          and p_hard_bounces / nullif(p_sent, 0) > coalesce(public.fn_it_threshold('sender_bounce_rate_max'), 0.02)
         then 'bounce_rate' end,
    case when upper(coalesce(p_whatsapp_quality, 'UNKNOWN')) not in ('HIGH', 'GREEN', 'UNKNOWN')
         then 'whatsapp_quality' end,
    case when coalesce(p_blocklisted, 0) > 0 then 'blocklisted' end
  ], null)
$fn$;
revoke execute on function public.fn_it_sender_health_verdict(numeric, numeric, numeric, text, integer) from public, anon, authenticated;

-- Counts from the same tables duty 10 counts, takes the reading's WhatsApp/blocklist/DMARC parts,
-- and upserts today's row. A second run on the same day replaces the row, it never adds one.
create or replace function public.fn_it_sender_health_record(p_sender jsonb)
 returns public.it_sender_health_daily
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $fn$
declare
  v_sent int; v_bounce int; v_compl int; v_listed int; v_wa text; r public.it_sender_health_daily;
begin
  select count(*) into v_sent from public.notifications
   where channel = 'email' and status = 'sent' and sent_at > now() - interval '7 days';
  select count(*) filter (where reason like 'hard_bounce%'), count(*) filter (where reason = 'spam_complaint')
    into v_bounce, v_compl from public.email_suppressions
   where source = 'resend_webhook' and created_at > now() - interval '7 days';
  select count(*) into v_listed from jsonb_array_elements(coalesce(p_sender->'blocklists', '[]'::jsonb)) b
   where b->>'basis' = 'measured' and coalesce((b->>'listed')::boolean, false);
  v_wa := case when p_sender->'whatsapp'->>'basis' = 'measured' then p_sender->'whatsapp'->>'quality' end;

  insert into public.it_sender_health_daily as t
    (day, sent_7d, hard_bounces_7d, complaints_7d, bounce_rate, complaint_rate, whatsapp_quality, blocklisted, dmarc, breaches)
  values (current_date, v_sent, v_bounce, v_compl,
          round(v_bounce::numeric / nullif(v_sent, 0), 5), round(v_compl::numeric / nullif(v_sent, 0), 5),
          v_wa, v_listed,
          jsonb_build_object('published', (select jsonb_object_agg(key, value->'dmarc') from jsonb_each(coalesce(p_sender->'dns', '{}'::jsonb))),
                             'aggregate', jsonb_build_object('basis', 'unavailable',
                               'reason', 'the rua mailbox is not a store this estate reads')),
          public.fn_it_sender_health_verdict(v_sent, v_bounce, v_compl, v_wa, v_listed))
  on conflict (day) do update set
    sent_7d = excluded.sent_7d, hard_bounces_7d = excluded.hard_bounces_7d, complaints_7d = excluded.complaints_7d,
    bounce_rate = excluded.bounce_rate, complaint_rate = excluded.complaint_rate,
    whatsapp_quality = excluded.whatsapp_quality, blocklisted = excluded.blocklisted,
    dmarc = excluded.dmarc, breaches = excluded.breaches, recorded_at = now()
  returning * into r;
  return r;
end $fn$;
revoke execute on function public.fn_it_sender_health_record(jsonb) from public, anon, authenticated;

-- ══ PROBE ═══════════════════════════════════════════════════════════════════════════════════
-- DDL above, so the verdict is a ROW. Pure inputs only; nothing is written.
select case
  when not ('complaint_rate' = any (public.fn_it_sender_health_verdict(1000, 0, 5, 'GREEN', 0)))
    then 'PROBE FAILED: 0.5% complaints did not flag'
  when public.fn_it_sender_health_verdict(1000, 0, 2, 'GREEN', 0) <> '{}'
    then 'PROBE FAILED: 0.2% complaints flagged'
  when not ('bounce_rate' = any (public.fn_it_sender_health_verdict(1000, 30, 0, 'HIGH', 0)))
    then 'PROBE FAILED: 3% hard bounces did not flag'
  when public.fn_it_sender_health_verdict(10, 5, 5, 'GREEN', 0) <> '{}'
    then 'PROBE FAILED: a rate on fewer than the minimum sends was evaluated'
  when not ('whatsapp_quality' = any (public.fn_it_sender_health_verdict(1000, 0, 0, 'RED', 0)))
    then 'PROBE FAILED: a RED WhatsApp rating did not flag'
  when not ('blocklisted' = any (public.fn_it_sender_health_verdict(1000, 0, 0, 'GREEN', 1)))
    then 'PROBE FAILED: a blocklist listing did not flag'
  else 'PROBE OK: every sender-health breach is named and a healthy day names none' end as verdict;
