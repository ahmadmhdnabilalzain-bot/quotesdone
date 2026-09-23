-- EACH POST IS MEASURED AND NAMES THE SUPPLIERS IT BROUGHT (marketing; the registration side with sales_engineer).
-- 23 Sep 2026. Founder instruction 865: the marketing seat must "monitor the analytics that's coming out of
-- these [posts]... tell me if we did a good job with these or not", then plan month 2 from the results.
--
-- MEASURED BEFORE THIS FILE (22-23 Sep 2026): marketing_insight_day held 29 rows of page/account numbers and
-- post counters under the PLATFORM's post id, which never matched ours; no per-video result; no UTM in src/
-- or any function; a supplier registration (leads, source 'self_registered') could not name what brought it;
-- the CEO report had counts only; supabase/functions/marketing/duties.ts DUTIES was empty.
--
-- WHAT THIS FILE ADDS (all service-role only; the marketing seat's duty reads and writes them):
--   marketing_post_platform  the tie: our post x platform -> Postiz's post id and the platform's media id.
--                            Keyed (post_id, platform), so it joins marketing_post and any per-platform
--                            variant of a post by the same pair.
--   marketing_post_metric    one value per post, platform, checkpoint (+1d/+3d/+7d/+28d) and metric, or the
--                            reason the platform would not give it. Never an invented number.
--   marketing_first_touch    the first visit's UTM, written ONCE at registration from what the browser kept
--                            (qd-first-touch, localStorage). No identifier, no IP, no user agent: nothing
--                            leaves the browser unless the visitor registers.
--   marketing_goal           month x platform x metric targets, each with its published source.
--   marketing_scorecard_report  the weekly and month-end scorecards the duty stored.
--   fn_marketing_post_checkpoints_due / fn_marketing_first_touch_record / fn_marketing_scorecard /
--   fn_marketing_scorecard_publish.
-- Prevented by: supabase/functions/_shared/marketing_post_results.test.ts,
--   scripts/checks/each_post_is_measured_and_names_the_suppliers_it_brought.test.mjs,
--   scripts/sql/each_post_is_measured_and_names_the_suppliers_it_brought_probe.sql (read after the apply).

-- ── 1. THE TIE: OUR POST ON A PLATFORM ───────────────────────────────────────────────────────────────
create table if not exists public.marketing_post_platform (
  post_id          bigint not null references public.marketing_post(id) on delete cascade,
  platform         text not null check (platform in ('facebook', 'instagram', 'linkedin', 'x')),
  postiz_post_id   text,
  platform_post_id text,
  permalink        text,
  tied_at          timestamptz not null default now(),
  primary key (post_id, platform),
  constraint marketing_post_platform_has_an_id check (postiz_post_id is not null or platform_post_id is not null)
);
comment on table public.marketing_post_platform is
  'Our post on one platform: Postiz''s post id and the platform''s own media id (Postiz releaseId, or for Instagram the media whose permalink is Postiz''s releaseURL). Written by the marketing seat''s post_results duty. Join key for results: (post_id, platform).';
alter table public.marketing_post_platform enable row level security;
drop policy if exists marketing_post_platform_service_role_only on public.marketing_post_platform;
create policy marketing_post_platform_service_role_only on public.marketing_post_platform as permissive for all to public using (false) with check (false);
revoke all on public.marketing_post_platform from anon, authenticated;

-- ── 2. RESULTS AT FOUR CHECKPOINTS ───────────────────────────────────────────────────────────────────
create table if not exists public.marketing_post_metric (
  id                 bigint generated always as identity primary key,
  post_id            bigint not null references public.marketing_post(id) on delete cascade,
  platform           text not null check (platform in ('facebook', 'instagram', 'linkedin', 'x')),
  platform_post_id   text,
  checkpoint         text not null check (checkpoint in ('1d', '3d', '7d', '28d')),
  metric             text not null check (metric ~ '^[a-z0-9_*]+$'),
  value              numeric,
  unavailable_reason text,
  captured_at        timestamptz not null default now(),
  unique (post_id, platform, checkpoint, metric),
  -- a value, or the platform's reason for not giving one; never both, never neither
  constraint marketing_post_metric_value_or_reason check ((value is null) <> (unavailable_reason is null))
);
comment on table public.marketing_post_metric is
  'Per-post results read at +1d/+3d/+7d/+28d after publishing (lifetime values at that moment). A metric the platform refused is a row with unavailable_reason, so a checkpoint is read once. Source: marketing seat duty post_results (supabase/functions/_shared/marketing_post_results.ts).';
create index if not exists marketing_post_metric_post on public.marketing_post_metric (post_id, platform);
alter table public.marketing_post_metric enable row level security;
drop policy if exists marketing_post_metric_service_role_only on public.marketing_post_metric;
create policy marketing_post_metric_service_role_only on public.marketing_post_metric as permissive for all to public using (false) with check (false);
revoke all on public.marketing_post_metric from anon, authenticated;

-- ── 3. FIRST TOUCH: WHICH POST BROUGHT A REGISTRATION ────────────────────────────────────────────────
create table if not exists public.marketing_first_touch (
  id            bigint generated always as identity primary key,
  lead_id       bigint not null unique references public.leads(id) on delete cascade,
  utm_source    text not null check (utm_source ~ '^[A-Za-z0-9._-]{1,100}$'),
  utm_medium    text check (utm_medium ~ '^[A-Za-z0-9._-]{1,100}$'),
  utm_campaign  text check (utm_campaign ~ '^[A-Za-z0-9._-]{1,100}$'),
  utm_content   text check (utm_content ~ '^[A-Za-z0-9._-]{1,100}$'),
  landing_path  text check (landing_path ~ '^/\S{0,200}$'),
  first_seen_at timestamptz,
  post_id       bigint references public.marketing_post(id) on delete set null,
  recorded_at   timestamptz not null default now()
);
comment on table public.marketing_first_touch is
  'The first visit''s UTM for a registration (leads row), kept in the visitor''s browser (localStorage qd-first-touch) and sent only with the registration. post_id is the marketing_post whose ingest_key is utm_content. No personal data beyond the registration itself.';
create index if not exists marketing_first_touch_post on public.marketing_first_touch (post_id) where post_id is not null;
alter table public.marketing_first_touch enable row level security;
drop policy if exists marketing_first_touch_service_role_only on public.marketing_first_touch;
create policy marketing_first_touch_service_role_only on public.marketing_first_touch as permissive for all to public using (false) with check (false);
revoke all on public.marketing_first_touch from anon, authenticated;

-- ── 4. GOALS, EACH WITH ITS SOURCE ───────────────────────────────────────────────────────────────────
create table if not exists public.marketing_goal (
  month            text not null check (month ~ '^\d{4}-(0[1-9]|1[0-2])$'),
  platform         text not null check (platform in ('facebook', 'instagram', 'linkedin', 'x')),
  metric           text not null check (metric ~ '^[a-z0-9_]+$'),
  target           numeric not null check (target >= 0),
  benchmark_source text not null check (length(btrim(benchmark_source)) >= 20),
  created_at       timestamptz not null default now(),
  primary key (month, platform, metric)
);
comment on table public.marketing_goal is
  'Month targets per platform and metric. Every row cites the published benchmark it came from; a platform with no sourced benchmark has no row and is scored against the account''s own median only.';
alter table public.marketing_goal enable row level security;
drop policy if exists marketing_goal_service_role_only on public.marketing_goal;
create policy marketing_goal_service_role_only on public.marketing_goal as permissive for all to public using (false) with check (false);
revoke all on public.marketing_goal from anon, authenticated;

-- Month 1 (Sep 2026). ONE benchmark could be sourced; the others are unknown and are NOT invented:
--   facebook / linkedin / x: no all-industry or UAE B2B median per post was found in a primary source
--   (Rival IQ's 2025 page states Instagram's median only; its X/Facebook figures are in charts, unquoted).
insert into public.marketing_goal (month, platform, metric, target, benchmark_source) values
  ('2026-09', 'instagram', 'engagement_rate_by_followers', 0.0036,
   'Rival IQ, 2025 Social Media Industry Benchmark Report: "the overall median engagement rate on Instagram is 0.36%" (all industries; interactions per post / followers). https://www.rivaliq.com/blog/good-engagement-rate-instagram/')
on conflict (month, platform, metric) do nothing;

-- ── 5. STORED SCORECARDS ─────────────────────────────────────────────────────────────────────────────
create table if not exists public.marketing_scorecard_report (
  period_key text primary key check (period_key ~ '^\d{4}-(W\d{2}|\d{2}-end)$'),
  month      text not null check (month ~ '^\d{4}-(0[1-9]|1[0-2])$'),
  kind       text not null check (kind in ('weekly', 'month_end')),
  rows       int not null,
  result     jsonb not null,
  owner_seat text not null default 'marketing' check (owner_seat = 'marketing'),
  created_at timestamptz not null default now()
);
comment on table public.marketing_scorecard_report is
  'The marketing seat''s scorecards: weekly (the month so far, every Monday Asia/Dubai) and month-end (the whole previous month, on the 1st). One row per period; result is fn_marketing_scorecard''s table.';
alter table public.marketing_scorecard_report enable row level security;
drop policy if exists marketing_scorecard_report_service_role_only on public.marketing_scorecard_report;
create policy marketing_scorecard_report_service_role_only on public.marketing_scorecard_report as permissive for all to public using (false) with check (false);
revoke all on public.marketing_scorecard_report from anon, authenticated;

-- ── 6. ROUTINES ──────────────────────────────────────────────────────────────────────────────────────

-- Which (post, platform, checkpoint) reads are due. A checkpoint is read once (any row, value or reason,
-- closes it) and only inside its own window: a +1d read taken on day 20 would be a 20-day number
-- labelled 1d, so a missed checkpoint stays missing rather than mislabelled.
create or replace function public.fn_marketing_post_checkpoints_due(p_limit int default 25)
returns table (post_id bigint, platform text, platform_post_id text, postiz_post_id text, checkpoint text, published_at timestamptz)
language sql stable security definer
set search_path to 'public', 'pg_temp'
as $fn$
  select pp.post_id, pp.platform, pp.platform_post_id, pp.postiz_post_id, c.checkpoint, p.published_at
    from public.marketing_post_platform pp
    join public.marketing_post p on p.id = pp.post_id
   cross join (values ('1d', 1), ('3d', 3), ('7d', 7), ('28d', 28)) c(checkpoint, days)
   where p.status = 'published' and not p.is_demo
     and now() >= p.published_at + make_interval(days => c.days)
     and now() <  p.published_at + make_interval(days => c.days * 2 + 1)
     and not exists (select 1 from public.marketing_post_metric m
                      where m.post_id = pp.post_id and m.platform = pp.platform and m.checkpoint = c.checkpoint)
   order by p.published_at, c.days
   limit greatest(1, least(coalesce(p_limit, 25), 100))
$fn$;
revoke execute on function public.fn_marketing_post_checkpoints_due(int) from public, anon, authenticated;

-- The registration side (sales_engineer: supplier_api create_company calls it right after the leads insert).
-- Takes only what the browser kept; anything malformed is dropped, not stored. First touch wins: a second
-- call for the same lead records nothing.
create or replace function public.fn_marketing_first_touch_record(p_lead_id bigint, p_touch jsonb)
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  v_ok constant text := '^[A-Za-z0-9._-]{1,100}$';
  v_src text; v_med text; v_cmp text; v_cnt text; v_path text; v_at timestamptz; v_post bigint; v_id bigint;
begin
  if p_lead_id is null or p_touch is null or jsonb_typeof(p_touch) <> 'object' then
    return jsonb_build_object('ok', true, 'recorded', false, 'reason', 'no first touch');
  end if;
  v_src := nullif(btrim(p_touch->>'utm_source'), '');     if v_src !~ v_ok then v_src := null; end if;
  v_med := nullif(btrim(p_touch->>'utm_medium'), '');     if v_med !~ v_ok then v_med := null; end if;
  v_cmp := nullif(btrim(p_touch->>'utm_campaign'), '');   if v_cmp !~ v_ok then v_cmp := null; end if;
  v_cnt := nullif(btrim(p_touch->>'utm_content'), '');    if v_cnt !~ v_ok then v_cnt := null; end if;
  v_path := nullif(btrim(p_touch->>'landing_path'), '');  if v_path !~ '^/\S{0,200}$' then v_path := null; end if;
  if v_src is null then
    return jsonb_build_object('ok', true, 'recorded', false, 'reason', 'no valid utm_source');
  end if;
  begin
    v_at := (p_touch->>'first_seen_at')::timestamptz;
    if v_at < now() - interval '400 days' or v_at > now() + interval '1 hour' then v_at := null; end if;
  exception when others then v_at := null;
  end;
  if v_med = 'social' and v_cnt is not null then
    select id into v_post from public.marketing_post where ingest_key = lower(v_cnt);
  end if;
  insert into public.marketing_first_touch (lead_id, utm_source, utm_medium, utm_campaign, utm_content, landing_path, first_seen_at, post_id)
  values (p_lead_id, lower(v_src), v_med, v_cmp, v_cnt, v_path, v_at, v_post)
  on conflict (lead_id) do nothing
  returning id into v_id;
  return jsonb_build_object('ok', true, 'recorded', v_id is not null, 'post_id', v_post);
end
$fn$;
revoke execute on function public.fn_marketing_first_touch_record(bigint, jsonb) from public, anon, authenticated;

-- THE SCORECARD. Plain SQL, no model. For every post of the month (Asia/Dubai, by published_at, else
-- scheduled_at) and each platform it went to:
--   * each metric at the latest checkpoint it reached (28d > 7d > 3d > 1d);
--   * engagement_rate_by_followers on Instagram = total_interactions / followers on the day it was read
--     (Rival IQ's definition, so it compares with the sourced target);
--   * registrations = supplier registrations whose first touch named this post on this platform;
--   * each compared with marketing_goal (when a sourced target exists) and with the account's own median
--     for that platform and metric this month.
-- rank (per platform): registrations first, then how many of the post's metrics are at or above the median.
create or replace function public.fn_marketing_scorecard(p_month text, p_include_demo boolean default false)
returns table (platform text, rank int, post_id bigint, ingest_key text, title text, checkpoint text, metric text,
               value numeric, target numeric, account_median numeric, verdict text, benchmark_source text)
language sql stable security definer
set search_path to 'public', 'pg_temp'
as $fn$
  with posts as (
    select p.id, p.ingest_key, p.title
      from public.marketing_post p
     where to_char(coalesce(p.published_at, p.scheduled_at) at time zone 'Asia/Dubai', 'YYYY-MM') = p_month
       and (p_include_demo or not p.is_demo)
  ), latest as (
    select distinct on (m.post_id, m.platform, m.metric) m.post_id, m.platform, m.checkpoint, m.metric, m.value, m.captured_at
      from public.marketing_post_metric m join posts on posts.id = m.post_id
     where m.value is not null
     order by m.post_id, m.platform, m.metric,
              case m.checkpoint when '28d' then 4 when '7d' then 3 when '3d' then 2 else 1 end desc
  ), derived as (
    select l.post_id, l.platform, l.checkpoint, l.metric, l.value from latest l
    union all
    select l.post_id, l.platform, l.checkpoint, 'engagement_rate_by_followers', round(l.value / f.value, 6)
      from latest l
      cross join lateral (select d.value from public.marketing_insight_day d
                           where d.platform = 'instagram' and d.metric = 'followers'
                             and d.day <= (l.captured_at at time zone 'Asia/Dubai')::date
                           order by d.day desc limit 1) f
     where l.platform = 'instagram' and l.metric = 'total_interactions' and f.value > 0
    union all
    select pp.post_id, pp.platform, null, 'registrations', count(t.id)::numeric
      from public.marketing_post_platform pp join posts on posts.id = pp.post_id
      left join public.marketing_first_touch t on t.post_id = pp.post_id and t.utm_source = pp.platform
     group by pp.post_id, pp.platform
  ), med as (
    select d.platform, d.metric, percentile_cont(0.5) within group (order by d.value)::numeric as median
      from derived d group by d.platform, d.metric
  ), scored as (
    select d.*, round(md.median, 6) as median, g.target, g.benchmark_source,
           case when g.target is not null then (d.value >= g.target) else (d.value >= md.median) end as good
      from derived d
      join med md on md.platform = d.platform and md.metric = d.metric
      left join public.marketing_goal g on g.month = p_month and g.platform = d.platform and g.metric = d.metric
  ), post_score as (
    select s.post_id, s.platform,
           max(s.value) filter (where s.metric = 'registrations') as regs,
           count(*) filter (where s.metric <> 'registrations' and s.value >= s.median) as at_or_above
      from scored s group by s.post_id, s.platform
  )
  select s.platform,
         (dense_rank() over (partition by s.platform order by coalesce(ps.regs, 0) desc, ps.at_or_above desc, s.post_id))::int,
         s.post_id, p.ingest_key, p.title, s.checkpoint, s.metric, s.value, s.target, s.median,
         case when s.target is not null then case when s.good then 'met target' else 'below target' end
              else case when s.good then 'at or above own median' else 'below own median' end || ' (no sourced target)' end,
         s.benchmark_source
    from scored s join posts p on p.id = s.post_id join post_score ps on ps.post_id = s.post_id and ps.platform = s.platform
   order by s.platform, 2, s.metric
$fn$;
revoke execute on function public.fn_marketing_scorecard(text, boolean) from public, anon, authenticated;

-- Stores one scorecard per period. Idempotent: a period already stored returns stored=false.
create or replace function public.fn_marketing_scorecard_publish(p_kind text, p_period_key text, p_month text)
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare v_rows int; v_new boolean;
begin
  if p_kind not in ('weekly', 'month_end') then raise exception 'kind must be weekly or month_end'; end if;
  insert into public.marketing_scorecard_report (period_key, month, kind, rows, result)
  select p_period_key, p_month, p_kind, count(*), coalesce(jsonb_agg(to_jsonb(s)), '[]'::jsonb)
    from public.fn_marketing_scorecard(p_month) s
  on conflict (period_key) do nothing
  returning rows into v_rows;
  v_new := v_rows is not null;
  return jsonb_build_object('ok', true, 'stored', v_new, 'period_key', p_period_key, 'rows', v_rows);
end
$fn$;
revoke execute on function public.fn_marketing_scorecard_publish(text, text, text) from public, anon, authenticated;
