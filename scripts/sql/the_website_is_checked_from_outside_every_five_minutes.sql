-- THE WEBSITE IS CHECKED FROM OUTSIDE EVERY FIVE MINUTES, AND THE FOUNDER IS PAGED WHEN IT IS DOWN.
--
-- Seat: it_engineer. 9 Nov 2026. The founder approved "uptime monitoring" that day. He has no account with any
-- monitoring service, so the check runs inside our own stack: pg_cron in the database calls the website over pg_net.
-- The database is on Supabase and the website on Vercel, so a Vercel outage does not stop the check.
--
-- THE GAP (read from the schema mirror, 9 Nov 2026): nothing called the public website on a short clock from outside
-- Vercel. The IT engineer's hourly `uptime` duty (fn_it_engineer_duties, section 7) judges sites that
-- resilience_ping reads, and resilience_ping runs on Vercel's own cron (/api/resilience-ping), so it stops when
-- Vercel stops. The GitHub cross-check that ran outside both is off with GitHub Actions since 26 Oct (ledger 1279).
-- fn_it_engineer_uptime_slo reads public.edge_health_probe 'uptime:%' rows that nothing writes.
--
-- MEASURED 9 Nov 2026 from this session (curl, no redirects followed):
--   https://quotesdone.com/api/health      404  (the route ships with PR #1874 at the same merge as this file)
--   https://www.quotesdone.com/api/health  308 -> https://quotesdone.com/api/health
--   https://quotesdone.com/                200
-- pg_net 0.20.3 on production does not follow redirects, so the check calls the APEX host: a check on www would
-- read 308 for ever. /api/health makes no database call (src/app/api/health/route.ts), so a slow database cannot
-- make the website look down, and it answers 200 only when the Next.js process on Vercel is serving.
--
-- WHAT THIS BUILDS
--   1. public.site_uptime_check: one row per check (checked_at, url, status_code, ms, ok, error), with the pg_net
--      request id it waits on. RLS on, a service-role-only policy, revoked from anon and authenticated. 14 days kept.
--   2. fn_site_uptime_verdict(recent ok values newest first, finding open?, need): the pure decision. 'open' when the
--      last `need` (3) COMPLETED checks all failed and no finding is open; 'keep' while it stays open; 'close' on the
--      first success; 'none' otherwise. Pure, so the probe proves the rule on arrays without calling the website.
--   3. fn_site_uptime_tick(), every 5 minutes at :02, :07, ... (off the :00/:05 marks the 82 seat-duty jobs fire on):
--        a. reads the answers pg_net recorded for EARLIER checks (pg_net is async: it sends after the commit, so a
--           check's answer is read on the next tick). Failed = anything but 200: a 404, a 5xx, a 308, a timeout
--           (10 s) or a connection error. A check with no answer after 15 minutes is marked lost and is NOT a
--           failure, because then it is pg_net that is broken, not the website;
--        b. decides with (2) and settles through the IT engineer's own finding path, fn_it_duty_settle('site_uptime',
--           ...): one finding, issue key duty:site_uptime:https://quotesdone.com/api/health, raised once and kept
--           (seen_count rises) while the website stays down, closed by the settle on the first success. Three lost
--           checks in a row are a separate, non-paging finding duty:site_uptime:monitor (the monitor is blind);
--        c. on 'open', pages the founder through fn_notify_founder with kind uptime_alert, the emergency kind
--           founder_mail_policy already allows (email and WhatsApp, the_founder_hears_from_it_once_a_day.sql), at
--           level critical, deduped per outage and held if a down page already went out in the last hour (a flapping
--           site is one page an hour, not one every fifteen minutes); on 'close', and only if he was paged about
--           that outage, one email (level info, no WhatsApp) that it is back;
--        d. sends the next check, and deletes checks older than 14 days, at most 1,000 rows a tick (288 rows a day).
--   4. The schedule site_uptime_5min, its cron_registry row, its writer_seat row, and the table's export-registry row.
--
-- TIMING. Three failed checks five minutes apart, read one tick later: the founder is paged 15 to 20 minutes into an
-- outage. The same rule gives the Vercel deploy of /api/health (PR #1874, same merge) about 15 minutes before its 404s
-- could page him. A 404 counts as a failure on purpose: a route that disappears is the website broken.
--
-- WHAT IT CANNOT SEE: a page that returns 200 with broken content (the nightly journey reads pages); a visitor sent
-- to quotesdone.ae (the hourly uptime duty reads that origin); the website from the UAE (pg_net runs where the
-- database runs). If the DATABASE is down, nothing here runs either; that is resilience_ping's platform_down page.
--
-- THE PROBE is read-only and tells nobody: it calls no website, opens no finding and sends nothing. It checks the
-- objects, the grants, the schedule and the registry rows, and runs the decision function on synthetic arrays.
--
-- Prevented by: scripts/checks/the_website_is_checked_from_outside_every_five_minutes.test.mjs.

-- ── 1. THE CHECKS ────────────────────────────────────────────────────────────────────────────────────────────────
create table if not exists public.site_uptime_check (
  id          bigint generated always as identity primary key,
  checked_at  timestamptz not null default clock_timestamp(),  -- when the request was queued
  url         text not null,
  request_id  bigint,                                          -- pg_net's net._http_response id to read next tick
  status_code integer,                                         -- null: no HTTP answer (timeout, error, lost, pending)
  ms          integer,                                         -- queued -> answer recorded, pg_net's queue wait included
  ok          boolean,                                         -- null while pending, and for a lost check
  error       text,                                            -- why it failed; 'lost: ...' when pg_net never answered
  answered_at timestamptz                                      -- when pg_net recorded the answer
);
create index if not exists site_uptime_check_url_checked_at on public.site_uptime_check (url, checked_at desc);
create index if not exists site_uptime_check_pending on public.site_uptime_check (request_id) where answered_at is null and error is null;

alter table public.site_uptime_check enable row level security;
drop policy if exists site_uptime_check_service_role_only on public.site_uptime_check;
create policy site_uptime_check_service_role_only on public.site_uptime_check
  as permissive for all to public using (false) with check (false);
revoke all on public.site_uptime_check from anon, authenticated;

comment on table public.site_uptime_check is
  'One row per external check of https://quotesdone.com/api/health by fn_site_uptime_tick (pg_cron + pg_net, every 5 minutes). 14 days kept. it_engineer, 9 Nov 2026.';

insert into public.table_export_registry (table_name, exported, category, reason, added_by) values
  ('site_uptime_check', false, 'measurement', 'one row per 5-minute check of the website by fn_site_uptime_tick, kept 14 days; an outage is recorded as an it_engineer_finding, which is exported', 'it_engineer')
on conflict (table_name) do update set exported = excluded.exported, category = excluded.category,
  reason = excluded.reason, added_by = excluded.added_by;

-- ── 2. THE DECISION: THREE COMPLETED FAILURES IN A ROW ───────────────────────────────────────────────────────────
-- p_recent: ok of the most recent COMPLETED checks, newest first (nulls are dropped: a pending or lost check is not
-- a completed one). p_open: whether the outage finding is open now. Returns open | keep | close | none.
create or replace function public.fn_site_uptime_verdict(p_recent boolean[], p_open boolean, p_need integer default 3)
returns text
language sql
immutable
security definer
set search_path to 'public', 'pg_temp'
as $fn$
  select case
    -- the newest completed check answered 200: the website is up
    when coalesce(cardinality(z.r), 0) > 0 and z.r[1] then case when coalesce(p_open, false) then 'close' else 'none' end
    -- the last p_need completed checks all failed: the website is down
    when coalesce(cardinality(z.r), 0) >= z.need and not (true = any (z.r[1:z.need])) then
      case when coalesce(p_open, false) then 'keep' else 'open' end
    -- fewer than p_need failures in a row, or nothing completed yet: an open outage stays open until a success
    else case when coalesce(p_open, false) then 'keep' else 'none' end
  end
  from (select array_remove(coalesce(p_recent, '{}'::boolean[]), null) as r, greatest(coalesce(p_need, 3), 1) as need) z;
$fn$;

revoke execute on function public.fn_site_uptime_verdict(boolean[], boolean, integer) from public, anon, authenticated;

comment on function public.fn_site_uptime_verdict(boolean[], boolean, integer) is
  'Pure decision of the website uptime check: open when the last p_need (3) completed checks all failed and no finding is open, keep while open, close on the first success, else none. it_engineer, 9 Nov 2026.';

-- ── 3. THE TICK ──────────────────────────────────────────────────────────────────────────────────────────────────
create or replace function public.fn_site_uptime_tick()
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  c_url     constant text := 'https://quotesdone.com/api/health';
  c_need    constant int  := 3;
  v_key     text := 'duty:site_uptime:' || c_url;
  v_harvested int; v_lost int; v_purged int; v_req bigint;
  v_recent  boolean[]; v_last jsonb; v_open boolean; v_started timestamptz; v_action text;
  v_blind   boolean; v_items jsonb := '[]'::jsonb; v_settle jsonb; v_page jsonb; v_epoch bigint;
begin
  -- a. THE ANSWERS TO EARLIER CHECKS. Only 200 is up. pg_net keeps answers six hours; this runs every five minutes.
  --    The created >= checked_at guard keeps a reused pg_net id (an extension reinstall restarts its sequence) from
  --    being read as this check's answer.
  update public.site_uptime_check c
     set status_code = h.status_code,
         ms = greatest(0, round(extract(epoch from (h.created - c.checked_at)) * 1000))::int,
         ok = coalesce(h.status_code = 200 and not coalesce(h.timed_out, false) and h.error_msg is null, false),
         error = case when h.status_code = 200 and not coalesce(h.timed_out, false) and h.error_msg is null then null
                      else left(coalesce(nullif(btrim(h.error_msg), ''),
                                         case when h.timed_out then 'timed out after 10 s' end,
                                         'HTTP ' || h.status_code,
                                         'no status and no error from pg_net'), 500) end,
         answered_at = h.created
    from net._http_response h
   where h.id = c.request_id and c.answered_at is null and c.error is null
     and h.created >= c.checked_at - interval '1 minute';
  get diagnostics v_harvested = row_count;

  -- No answer in 15 minutes: pg_net is what failed, not the website. Lost, and not a failure.
  update public.site_uptime_check
     set error = 'lost: pg_net recorded no answer within 15 minutes'
   where answered_at is null and error is null and checked_at < now() - interval '15 minutes';
  get diagnostics v_lost = row_count;

  -- b. THE DECISION, over the last three COMPLETED checks of this url.
  select array_agg(z.ok order by z.checked_at desc),
         jsonb_agg(jsonb_build_object('checked_at', z.checked_at, 'status_code', z.status_code, 'ms', z.ms, 'error', z.error)
                   order by z.checked_at desc)
    into v_recent, v_last
    from (select ok, checked_at, status_code, ms, error from public.site_uptime_check
           where url = c_url and answered_at is not null order by checked_at desc limit c_need) z;

  select started_at into v_started from public.it_engineer_finding where issue_key = v_key and closed_at is null;
  v_open := found;
  v_action := public.fn_site_uptime_verdict(v_recent, v_open, c_need);
  -- ARMED ONLY AFTER THE FIRST 200 (9 Nov 2026). /api/health ships in the same merge as this file, and the SQL can
  -- apply before Vercel finishes deploying the page: its 404s must not page the founder about an outage that is
  -- only a deploy in progress. Until some check has ever answered 200 for this url, nothing opens.
  if v_action = 'open' and not exists (select 1 from public.site_uptime_check where url = c_url and ok) then
    v_action := 'none';
  end if;

  if v_action in ('open', 'keep') then
    v_items := v_items || jsonb_build_object('item', c_url, 'owner_seat', 'it_engineer', 'subject', 'website',
      'title', 'The website is down: ' || c_url || ' failed its last ' || c_need || ' checks from outside Vercel ('
               || coalesce(v_last->0->>'error', 'no answer') || ')',
      'blast', 'customer_facing', 'affected', 1,
      'evidence', jsonb_build_object('url', c_url, 'last_checks', coalesce(v_last, '[]'::jsonb), 'rule', c_need || ' completed checks in a row not answering 200',
                                     'checked_by', 'fn_site_uptime_tick (pg_cron site_uptime_5min, pg_net)', 'table', 'public.site_uptime_check'));
  end if;

  -- The monitor watches itself: the last three finished checks were all lost. Not paged (the website may be fine).
  -- coalesce, because bool_and skips nulls and an answered check's error is null (rehearsal, 9 Nov: one lost check
  -- and two answered ones read as blind without it).
  select count(*) = c_need and bool_and(coalesce(error like 'lost:%', false)) into v_blind
    from (select error from public.site_uptime_check
           where url = c_url and (answered_at is not null or error is not null) order by checked_at desc limit c_need) z;
  if coalesce(v_blind, false) then
    v_items := v_items || jsonb_build_object('item', 'monitor', 'owner_seat', 'it_engineer', 'subject', 'site_uptime',
      'title', 'The website uptime check is blind: pg_net recorded no answer to its last ' || c_need || ' requests',
      'blast', 'monitor', 'affected', 0,
      'evidence', jsonb_build_object('url', c_url, 'look_at', 'net._http_response and the pg_net background worker'));
  end if;

  -- One finding per condition, raised once and kept while it lasts; the settle closes whatever is no longer listed.
  v_settle := public.fn_it_duty_settle('site_uptime', v_items);

  -- c. THE FOUNDER: paged once per outage, told once when it ends if he was paged about it.
  --    The page block runs on 'open' AND 'keep' (review of #1874, 9 Nov 2026): a site that comes back for one check and
  --    falls again within the hour reopens the same finding with a new started_at, the hour's hold stops the page at
  --    'open', and every later tick is 'keep'. Running only on 'open' left that second outage unpaged however long it
  --    lasted. Now each tick of an open outage asks: was he already paged for THIS outage (its started_at)? If not, page
  --    as soon as the hour's hold allows. The not-exists keeps fn_notify_founder from writing a 'deduped' row every tick.
  if v_action in ('open', 'keep') then
    select floor(extract(epoch from started_at))::bigint into v_epoch from public.it_engineer_finding where issue_key = v_key;
    if exists (select 1 from public.founder_alerts f
                where f.dedupe_key = 'site_uptime_down:' || v_epoch and f.channel = 'email') then
      v_page := jsonb_build_object('paged', false, 'why', 'already paged for this outage');
    elsif exists (select 1 from public.founder_alerts f
                where f.dedupe_key like 'site_uptime_down:%' and f.channel in ('email', 'whatsapp')
                  and f.created_at > now() - interval '1 hour') then
      v_page := jsonb_build_object('paged', false, 'why', 'a website-down page already went out in the last hour; this outage pages when the hour has passed');
    else
      v_page := public.fn_notify_founder(
        p_event => 'THE WEBSITE IS DOWN: quotesdone.com is not answering',
        p_detail => 'quotesdone.com has failed ' || c_need || ' checks in a row, five minutes apart, from outside Vercel. '
          || 'Last answer: ' || coalesce(v_last->0->>'error', 'none') || '. Customers and suppliers cannot open the website. '
          || 'The IT engineer has opened the finding ' || v_key || ' and will tell you when it is back.',
        p_level => 'critical', p_kind => 'uptime_alert', p_dedupe_key => 'site_uptime_down:' || v_epoch, p_owner_agent => 'it_engineer');
    end if;
  elsif v_action = 'close' then
    v_epoch := floor(extract(epoch from v_started))::bigint;
    if exists (select 1 from public.founder_alerts f
                where f.dedupe_key = 'site_uptime_down:' || v_epoch and f.channel = 'email') then
      v_page := public.fn_notify_founder(
        p_event => 'The website is back up',
        p_detail => 'quotesdone.com answered normally again at ' || to_char(now() at time zone 'Asia/Dubai', 'HH24:MI DD Mon') || ' Dubai, after '
          || greatest(1, round(extract(epoch from (now() - v_started)) / 60)) || ' minutes. Nothing is needed from you.',
        p_level => 'info', p_kind => 'uptime_alert', p_dedupe_key => 'site_uptime_up:' || v_epoch, p_owner_agent => 'it_engineer');
    else
      v_page := jsonb_build_object('paged', false, 'why', 'he was not paged about this outage, so its end is not news');
    end if;
  end if;

  -- d. THE NEXT CHECK, and the retention.
  v_req := net.http_get(url := c_url,
                        headers := jsonb_build_object('User-Agent', 'QuotesDone uptime check (pg_net)', 'Cache-Control', 'no-cache'),
                        timeout_milliseconds := 10000);
  insert into public.site_uptime_check (url, request_id) values (c_url, v_req);

  delete from public.site_uptime_check
   where id in (select id from public.site_uptime_check where checked_at < now() - interval '14 days' order by id limit 1000);
  get diagnostics v_purged = row_count;

  return jsonb_build_object('url', c_url, 'harvested', v_harvested, 'lost', v_lost, 'recent', to_jsonb(v_recent),
                            'action', v_action, 'blind', coalesce(v_blind, false), 'settle', v_settle, 'page', v_page,
                            'requested', v_req, 'purged', v_purged);
end
$fn$;

revoke execute on function public.fn_site_uptime_tick() from public, anon, authenticated;

comment on function public.fn_site_uptime_tick() is
  'Every 5 minutes (site_uptime_5min): reads pg_net answers to earlier checks of https://quotesdone.com/api/health, opens/keeps/closes the finding duty:site_uptime:<url> through fn_it_duty_settle (3 completed failures in a row), pages the founder with kind uptime_alert on open, sends the next check, keeps 14 days. it_engineer, 9 Nov 2026.';

-- ── 4. THE SCHEDULE AND ITS REGISTRY ROWS ────────────────────────────────────────────────────────────────────────
select cron.schedule('site_uptime_5min', '2-59/5 * * * *', $CRON$set statement_timeout = '30s'; select public.fn_site_uptime_tick();$CRON$);

insert into public.cron_registry (jobname, human_name, category, purpose) values
  ('site_uptime_5min', 'Website uptime check', 'Health & monitoring',
   'fn_site_uptime_tick() every 5 minutes at :02, :07, ...: calls https://quotesdone.com/api/health from the database '
   || '(pg_net, outside Vercel), records it in site_uptime_check, and after 3 failed checks in a row opens the IT '
   || 'engineer''s finding and pages the founder (kind uptime_alert). Founder approved uptime monitoring 9 Nov 2026.')
on conflict (jobname) do update set human_name = excluded.human_name, category = excluded.category, purpose = excluded.purpose;

insert into public.writer_seat (kind, name, owner_seat, note, owner_file) values
  ('cron_job', 'site_uptime_5min', 'it_engineer',
   'fn_site_uptime_tick() every 5 min at :02: the external website uptime check; pages the founder (uptime_alert) after 3 failures in a row.',
   'scripts/sql/the_website_is_checked_from_outside_every_five_minutes.sql')
on conflict (kind, name) do update set owner_seat = excluded.owner_seat, note = excluded.note, owner_file = excluded.owner_file;

-- PROBE: read-only; returns its verdict as a row (the file holds DDL, so it must not raise). It calls no website,
-- opens no finding and sends nothing: the decision is proved on synthetic arrays.
with t as (select c.relrowsecurity rls from pg_class c join pg_namespace n on n.oid = c.relnamespace
            where n.nspname = 'public' and c.relname = 'site_uptime_check'),
     pol as (select count(*) n from pg_policies where schemaname = 'public' and tablename = 'site_uptime_check'
              and policyname = 'site_uptime_check_service_role_only'),
     tgrant as (select has_table_privilege('anon', 'public.site_uptime_check', 'select')
                    or has_table_privilege('authenticated', 'public.site_uptime_check', 'select') open_to_browser),
     f as (select count(*) n from pg_proc p join pg_namespace s on s.oid = p.pronamespace
            where s.nspname = 'public' and p.proname in ('fn_site_uptime_tick', 'fn_site_uptime_verdict') and p.prosecdef
              and exists (select 1 from unnest(p.proconfig) cfg where cfg like 'search_path=%')),
     ex as (select count(*) n from pg_proc p join pg_namespace s on s.oid = p.pronamespace
             where s.nspname = 'public' and p.proname in ('fn_site_uptime_tick', 'fn_site_uptime_verdict')
               and (has_function_privilege('anon', p.oid, 'execute') or has_function_privilege('authenticated', p.oid, 'execute'))),
     j as (select count(*) n from cron.job where jobname = 'site_uptime_5min' and active and schedule = '2-59/5 * * * *'
            and command like '%public.fn_site_uptime_tick()%'),
     reg as (select (select count(*) from public.cron_registry where jobname = 'site_uptime_5min')
                  + (select count(*) from public.writer_seat where kind = 'cron_job' and name = 'site_uptime_5min' and owner_seat = 'it_engineer')
                  + (select count(*) from public.table_export_registry where table_name = 'site_uptime_check') n),
     pol_kind as (select coalesce((select allowed_to_email from public.founder_mail_policy where kind = 'uptime_alert'), false) allowed),
     cases(recent, is_open, expect) as (values
       (array[false, false, false], false, 'open'),
       (array[false, false, false, false], false, 'open'),
       (array[false, false, false], true,  'keep'),
       (array[false, false], false, 'none'),
       (array[false, false, true], false, 'none'),
       (array[false, true, false, false], false, 'none'),
       (array[false], true, 'keep'),
       (array[true, false, false], true, 'close'),
       (array[true], false, 'none'),
       ('{}'::boolean[], false, 'none'),
       (array[null, false, false, false]::boolean[], false, 'open')),
     bad as (select string_agg(coalesce(array_to_string(recent, ',', 'null'), '{}') || '/' || is_open || ' gave '
                               || coalesce(public.fn_site_uptime_verdict(recent, is_open, 3), 'null') || ' not ' || expect, '; ') why
               from cases where public.fn_site_uptime_verdict(recent, is_open, 3) is distinct from expect)
select case
  when (select count(*) from t) <> 1 then 'PROBE FAILED: public.site_uptime_check does not exist'
  when not (select rls from t) then 'PROBE FAILED: site_uptime_check has row security off'
  when (select n from pol) <> 1 then 'PROBE FAILED: site_uptime_check has no service-role-only policy'
  when (select open_to_browser from tgrant) then 'PROBE FAILED: anon or authenticated can read site_uptime_check'
  when (select n from f) <> 2 then 'PROBE FAILED: fn_site_uptime_tick / fn_site_uptime_verdict missing, not security definer, or no pinned search_path'
  when (select n from ex) <> 0 then 'PROBE FAILED: anon or authenticated can execute a site uptime routine'
  when (select n from j) <> 1 then 'PROBE FAILED: site_uptime_5min is not scheduled and active at 2-59/5'
  when (select n from reg) <> 3 then 'PROBE FAILED: site_uptime_5min lacks its cron_registry or writer_seat row, or the table its export-registry row'
  when not (select allowed from pol_kind) then 'PROBE FAILED: founder_mail_policy does not allow kind uptime_alert, so the page would be routed'
  when (select why from bad) is not null then 'PROBE FAILED: the 3-in-a-row rule is wrong: ' || (select why from bad)
  else 'PROBE OK: site_uptime_check (RLS, service-role only), fn_site_uptime_tick and fn_site_uptime_verdict (definer, revoked), '
       || 'site_uptime_5min at 2-59/5, registry rows present, uptime_alert allowed, 11 of 11 decision cases right'
end as verdict;
