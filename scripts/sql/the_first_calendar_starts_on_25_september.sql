-- THE FIRST CALENDAR STARTS ON 25 SEPTEMBER, NOT IN OCTOBER (24 Sep 2026; seat: marketing).
--
-- Founder, 24 Sep 2026: the first calendar starts TOMORROW, Friday 25 Sep 2026, a UAE working day; same 12 videos,
-- same cadence (three video days a week, Monday / Wednesday / Thursday after the Friday start), same per-platform
-- Dubai times (LinkedIn 11:30, Facebook 13:00, YouTube 17:30, Instagram 19:30, TikTok 20:30), working days only.
-- Campaign 7 (2026-month1-supplier-recruitment, 60 posts) was loaded from docs/marketing/2026-10_social_calendar.json
-- (#914 via #915) for 5-29 Oct. This moves the LOADED rows to the same dates as the renamed file
-- docs/marketing/2026-09_social_calendar.json, renames the post keys oct26-* -> m1-* and the campaign's month and
-- title so nothing says October. The video, captions, hashtags and links are untouched.
--
--   old day   -> new day              old day   -> new day
--   Mon 5 Oct -> Fri 25 Sep           Mon 19 Oct -> Thu 8 Oct
--   Wed 7 Oct -> Mon 28 Sep           Wed 21 Oct -> Mon 12 Oct
--   Thu 8 Oct -> Wed 30 Sep           Thu 22 Oct -> Wed 14 Oct
--   Mon 12 Oct -> Thu 1 Oct           Mon 26 Oct -> Thu 15 Oct
--   Wed 14 Oct -> Mon 5 Oct           Wed 28 Oct -> Mon 19 Oct
--   Thu 15 Oct -> Wed 7 Oct           Thu 29 Oct -> Wed 21 Oct
-- Every new day is a UAE working day (fn_is_working_day; no public holiday falls in 25 Sep - 21 Oct 2026).
--
-- The content hash changes (it includes each time), so fn_marketing_calendar_due owes the calendar email 30 minutes
-- after this commits and marketing_channels sends it on its next 15-minute beat; his "approve" then schedules and
-- publishes the month (one_approve_schedules_and_publishes_the_month_on_working_days.sql, applied BEFORE this file).
-- Returns a verdict row; it writes the data it is meant to keep, so it never raises.
--
--   node scripts/apply_sql.mjs scripts/sql/the_first_calendar_starts_on_25_september.sql --apply

begin;

with moves(old_day, new_day) as (values
  (date '2026-10-05', date '2026-09-25'), (date '2026-10-07', date '2026-09-28'), (date '2026-10-08', date '2026-09-30'),
  (date '2026-10-12', date '2026-10-01'), (date '2026-10-14', date '2026-10-05'), (date '2026-10-15', date '2026-10-07'),
  (date '2026-10-19', date '2026-10-08'), (date '2026-10-21', date '2026-10-12'), (date '2026-10-22', date '2026-10-14'),
  (date '2026-10-26', date '2026-10-15'), (date '2026-10-28', date '2026-10-19'), (date '2026-10-29', date '2026-10-21'))
update public.marketing_post p
   set scheduled_at = ((m.new_day + (p.scheduled_at at time zone 'Asia/Dubai')::time) at time zone 'Asia/Dubai'),
       scheduled_local = (m.new_day + (p.scheduled_at at time zone 'Asia/Dubai')::time),
       ingest_key = regexp_replace(p.ingest_key, '^oct26-', 'm1-'),
       updated_at = now()
  from moves m, public.marketing_campaign c
 where c.campaign_key = '2026-month1-supplier-recruitment' and p.campaign_id = c.id
   and p.status in ('draft', 'scheduled') and p.ingest_key like 'oct26-%'
   and (p.scheduled_at at time zone 'Asia/Dubai')::date = m.old_day;

update public.marketing_campaign
   set month = '2026-09-01',
       title = 'First month (25 Sep to 21 Oct 2026): supplier recruitment and how QuotesDone works',
       updated_at = now()
 where campaign_key = '2026-month1-supplier-recruitment';

select case when n = 60 and first_at = '2026-09-25 11:30' and last_at = '2026-10-21 20:30' and off_day = 0 and old_keys = 0
                 and days = 12 and times = 5
            then 'PROBE OK: 60 posts on 12 working days, 25 Sep 11:30 to 21 Oct 20:30 Dubai, keys m1-*'
            else 'PROBE FAILED: ' || json_build_object('n', n, 'first', first_at, 'last', last_at, 'off_day', off_day,
                                                          'old_keys', old_keys, 'days', days, 'times', times)::text end as verdict
  from (select count(*) n, to_char(min(p.scheduled_local), 'YYYY-MM-DD HH24:MI') first_at,
               to_char(max(p.scheduled_local), 'YYYY-MM-DD HH24:MI') last_at,
               count(*) filter (where not public.fn_is_working_day(p.scheduled_local::date)) off_day,
               count(*) filter (where p.ingest_key like 'oct26-%') old_keys,
               count(distinct p.scheduled_local::date) days, count(distinct p.scheduled_local::time) times
          from public.marketing_post p join public.marketing_campaign c on c.id = p.campaign_id
         where c.campaign_key = '2026-month1-supplier-recruitment' and p.status <> 'cancelled') s;

commit;
