-- THE MARKETING SEAT MEASURES SEARCH, REGISTRATIONS AND COST PER SUPPLIER EVERY DAY.
-- Seat: marketing (agent: marketing seat builder). 15 Nov 2026. Founder rulings 1701 (profitability; enough registered
-- suppliers first), 1705 (KPIs that drive action), 1709 (his own network through the tracked link utm_source=founder).
--
-- MEASURED BEFORE THIS FILE (SELECT, 15 Nov 2026)
--   * marketing_first_touch: 0 rows. Two real suppliers are registered: one self-registered with no tag and no opened
--     invitation (the routine correctly records nothing), and one who OPENED his invitation (leads.invite_clicked_at set)
--     and registered on 11 Nov, for whom fn_marketing_first_touch_record would have recorded source 'invite' - but
--     supplier_api/lib/registration.ts returned before calling it whenever the browser kept no tags. Fixed in that file
--     (first_touch_payload.ts); this file does not backfill (that supplier's rows are not touched by this session).
--   * No Search Console data anywhere (no code, table or credential); Vercel Web Analytics answers 404 "not found".
--   * fn_marketing_kpi_scorecard returns cost_per_registered_supplier_aed null; posts and articles are counted, their
--     traffic is not.
--
-- WHAT THIS FILE ADDS
--   1. public.marketing_search_day (one row per Dubai day x total/query/page: clicks, impressions, ctr, average position)
--      and public.marketing_search_sitemap (submitted and indexed URLs per sitemap), written by the marketing duty
--      search_console (supabase/functions/marketing/duties/search_console.ts) from the Google Search Console API with the
--      read-only scope. Inert until app_secrets google_search_console_sa (a service-account key added as a user of the
--      property) and google_search_console_site are set; it then says so instead of failing.
--   2. fn_marketing_measurement_kpis(day): registrations by first-touch source (submitted and approved, 30 days), cost per
--      registered supplier (all-in: 6200 Marketing & Advertising, reported ad spend not yet booked, and the marketing
--      seat's model spend), posts and articles published and their traffic (post views and reach from
--      marketing_post_metric, organic clicks to /blog pages from marketing_search_day), and rankings (clicks,
--      impressions, average position, queries in the top 10, pages with impressions, indexed URLs).
--   3. fn_marketing_measurement_tick() (duty marketing.measurement_kpis, daily): writes the day into the seat's own record
--      (marketing_duty_record, duty 'marketing.measurement_kpis') and returns it; fn_marketing_measurement_reading() is
--      what the CEO's planning pack reads.

create table if not exists public.marketing_search_day (
  day date not null,
  dim text not null check (dim in ('total', 'query', 'page')),
  key text not null default '',
  clicks integer not null default 0 check (clicks >= 0),
  impressions integer not null default 0 check (impressions >= 0),
  ctr numeric,
  position numeric,
  fetched_at timestamptz not null default now(),
  primary key (day, dim, key),
  check ((dim = 'total') = (key = ''))
);
comment on table public.marketing_search_day is
  'Google Search Console search analytics per day: the site total, each query and each page (marketing duty search_console).';
alter table public.marketing_search_day enable row level security;
drop policy if exists marketing_search_day_service_role_only on public.marketing_search_day;
create policy marketing_search_day_service_role_only on public.marketing_search_day as permissive for all to public using (false) with check (false);
revoke all on public.marketing_search_day from anon, authenticated;

create table if not exists public.marketing_search_sitemap (
  path text primary key,
  submitted integer,
  indexed integer,
  last_downloaded timestamptz,
  errors integer,
  warnings integer,
  fetched_at timestamptz not null default now()
);
comment on table public.marketing_search_sitemap is 'Google Search Console sitemaps: URLs submitted and indexed per sitemap (marketing duty search_console).';
alter table public.marketing_search_sitemap enable row level security;
drop policy if exists marketing_search_sitemap_service_role_only on public.marketing_search_sitemap;
create policy marketing_search_sitemap_service_role_only on public.marketing_search_sitemap as permissive for all to public using (false) with check (false);
revoke all on public.marketing_search_sitemap from anon, authenticated;

create or replace function public.fn_marketing_measurement_kpis(p_day date default null)
returns jsonb language plpgsql stable security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  v_d date := coalesce(p_day, (now() at time zone 'Asia/Dubai')::date);
  v_from date := v_d - 29; v_fx numeric; v_reg jsonb; v_sub int; v_app int; v_cost6200 numeric; v_ads numeric; v_model numeric;
  v_cost numeric; v_posts jsonb; v_articles jsonb; v_search jsonb; v_last_search date; v_missing text[] := '{}';
begin
  select num_value into v_fx from public.gl_settings where key = 'usd_to_aed'; v_fx := coalesce(v_fx, 3.6725);

  -- REGISTRATIONS BY SOURCE (30 days to v_d): submitted and approved, demo identities excluded.
  with reg as (
    select l.id, l.registration_submitted_at, l.approved_at,
           case when ft.utm_source = 'invite' then 'email_invitation' when ft.utm_source is not null then ft.utm_source else 'untagged' end src
      from public.leads l left join public.marketing_first_touch ft on ft.lead_id = l.id
     where l.claimed_by is not null and not coalesce(l.is_demo, false) and l.company_name !~* '^zz[ _-]?demo'
       and ((l.registration_submitted_at at time zone 'Asia/Dubai')::date between v_from and v_d
            or (l.approved_at at time zone 'Asia/Dubai')::date between v_from and v_d))
  select coalesce(jsonb_object_agg(src, jsonb_build_object('submitted', sb, 'approved', ap)), '{}'::jsonb), coalesce(sum(sb), 0), coalesce(sum(ap), 0)
    into v_reg, v_sub, v_app
    from (select src, count(*) filter (where (registration_submitted_at at time zone 'Asia/Dubai')::date between v_from and v_d) sb,
                      count(*) filter (where (approved_at at time zone 'Asia/Dubai')::date between v_from and v_d) ap
            from reg group by src) z;

  -- COST PER REGISTERED SUPPLIER, all-in, 30 days: booked marketing (6200), reported ad spend, the seat's model spend
  select coalesce(sum(l.debit - l.credit), 0) into v_cost6200 from public.gl_journal j join public.gl_journal_lines l on l.journal_id = j.id
   where j.status = 'posted' and l.account_code = '6200' and j.entry_date between v_from and v_d;
  select coalesce(sum(coalesce(amount_aed, case when upper(currency) = 'USD' then amount * v_fx when upper(currency) = 'AED' then amount end)), 0) into v_ads
    from public.ad_spend_reported where spend_date between v_from and v_d;
  select coalesce(sum(cost_aed), 0) into v_model from public.ai_cost_log
   where (fn like 'marketing%' or seat = 'marketing') and e2e_run_tag is null
     and (occurred_at at time zone 'Asia/Dubai')::date between v_from and v_d;
  v_cost := round(greatest(v_cost6200, v_ads) + v_model, 2);   -- ad spend is booked to 6200 once invoiced: the larger, never both
  if v_app = 0 then v_missing := v_missing || text 'no supplier approved in the 30 days, so the cost per registered supplier is undefined'; end if;

  -- POSTS AND ARTICLES PUBLISHED, AND THEIR TRAFFIC
  select jsonb_build_object(
           'published_30d', count(*) filter (where (p.published_at at time zone 'Asia/Dubai')::date between v_from and v_d),
           'last_published', max(p.published_at),
           'views_30d_posts', coalesce((select sum(x.value) from (
                                 select distinct on (m.post_id, m.metric) m.value from public.marketing_post_metric m
                                   join public.marketing_post p2 on p2.id = m.post_id
                                  where m.metric in ('views', 'video_views', 'impressions', 'plays') and m.value is not null and not p2.is_demo
                                    and (p2.published_at at time zone 'Asia/Dubai')::date between v_from and v_d
                                  order by m.post_id, m.metric, m.captured_at desc) x), 0),
           'link_clicks', 'not measured by the platforms'' APIs; registrations with utm_source per platform are the click outcome (above)')
    into v_posts from public.marketing_post p where p.status = 'published' and not p.is_demo;
  select jsonb_build_object(
           'live_30d', count(*) filter (where (a.live_at at time zone 'Asia/Dubai')::date between v_from and v_d),
           'live_total', count(*) filter (where a.status = 'live'),
           'waiting_release', count(*) filter (where a.status in ('approved', 'released')),
           'blog_organic_clicks_30d', (select coalesce(sum(s.clicks), 0) from public.marketing_search_day s where s.dim = 'page' and s.key ~ '/blog(/|$)' and s.day between v_from and v_d),
           'blog_impressions_30d', (select coalesce(sum(s.impressions), 0) from public.marketing_search_day s where s.dim = 'page' and s.key ~ '/blog(/|$)' and s.day between v_from and v_d))
    into v_articles from public.marketing_article a where not a.is_demo;

  -- RANKINGS (Search Console; data lags about two days)
  select max(day) into v_last_search from public.marketing_search_day where dim = 'total';
  if v_last_search is null then
    v_missing := v_missing || text 'no Search Console data: app_secrets google_search_console_sa and google_search_console_site are not set (marketing duty search_console)';
    v_search := jsonb_build_object('unavailable', 'no Search Console data yet');
  else
    select jsonb_build_object(
             'last_day', v_last_search,
             'clicks_30d', (select coalesce(sum(clicks), 0) from public.marketing_search_day where dim = 'total' and day between v_from and v_d),
             'impressions_30d', (select coalesce(sum(impressions), 0) from public.marketing_search_day where dim = 'total' and day between v_from and v_d),
             'avg_position_30d', (select round(sum(position * impressions) / nullif(sum(impressions), 0), 1) from public.marketing_search_day
                                   where dim = 'total' and day between v_from and v_d),
             'queries_in_top_10_last_7d', (select count(*) from (select key from public.marketing_search_day where dim = 'query' and day between v_d - 6 and v_d
                                                                  group by key having sum(position * impressions) / nullif(sum(impressions), 0) <= 10) q),
             'pages_with_impressions_30d', (select count(distinct key) from public.marketing_search_day where dim = 'page' and impressions > 0 and day between v_from and v_d),
             'indexed_urls', (select sum(indexed) from public.marketing_search_sitemap),
             'submitted_urls', (select sum(submitted) from public.marketing_search_sitemap),
             'top_queries_7d', (select coalesce(jsonb_agg(jsonb_build_object('query', key, 'clicks', c, 'impressions', i, 'position', p) order by i desc), '[]'::jsonb)
                                  from (select key, sum(clicks) c, sum(impressions) i, round(sum(position * impressions) / nullif(sum(impressions), 0), 1) p
                                          from public.marketing_search_day where dim = 'query' and day between v_d - 6 and v_d
                                         group by key order by sum(impressions) desc limit 10) t))
      into v_search;
  end if;

  return jsonb_build_object(
    'day', v_d, 'window', jsonb_build_object('from', v_from, 'to', v_d),
    'registrations_by_source', v_reg, 'registrations_submitted_30d', v_sub, 'suppliers_approved_30d', v_app,
    'cost_per_registered_supplier', jsonb_build_object(
      'aed', case when v_app > 0 then round(v_cost / v_app, 2) end, 'cost_aed', v_cost, 'approved', v_app,
      'marketing_6200_aed', round(v_cost6200, 2), 'ad_spend_reported_aed', round(v_ads, 2), 'marketing_model_aed', round(v_model, 2),
      'basis', 'all-in marketing cost of the 30 days / suppliers approved in them; reported ad spend and the booked 6200 are one cost (the larger is taken)'),
    'posts', v_posts, 'articles', v_articles, 'search', v_search,
    'web_analytics', 'Vercel Web Analytics is off for the project (404); docs/runbooks/vercel_web_analytics.md switches it on',
    'missing', to_jsonb(v_missing));
end $fn$;
revoke execute on function public.fn_marketing_measurement_kpis(date) from public, anon, authenticated;

create or replace function public.fn_marketing_measurement_tick()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_d date := (now() at time zone 'Asia/Dubai')::date; b jsonb;
begin
  b := public.fn_marketing_measurement_kpis(v_d);
  insert into public.marketing_duty_record (duty, period, body) values ('marketing.measurement_kpis', v_d, b)
  on conflict (duty, period) do update set body = excluded.body, written_at = now();
  return b;
end $fn$;
revoke execute on function public.fn_marketing_measurement_tick() from public, anon, authenticated;

create or replace function public.fn_marketing_measurement_reading()
returns jsonb language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  select coalesce((select r.body || jsonb_build_object('written_at', r.written_at, 'seat', 'marketing')
                     from public.marketing_duty_record r where r.duty = 'marketing.measurement_kpis' order by r.period desc limit 1),
                  jsonb_build_object('unavailable', 'fn_marketing_measurement_tick has not run yet', 'seat', 'marketing'));
$fn$;
revoke execute on function public.fn_marketing_measurement_reading() from public, anon, authenticated;

insert into public.seat_duty (duty, owner_seat, every, routine, what, owner_file) values
  ('marketing.measurement_kpis', 'marketing', interval '1 day', 'fn_marketing_measurement_tick',
   'Registrations by first-touch source, cost per registered supplier, posts and articles published and their traffic, and search rankings, for the last 30 days; written to marketing_duty_record and read by the CEO''s planning pack (fn_marketing_measurement_reading).',
   'scripts/sql/the_marketing_seat_measures_search_registrations_and_cost_per_supplier_every_day.sql')
on conflict (duty) do update set owner_seat = excluded.owner_seat, every = excluded.every, routine = excluded.routine,
  what = excluded.what, owner_file = excluded.owner_file;
