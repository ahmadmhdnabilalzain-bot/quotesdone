-- THE MARKETING SEAT PUBLISHES, MEASURES AND REPORTS ITS SPEND (22 Sep 2026; seat: marketing).
--
-- Founder, 22 Sep 2026: the marketing seat has access to Postiz and Meta; he and Claude create posts
-- together and INGEST them to the seat; the seat SCHEDULES them, MONITORS ANALYTICS, reports the overall
-- picture to the CEO (not for approval), collects the ad spend and shares it with the accountant.
--
-- WHAT WAS MEASURED (22 Sep 2026, read-only calls from the session, recorded in the PR):
--   * postiz_publish, meta_ads and meta_sync were deleted by #530 (7 Sep) when only two seats owned
--     anything. Their tables survived: social_posts (10 rows, Jun-Aug, the old Postiz ledger), meta_insights
--     (2 rows), ad_spend_policy / ad_campaign_state / ad_decision (the dormant autopilot: no scheduler, no
--     executor since #530), accountant_ad_spend_month (0 rows: nothing has written month_spent_aed since).
--   * Postiz answers GET /integrations 200 with facebook, instagram-standalone, linkedin-page, x, youtube,
--     none disabled. There is no postiz_api_url key, so the cloud base https://api.postiz.com/public/v1 is used.
--   * meta_access_token is a SYSTEM_USER token, valid, expires_at 0 (never), with ads_read, read_insights,
--     pages_read_engagement, instagram_manage_insights, pages_manage_posts, instagram_content_publish.
--     It sees page 1091910187348405 (tasks include ANALYZE, ADVERTISE) and its Instagram business account
--     17841422260736621 (@official.quotesdone). meta_ad_account_id now names "quotesdoneads": AED,
--     Asia/Dubai, account_status 1, business 2335064440232533 (Quotes Done), 0 campaigns, amount_spent 0.
--     The 14 Sep note that the ad account sat outside the business is superseded by this reading.
--   * Page metrics page_impressions and page_impressions_unique are refused by Graph ("must be a valid
--     insights metric"); page_post_engagements, page_follows and page_views_total answer.
--   * No LinkedIn credential exists; LinkedIn is reached through Postiz's linkedin-page channel, whose
--     GET /analytics/{id} answered 200.
--   * The accountant books Meta from the Meta INVOICE (expenses mailbox -> expense_entries) and matches it
--     against the REPORTED spend in accountant_ad_spend_month (every_meta_invoice_is_matched_to_the_spend_meta_reported.sql).
--
-- WHAT THIS BUILDS:
--   marketing_post                the content store: EN + AR text, media in the private marketing-media
--                                 bucket, channels, schedule, status draft/scheduled/publishing/published/failed/cancelled
--   fn_marketing_post_ingest      the one ingest path (supabase/functions/marketing_channels action 'ingest',
--                                 used by scripts/marketing/ingest_post.mjs)
--   marketing_connection_check    the MEASURED access state per platform and credential, with when and what
--                                 the founder must provide -- read by fn_marketing_connection_status
--   marketing_insight_day         page, Instagram, post and LinkedIn metrics, one row per metric per day
--   marketing_ad_spend_day        Meta spend per campaign per day, and the adspend.recorded handoff
--   fn_accountant_keeps_reported_ad_spend / fn_marketing_notes_ad_spend_booked   the two money handlers
--   fn_marketing_report_figures   the overall picture the marketing.report handoff carries to the CEO
--
-- WHAT IT DELIBERATELY DOES NOT DO:
--   * Nothing posts publicly: the scheduler publishes only when app_secrets.marketing_golive is 'true'
--     (measured 'false'), and never a ZZ DEMO post; otherwise it records the payload it WOULD send (dry_run).
--   * No ad money is spent and no budget is raised: nothing here writes to Meta, and the dormant autopilot
--     (fn_ads_manage, ad_decision) is left exactly as it is.
--   * The reported spend is NOT booked to the ledger: the Meta invoice is the tax document and is already
--     booked by the expenses duty; booking the reported figure as well would count the spend twice. The
--     accountant keeps it as the REPORTED side of the invoice match, which is what adspend.booked confirms.
--   * The seat, its handoff kinds (marketing.report, adspend.recorded, adspend.booked), fn_seat_handoff_types
--     and payment_handoffs.ts are the ceo/the-marketing-seat-exists build; APPLY THAT FILE FIRST. This file
--     names 'marketing' in function_owner and addresses handoffs to it.
--   * social_posts stays as the history of the June-August Postiz ledger; nothing writes it any more.
--
-- Prevented by: supabase/functions/_shared/marketing_channels.test.ts (mock HTTP: switch off never POSTs,
-- a demo post never goes live, tokens never stored, a campaign outside the business never reaches the books)
-- and scripts/checks/marketing_never_posts_or_spends_by_default.test.mjs.
--
--   node scripts/apply_sql.mjs scripts/sql/the_marketing_seat_publishes_measures_and_reports_spend.sql --apply --ddl

begin;

-- ── 1. THE PRIVATE MEDIA BUCKET ──────────────────────────────────────────────────────────────────
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('marketing-media', 'marketing-media', false, 52428800, array['image/png', 'image/jpeg', 'image/webp', 'video/mp4'])
on conflict (id) do nothing;

-- ── 2. THE CONTENT STORE ─────────────────────────────────────────────────────────────────────────
create table if not exists public.marketing_post (
  id            bigint generated always as identity primary key,
  ingest_key    text not null unique check (ingest_key ~ '^[a-z0-9][a-z0-9_-]{2,80}$'),
  owner_seat    text not null default 'marketing' check (owner_seat = 'marketing'),
  ingested_by   text not null check (ingested_by in ('founder', 'claude', 'marketing')),
  title         text,
  text_en       text not null check (btrim(text_en) <> ''),
  -- Arabic letters must be present (the class is the Arabic block U+0600..U+06FF): a body that arrived
  -- as question marks is refused here, not published.
  text_ar       text not null check (text_ar ~ '[؀-ۿ]'),
  media_paths   text[] not null default '{}',
  channels      text[] not null check (cardinality(channels) > 0 and channels <@ array['facebook', 'instagram', 'linkedin', 'x']),
  scheduled_at  timestamptz,
  status        text not null default 'draft'
                check (status in ('draft', 'scheduled', 'publishing', 'published', 'failed', 'cancelled')),
  is_demo       boolean not null default false,
  dry_run       jsonb,
  postiz_result jsonb,
  permalinks    jsonb,
  error         text,
  attempts      int not null default 0,
  published_at  timestamptz,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  constraint marketing_post_scheduled_has_a_time check (status not in ('scheduled', 'publishing', 'published') or scheduled_at is not null),
  constraint marketing_post_instagram_needs_media check (not ('instagram' = any (channels)) or cardinality(media_paths) > 0),
  constraint marketing_post_demo_is_marked check (not is_demo or text_en like 'ZZ DEMO%'),
  constraint marketing_post_failed_says_why check (status <> 'failed' or error is not null),
  constraint marketing_post_published_says_when check (status <> 'published' or published_at is not null)
);
comment on table public.marketing_post is
  'Posts the founder and Claude ingest to the marketing seat (EN + AR, media in the private marketing-media bucket). The seat publishes a scheduled post through Postiz when app_secrets.marketing_golive is true; otherwise dry_run holds the payload it would have sent.';
create index if not exists marketing_post_due_idx on public.marketing_post (scheduled_at) where status = 'scheduled';
alter table public.marketing_post enable row level security;
drop policy if exists marketing_post_service_role_only on public.marketing_post;
create policy marketing_post_service_role_only on public.marketing_post as permissive for all to public using (false) with check (false);
revoke all on public.marketing_post from anon, authenticated;

-- ── 3. THE MEASURED CONNECTION STATE ─────────────────────────────────────────────────────────────
create table if not exists public.marketing_connection_check (
  check_key       text primary key check (check_key ~ '^[a-z]+(\.[a-z_]+)+$'),
  platform        text not null check (platform in ('postiz', 'meta', 'linkedin')),
  ok              boolean not null,
  http_status     int,
  credential_keys text[] not null default '{}',
  detail          jsonb not null default '{}',
  needs           text,
  measured_at     timestamptz not null,
  constraint marketing_connection_check_failure_names_the_need check (ok or btrim(coalesce(needs, '')) <> '')
);
comment on table public.marketing_connection_check is
  'What each marketing credential answered to a READ-ONLY call, and when (never a typed CONNECTED). needs names what the founder must provide or grant when ok is false. Written by marketing_channels action access_check.';
alter table public.marketing_connection_check enable row level security;
drop policy if exists marketing_connection_check_service_role_only on public.marketing_connection_check;
create policy marketing_connection_check_service_role_only on public.marketing_connection_check as permissive for all to public using (false) with check (false);
revoke all on public.marketing_connection_check from anon, authenticated;

-- ── 4. ANALYTICS, ONE ROW PER METRIC PER DAY ─────────────────────────────────────────────────────
create table if not exists public.marketing_insight_day (
  platform    text not null check (platform in ('facebook', 'instagram', 'linkedin', 'x')),
  object_type text not null check (object_type in ('page', 'account', 'post')),
  object_id   text not null check (btrim(object_id) <> ''),
  metric      text not null check (metric ~ '^[a-z0-9_]+$'),
  day         date not null,
  value       numeric not null,
  pulled_at   timestamptz not null default now(),
  primary key (platform, object_id, metric, day)
);
comment on table public.marketing_insight_day is
  'Read-only insights pulled daily by marketing_channels (Meta page and Instagram through Graph, LinkedIn through Postiz analytics, post counters as a daily snapshot). Feeds fn_marketing_report_figures.';
alter table public.marketing_insight_day enable row level security;
drop policy if exists marketing_insight_day_service_role_only on public.marketing_insight_day;
create policy marketing_insight_day_service_role_only on public.marketing_insight_day as permissive for all to public using (false) with check (false);
revoke all on public.marketing_insight_day from anon, authenticated;

-- ── 5. AD SPEND, PER CAMPAIGN PER DAY ────────────────────────────────────────────────────────────
create table if not exists public.marketing_ad_spend_day (
  account_id    text not null check (account_id ~ '^act_[0-9]+$'),
  campaign_id   text not null check (btrim(campaign_id) <> ''),
  day           date not null,
  campaign_name text,
  spend         numeric(14, 2) not null check (spend >= 0),
  currency      text not null check (currency ~ '^[A-Z]{3}$'),
  impressions   bigint,
  clicks        bigint,
  is_demo       boolean not null default false,
  pulled_at     timestamptz not null default now(),
  handed_off_at timestamptz,
  booked_ack_at timestamptz,
  primary key (account_id, campaign_id, day),
  constraint marketing_ad_spend_day_demo_is_marked check (not is_demo or campaign_name like 'ZZ DEMO%')
);
comment on table public.marketing_ad_spend_day is
  'Meta ad spend read daily (insights level=campaign, time_increment=1) from the configured ad account, only while that account sits in the Quotes Done business. A closed day is handed to the accountant as adspend.recorded; a revised figure is handed again. ZZ DEMO rows are never handed off.';
alter table public.marketing_ad_spend_day enable row level security;
drop policy if exists marketing_ad_spend_day_service_role_only on public.marketing_ad_spend_day;
create policy marketing_ad_spend_day_service_role_only on public.marketing_ad_spend_day as permissive for all to public using (false) with check (false);
revoke all on public.marketing_ad_spend_day from anon, authenticated;

-- ── 6. WHEN EACH DAILY DUTY LAST RAN ─────────────────────────────────────────────────────────────
create table if not exists public.marketing_duty_run (
  duty            text primary key check (duty in ('access', 'insights', 'ad_spend')),
  last_started_at timestamptz,
  last_ok_at      timestamptz,
  last_result     jsonb
);
alter table public.marketing_duty_run enable row level security;
drop policy if exists marketing_duty_run_service_role_only on public.marketing_duty_run;
create policy marketing_duty_run_service_role_only on public.marketing_duty_run as permissive for all to public using (false) with check (false);
revoke all on public.marketing_duty_run from anon, authenticated;

insert into public.decision_policy (key, value, description) values
  ('marketing_meta_business_id', to_jsonb('2335064440232533'::text),
   'The Quotes Done Meta business portfolio. Ad spend is recorded for the books only while the configured ad account belongs to it (measured 22 Sep 2026).'),
  ('marketing_meta_graph_version', to_jsonb('v21.0'::text),
   'Graph API version the marketing seat calls (measured answering 22 Sep 2026). Raise it here, not in code.'),
  ('marketing_ad_spend_lookback_days', '7'::jsonb,
   'Days of Meta spend the daily read re-reads, so a figure Meta revises after the day closes is handed to the accountant again.')
on conflict (key) do nothing;

-- ── 7. INGEST ────────────────────────────────────────────────────────────────────────────────────
create or replace function public.fn_marketing_post_ingest(p jsonb)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  v_key text := lower(btrim(coalesce(p->>'ingest_key', '')));
  v_at timestamptz := nullif(p->>'scheduled_at', '')::timestamptz;
  v_media text[] := coalesce((select array_agg(x) from jsonb_array_elements_text(coalesce(p->'media_paths', '[]'::jsonb)) x), '{}');
  v_ch text[] := coalesce((select array_agg(distinct lower(x)) from jsonb_array_elements_text(coalesce(p->'channels', '[]'::jsonb)) x), '{}');
  v_cur public.marketing_post; v_id bigint;
begin
  if public.fn_text_lost_its_script(p->>'text_ar') or public.fn_text_lost_its_script(p->>'text_en') then
    return jsonb_build_object('ok', false, 'error', 'text_lost_its_script',
      'message', 'The text arrived as question marks; send it as UTF-8 (scripts/marketing/ingest_post.mjs does).');
  end if;
  if v_at is not null and v_at < now() - interval '1 hour' then
    return jsonb_build_object('ok', false, 'error', 'scheduled_in_the_past',
      'message', 'scheduled_at is more than an hour ago; a past time would publish at once. Send a future time or none (draft).');
  end if;
  if exists (select 1 from unnest(v_media) m where m !~ '^posts/[a-z0-9_-]+/[A-Za-z0-9._-]+$') then
    return jsonb_build_object('ok', false, 'error', 'media_path_outside_the_bucket_layout',
      'message', 'media_paths are marketing-media objects under posts/<ingest_key>/.');
  end if;

  select * into v_cur from public.marketing_post where ingest_key = v_key for update;
  if found and v_cur.status not in ('draft', 'scheduled') then
    return jsonb_build_object('ok', true, 'id', v_cur.id, 'unchanged', true, 'status', v_cur.status,
      'message', 'Already ' || v_cur.status || '; a post that reached Postiz is not edited. Ingest it under a new key.');
  end if;

  insert into public.marketing_post (ingest_key, ingested_by, title, text_en, text_ar, media_paths, channels,
                                     scheduled_at, status, is_demo)
  values (v_key, coalesce(p->>'ingested_by', 'claude'), nullif(btrim(p->>'title'), ''), p->>'text_en', p->>'text_ar',
          v_media, v_ch, v_at, case when v_at is null then 'draft' else 'scheduled' end,
          coalesce((p->>'is_demo')::boolean, false))
  on conflict (ingest_key) do update
     set ingested_by = excluded.ingested_by, title = excluded.title, text_en = excluded.text_en,
         text_ar = excluded.text_ar, media_paths = excluded.media_paths, channels = excluded.channels,
         scheduled_at = excluded.scheduled_at, status = excluded.status, is_demo = excluded.is_demo,
         dry_run = null, updated_at = now()
  returning id into v_id;
  return jsonb_build_object('ok', true, 'id', v_id, 'status', case when v_at is null then 'draft' else 'scheduled' end,
                            'updated', v_cur.id is not null);
end $fn$;
revoke execute on function public.fn_marketing_post_ingest(jsonb) from public, anon, authenticated;

-- ── 8. WHICH DAILY DUTIES ARE DUE (Asia/Dubai day; a failed run retries after two hours) ──────────
create or replace function public.fn_marketing_duties_due()
returns jsonb language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  -- Due when no success yet today; but a start with no success after it is a run in flight or one that
  -- failed, so that waits two hours instead of hammering Graph every beat.
  select jsonb_object_agg(d.duty,
           (r.last_ok_at is null or (r.last_ok_at at time zone 'Asia/Dubai')::date < (now() at time zone 'Asia/Dubai')::date)
           and (r.last_started_at is null or r.last_started_at <= coalesce(r.last_ok_at, '-infinity')
                or r.last_started_at < now() - interval '2 hours'))
    from (values ('access'), ('insights'), ('ad_spend')) d(duty)
    left join public.marketing_duty_run r on r.duty = d.duty
$fn$;
revoke execute on function public.fn_marketing_duties_due() from public, anon, authenticated;

create or replace function public.fn_marketing_duty_mark(p_duty text, p_phase text, p_result jsonb default null)
returns void language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
begin
  if p_phase not in ('start', 'ok', 'error') then raise exception 'phase must be start, ok or error'; end if;
  insert into public.marketing_duty_run (duty, last_started_at, last_ok_at, last_result)
  values (p_duty, case when p_phase = 'start' then now() end, case when p_phase = 'ok' then now() end, p_result)
  on conflict (duty) do update
     set last_started_at = case when p_phase = 'start' then now() else marketing_duty_run.last_started_at end,
         last_ok_at = case when p_phase = 'ok' then now() else marketing_duty_run.last_ok_at end,
         last_result = coalesce(p_result, marketing_duty_run.last_result);
end $fn$;
revoke execute on function public.fn_marketing_duty_mark(text, text, jsonb) from public, anon, authenticated;

-- ── 9. THE CONNECTION STATUS THE CEO REPORT AND THE IT ENGINEER READ ──────────────────────────────
create or replace function public.fn_marketing_connection_status()
returns jsonb language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  select jsonb_build_object(
    'all_ok', coalesce(bool_and(c.ok), false),
    'oldest_measurement', min(c.measured_at),
    'checks', coalesce(jsonb_agg(jsonb_build_object('check', c.check_key, 'platform', c.platform, 'ok', c.ok,
                'http_status', c.http_status, 'measured_at', c.measured_at, 'credential_keys', c.credential_keys,
                'needs', c.needs, 'detail', c.detail) order by c.check_key), '[]'::jsonb),
    'never_measured', not exists (select 1 from public.marketing_connection_check))
  from public.marketing_connection_check c
$fn$;
revoke execute on function public.fn_marketing_connection_status() from public, anon, authenticated;

-- ── 10. AD SPEND: RECORD THE READ, HAND CLOSED DAYS TO THE ACCOUNTANT ────────────────────────────
-- p_rows: [{campaign_id, campaign_name, day, spend, currency, impressions, clicks}] as Graph returned them.
-- p_business_id is the business the account reported on the SAME read; a mismatch records nothing.
create or replace function public.fn_marketing_ad_spend_record(p_account text, p_business_id text, p_rows jsonb, p_is_demo boolean default false)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  v_expected_acct text := 'act_' || regexp_replace(coalesce((select value from public.app_secrets where key = 'meta_ad_account_id'), ''), '^act_', '');
  v_business text := (select value #>> '{}' from public.decision_policy where key = 'marketing_meta_business_id');
  v_today date := (now() at time zone 'Asia/Dubai')::date;
  v_n int := 0; v_handoffs int := 0; d record;
begin
  if not p_is_demo and (p_account is distinct from v_expected_acct or p_business_id is distinct from v_business) then
    return jsonb_build_object('ok', false, 'error', 'account_not_the_company',
      'message', 'The ad account read is not app_secrets.meta_ad_account_id inside the Quotes Done business (decision_policy marketing_meta_business_id); nothing was recorded.',
      'account', p_account, 'business', p_business_id);
  end if;

  insert into public.marketing_ad_spend_day as t (account_id, campaign_id, day, campaign_name, spend, currency, impressions, clicks, is_demo, pulled_at)
  select p_account, r->>'campaign_id', (r->>'day')::date, r->>'campaign_name', round((r->>'spend')::numeric, 2),
         upper(r->>'currency'), nullif(r->>'impressions', '')::bigint, nullif(r->>'clicks', '')::bigint, p_is_demo, now()
    from jsonb_array_elements(coalesce(p_rows, '[]'::jsonb)) r
  on conflict (account_id, campaign_id, day) do update
     set campaign_name = excluded.campaign_name, currency = excluded.currency, impressions = excluded.impressions,
         clicks = excluded.clicks, pulled_at = now(),
         -- a revised figure goes to the accountant again
         handed_off_at = case when excluded.spend is distinct from t.spend then null else t.handed_off_at end,
         booked_ack_at = case when excluded.spend is distinct from t.spend then null else t.booked_ack_at end,
         spend = excluded.spend;
  get diagnostics v_n = row_count;

  -- One handoff per closed day (Asia/Dubai), never for today, never for a demo row, never for a zero.
  for d in
    select s.account_id, s.day, sum(s.spend) spend, min(s.currency) currency, count(distinct s.currency) currencies,
           jsonb_agg(jsonb_build_object('campaign_id', s.campaign_id, 'campaign_name', s.campaign_name, 'spend', s.spend) order by s.campaign_id) campaigns
      from public.marketing_ad_spend_day s
     where s.account_id = p_account and not s.is_demo and s.day < v_today
       and exists (select 1 from public.marketing_ad_spend_day u
                    where u.account_id = s.account_id and u.day = s.day and not u.is_demo and u.handed_off_at is null)
     group by s.account_id, s.day
    having sum(s.spend) > 0
  loop
    -- Marked BEFORE the handoff: the accountant answers inside fn_seat_handoff and sums the handed-off days,
    -- so today's still-moving figure never enters the month it keeps (a probe caught 3 AED of today in it).
    update public.marketing_ad_spend_day set handed_off_at = now()
     where account_id = d.account_id and day = d.day and not is_demo;
    perform public.fn_seat_handoff('marketing', 'accountant', 'adspend.recorded', 'marketing_ad_spend_day',
      d.account_id || ':' || d.day || ':' || d.spend,
      jsonb_build_object('account_id', d.account_id, 'day', d.day, 'spend', d.spend,
                         'currency', case when d.currencies = 1 then d.currency end, 'is_demo', false,
                         'campaigns', d.campaigns, 'source', 'Meta Graph insights level=campaign time_increment=1'));
    v_handoffs := v_handoffs + 1;
  end loop;
  return jsonb_build_object('ok', true, 'rows', v_n, 'handoffs', v_handoffs);
end $fn$;
revoke execute on function public.fn_marketing_ad_spend_record(text, text, jsonb, boolean) from public, anon, authenticated;

-- ── 11. adspend.recorded -> accountant: keep the REPORTED side of the invoice match ───────────────
create or replace function public.fn_accountant_keeps_reported_ad_spend(p_id bigint)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  a public.agent_actions; v_day date; v_month date; v_acct text; v_rep numeric; f jsonb;
  v_expected_acct text := 'act_' || regexp_replace(coalesce((select value from public.app_secrets where key = 'meta_ad_account_id'), ''), '^act_', '');
begin
  select * into a from public.agent_actions where id = p_id and kind = 'handoff';
  v_day := nullif(a.detail->>'day', '')::date; v_acct := a.detail->>'account_id';
  -- TEST AND SANDBOX AMOUNTS NEVER REACH THE BOOKS: refused here even though the sender never sends them.
  if coalesce((a.detail->>'is_demo')::boolean, true) then
    return jsonb_build_object('kept', false, 'refused', 'demo_or_unmarked', 'message', 'A demo or unmarked amount is never kept for the books.');
  end if;
  if v_acct is distinct from v_expected_acct or v_day is null then
    return jsonb_build_object('kept', false, 'refused', 'not_the_company_account', 'account', v_acct);
  end if;
  if coalesce(a.detail->>'currency', '') <> 'AED' then
    return jsonb_build_object('kept', false, 'refused', 'currency_not_aed', 'currency', a.detail->>'currency',
      'message', 'The ad account reports in AED (measured 22 Sep 2026); another currency is held until a conversion rule exists.');
  end if;

  v_month := date_trunc('month', v_day)::date;
  select round(sum(spend), 2) into v_rep from public.marketing_ad_spend_day
   where account_id = v_acct and not is_demo and currency = 'AED' and handed_off_at is not null
     and day >= v_month and day < (v_month + interval '1 month')::date;
  if coalesce(v_rep, 0) > 0 then
    insert into public.accountant_ad_spend_month (month, reported_spend_aed, reported_at, updated_at)
    values (v_month, v_rep, now(), now())
    on conflict (month) do update set reported_spend_aed = excluded.reported_spend_aed, reported_at = now(), updated_at = now();
    -- the hourly snapshot (fn_accountant_ad_spend_snapshot) reads this row; keep it saying the same figure
    update public.ad_spend_policy set month_spent_aed = v_rep, month_label = to_char(v_month, 'YYYY-MM'), updated_at = now()
     where policy_key = 'default' and to_char(v_month, 'YYYY-MM') = to_char(now() at time zone 'Asia/Dubai', 'YYYY-MM');
  end if;
  f := public.fn_accountant_ad_spend_figures(v_month);

  perform public.fn_seat_handoff('accountant', 'marketing', 'adspend.booked', 'accountant_ad_spend_month',
    to_char(v_month, 'YYYY-MM') || ':' || coalesce(v_rep, 0),
    jsonb_build_object('month', to_char(v_month, 'YYYY-MM'), 'reported_spend_aed', v_rep,
                       'invoiced_aed', f->'invoiced_aed', 'difference_aed', f->'difference_aed', 'missing', f->'missing',
                       'basis', 'Kept as the REPORTED side of the Meta invoice match. The ledger entry comes from the Meta invoice in expense_entries, so the spend is counted once.'));
  return jsonb_build_object('kept', true, 'month', to_char(v_month, 'YYYY-MM'), 'reported_spend_aed', v_rep, 'figures', f);
end $fn$;
revoke execute on function public.fn_accountant_keeps_reported_ad_spend(bigint) from public, anon, authenticated;

-- ── 12. adspend.booked -> marketing: the seat notes the accountant's answer on its rows ────────────
create or replace function public.fn_marketing_notes_ad_spend_booked(p_id bigint)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare a public.agent_actions; v_month date; v_n int;
begin
  select * into a from public.agent_actions where id = p_id and kind = 'handoff';
  v_month := to_date(a.detail->>'month' || '-01', 'YYYY-MM-DD');
  update public.marketing_ad_spend_day set booked_ack_at = now()
   where not is_demo and handed_off_at is not null and booked_ack_at is null
     and day >= v_month and day < (v_month + interval '1 month')::date;
  get diagnostics v_n = row_count;
  return jsonb_build_object('acknowledged_rows', v_n, 'month', a.detail->>'month',
                            'reported_spend_aed', a.detail->'reported_spend_aed', 'invoiced_aed', a.detail->'invoiced_aed');
end $fn$;
revoke execute on function public.fn_marketing_notes_ad_spend_booked(bigint) from public, anon, authenticated;

-- ── 13. THE OVERALL PICTURE FOR THE CEO (marketing.report carries this; it asks for nothing) ──────
create or replace function public.fn_marketing_report_figures(p_days int default 7)
returns jsonb language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  with w as (select now() - make_interval(days => greatest(1, p_days)) as since)
  select jsonb_build_object(
    'window_days', greatest(1, p_days),
    'publishing_live', coalesce((select lower(value) = 'true' from public.app_secrets where key = 'marketing_golive'), false),
    'posts', jsonb_build_object(
      'draft', (select count(*) from public.marketing_post where status = 'draft' and not is_demo),
      'scheduled_next_window', (select count(*) from public.marketing_post where status = 'scheduled' and not is_demo
                                   and scheduled_at < now() + make_interval(days => greatest(1, p_days))),
      'due_held_by_switch', (select count(*) from public.marketing_post where status = 'scheduled' and not is_demo
                                and scheduled_at <= now() and dry_run is not null),
      'published_in_window', (select count(*) from public.marketing_post, w where status = 'published' and published_at >= w.since),
      'failed_in_window', (select count(*) from public.marketing_post, w where status = 'failed' and updated_at >= w.since),
      'stuck_publishing', (select count(*) from public.marketing_post where status = 'publishing' and updated_at < now() - interval '30 minutes')),
    'insights', coalesce((select jsonb_object_agg(k, v) from (
        select i.platform || '.' || i.metric k, sum(i.value) v
          from public.marketing_insight_day i, w
         where i.object_type <> 'post' and i.day >= (w.since at time zone 'Asia/Dubai')::date
         group by 1) x), '{}'::jsonb),
    'ad_spend', jsonb_build_object(
      'window_aed', (select coalesce(sum(spend), 0) from public.marketing_ad_spend_day, w
                      where not is_demo and currency = 'AED' and day >= (w.since at time zone 'Asia/Dubai')::date),
      'month_to_date_aed', (select coalesce(sum(spend), 0) from public.marketing_ad_spend_day
                             where not is_demo and currency = 'AED'
                               and day >= date_trunc('month', now() at time zone 'Asia/Dubai')::date),
      'handed_to_accountant_days', (select count(distinct day) from public.marketing_ad_spend_day where not is_demo and handed_off_at is not null),
      'acknowledged_by_accountant_days', (select count(distinct day) from public.marketing_ad_spend_day where not is_demo and booked_ack_at is not null)),
    'connections', public.fn_marketing_connection_status(),
    'duties', coalesce((select jsonb_object_agg(duty, jsonb_build_object('last_ok_at', last_ok_at, 'last_started_at', last_started_at))
                          from public.marketing_duty_run), '{}'::jsonb))
$fn$;
revoke execute on function public.fn_marketing_report_figures(integer) from public, anon, authenticated;

-- ── 14. THE SEAT'S RUNTIME CREDENTIAL, OWNER ROW AND CLOCK ──────────────────────────────────────
do $mint$
declare v_secret text;
begin
  if exists (select 1 from public.internal_credential where context = 'fn.marketing_channels') then return; end if;
  v_secret := encode(extensions.gen_random_bytes(32), 'hex');
  insert into public.internal_credential (context, label, secret_hash, scope, is_legacy, active)
  values ('fn.marketing_channels',
          'The marketing seat''s hands on Postiz and Meta: ingest, access check, scheduled publishing (behind marketing_golive), insights and ad spend reads',
          public.fn_internal_credential_hash(v_secret), array['marketing_channels'], false, true);
  insert into public.app_secrets (key, value) values ('cred_fn_marketing_channels', v_secret)
  on conflict (key) do update set value = excluded.value;
end
$mint$;

insert into public.function_owner (function_slug, owner, note)
values ('marketing_channels', 'marketing',
        'The marketing seat''s runtime on Postiz and Meta. Founder, 22 Sep 2026: the seat schedules the posts he and Claude ingest, monitors analytics, reports to the CEO and shares the ad spend with the accountant. Publishing waits on app_secrets.marketing_golive; nothing here spends on ads.')
on conflict (function_slug) do update set owner = excluded.owner, note = excluded.note;

insert into public.resilience_step (step, every, budget_ms, place, rank, note) values
  ('marketingChannels', interval '15 min', 3000, 'plan', 0,
   'marketing: publishes due posts (dry run while marketing_golive is false) every beat; the access check, insights and ad spend reads run once per Dubai day inside marketing_channels (fn_marketing_duties_due)')
on conflict (step) do update
   set every = excluded.every, budget_ms = excluded.budget_ms, place = excluded.place, rank = excluded.rank, note = excluded.note;

-- ── 15. BACKUP REGISTRY: the bucket and marketing_post.media_paths (fn_backup_source_registry) ────
-- Copied from its current definition (the_cad_read_queue_path_is_registered_for_backup.sql) with two rows added:
-- the marketing-media bucket and marketing_post.media_paths, both filed by the STORAGE SWEEP.
CREATE OR REPLACE FUNCTION public.fn_backup_source_registry()
 RETURNS TABLE(source text, kind text, bucket text, backed_up boolean, enqueue_rule text, reason text)
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  values
    -- ── (a) backed up by an owner rule: each names the fn_enqueue_doc_backups section that files it ──
    ('leads.license_doc_path',               'column', 'supplier-docs', true,  'fn_enqueue_doc_backups: SUPPLIERS', null),
    ('leads.egr_doc_path',                   'column', 'supplier-docs', true,  'fn_enqueue_doc_backups: SUPPLIERS', null),
    ('leads.insurance_doc_path',             'column', 'supplier-docs', true,  'fn_enqueue_doc_backups: SUPPLIERS', null),
    ('leads.vat_doc_path',                   'column', 'supplier-docs', true,  'fn_enqueue_doc_backups: SUPPLIERS', null),
    ('leads.iso_doc_path',                   'column', 'supplier-docs', true,  'fn_enqueue_doc_backups: SUPPLIERS', null),
    ('leads.manufacturer_auth_doc_path',     'column', 'supplier-docs', true,  'fn_enqueue_doc_backups: SUPPLIERS', null),
    ('leads.company_profile_doc_path',       'column', 'supplier-docs', true,  'fn_enqueue_doc_backups: SUPPLIERS', null),
    ('leads.catalog_doc_paths',              'column', 'supplier-docs', true,  'fn_enqueue_doc_backups: SUPPLIERS (catalogue)', null),
    ('leads.signed_terms_path',              'column', 'signed-terms',  true,  'fn_enqueue_doc_backups: SUPPLIERS', null),
    ('customers.signed_terms_path',          'column', 'signed-terms',  true,  'fn_enqueue_doc_backups: CUSTOMERS', null),
    ('inquiries.drawing_file_path',          'column', 'drawing-files', true,  'fn_enqueue_doc_backups: INQUIRIES', null),
    ('transactions.doc_path',                'column', 'finance-docs',  true,  'fn_enqueue_doc_backups: REVENUE INVOICES', null),
    ('conversation_archive.pdf_path',        'column', 'backups',       true,  'fn_enqueue_doc_backups: CORRESPONDENCE', null),
    ('backups/<YYYY-MM-DD>/<table>/page_NNNN.json', 'export', 'backups', true, 'fn_enqueue_doc_backups: TABLE EXPORTS (written daily by supabase/functions/backup; the tables are fn_table_export_list()); kept 90 days, Friday full copies 12 months (fn_backup_prune_tick)', null),
    -- The accountant's four (open gaps until 14 Sep 2026, closed by
    -- the_accountant_files_the_year_end_pack_in_dropbox_and_the_backups_bucket.sql). A path stored as
    -- '<bucket>/<path>' names its bucket itself, so the bucket column is null for those two.
    ('accountant_month_close.pdf_path',      'column', 'finance-reports', true, 'fn_enqueue_doc_backups: ACCOUNTING', null),
    ('accountant_month_close.csv_path',      'column', 'finance-reports', true, 'fn_enqueue_doc_backups: ACCOUNTING', null),
    ('accountant_issued_document.file_path', 'column', null,              true, 'fn_enqueue_doc_backups: ACCOUNTING', null),
    ('bank_statement_intake.doc_path',       'column', null,              true, 'fn_enqueue_doc_backups: ACCOUNTING', null),

    -- ── (a) the buckets: every file an owner rule did not file is filed by the STORAGE SWEEP ──
    ('supplier-docs',    'bucket', 'supplier-docs',    true, 'fn_enqueue_doc_backups: SUPPLIERS; STORAGE SWEEP for every other file (inbound/, legal/, catalog/ ...)', null),
    ('signed-terms',     'bucket', 'signed-terms',     true, 'fn_enqueue_doc_backups: SUPPLIERS, CUSTOMERS; STORAGE SWEEP for every other signed record', null),
    ('drawing-files',    'bucket', 'drawing-files',    true, 'fn_enqueue_doc_backups: INQUIRIES; STORAGE SWEEP for every other file, the anonymised redacted/ copies included', null),
    ('finance-docs',     'bucket', 'finance-docs',     true, 'fn_enqueue_doc_backups: REVENUE INVOICES; STORAGE SWEEP for every other file', null),
    ('backups',          'bucket', 'backups',          true, 'fn_enqueue_doc_backups: CORRESPONDENCE, ACCOUNTING (the year-end pack in backups/accountant/year-end/), TABLE EXPORTS; dropbox_backup renders generated documents into backups/generated/; STORAGE SWEEP for everything outside the dated export folders, conversations/ and generated/ (archives/, engineering/, imports/ ...)', null),
    ('quote-files',      'bucket', 'quote-files',      true, 'fn_enqueue_doc_backups: STORAGE SWEEP (suppliers'' quotation files and the regenerated quotations)', null),
    ('compliance-docs',  'bucket', 'compliance-docs',  true, 'fn_enqueue_doc_backups: STORAGE SWEEP (compliance sources as downloaded, the UAE library)', null),
    ('receipt-files',    'bucket', 'receipt-files',    true, 'fn_enqueue_doc_backups: ACCOUNTING (bank statements); STORAGE SWEEP for the expense receipts (the inbound mailbox keeps about a month)', null),
    ('agent-docs',       'bucket', 'agent-docs',       true, 'fn_enqueue_doc_backups: STORAGE SWEEP (quotations and invoices as sent, weekly reports, incident PDFs)', null),
    ('finance-reports',  'bucket', 'finance-reports',  true, 'fn_enqueue_doc_backups: ACCOUNTING (month close); STORAGE SWEEP for every other report and legal notice', null),
    ('reports',          'bucket', 'reports',          true, 'fn_enqueue_doc_backups: STORAGE SWEEP (board and executive report PDFs; their rows are not in the daily table export)', null),
    ('social-media',     'bucket', 'social-media',     true, 'fn_enqueue_doc_backups: STORAGE SWEEP (generated post cards and avatars; not in the repository)', null),
    ('brand',            'bucket', 'brand',            true, 'fn_enqueue_doc_backups: STORAGE SWEEP (brand kit, signature and stamp images; not in the repository)', null),
    ('kb-import-assets', 'bucket', 'kb-import-assets', true, 'fn_enqueue_doc_backups: STORAGE SWEEP (knowledge import runs; only part of it is in the repository)', null),
    ('site',             'bucket', 'site',             true, 'fn_enqueue_doc_backups: STORAGE SWEEP (the static website pages as first published)', null),
    ('marketing-media',  'bucket', 'marketing-media',  true, 'fn_enqueue_doc_backups: STORAGE SWEEP (the media of the posts the founder and Claude ingest to the marketing seat; private, not in the repository)', null),

    -- ── (a) columns whose files are filed by the STORAGE SWEEP of the bucket they sit in ──
    -- measured 15 Sep 2026 where rows exist; "no writer today" where no code writes the column yet
    ('quotes.original_file_path',            'column', 'quote-files',      true, 'fn_enqueue_doc_backups: STORAGE SWEEP (written by supplier_api)', null),
    ('quote_spec_hold.pdf_path',             'column', null,               true, 'fn_enqueue_doc_backups: STORAGE SWEEP (bucket in quote_spec_hold.pdf_bucket; the regenerated quotations sit in quote-files)', null),
    ('quote_reviews.original_file_path',     'column', null,               true, 'fn_enqueue_doc_backups: STORAGE SWEEP (no writer today)', null),
    ('quote_committed_items.sub_quote_path', 'column', null,               true, 'fn_enqueue_doc_backups: STORAGE SWEEP (no writer today)', null),
    ('quote_items.datasheet_path',           'column', null,               true, 'fn_enqueue_doc_backups: STORAGE SWEEP (no writer today)', null),
    ('rfq_archives.archive_path',            'column', null,               true, 'fn_enqueue_doc_backups: STORAGE SWEEP (bucket in rfq_archives.bucket; backups/archives/ is swept)', null),
    ('compliance_sources.doc_path',          'column', 'compliance-docs',  true, 'fn_enqueue_doc_backups: STORAGE SWEEP (16 of 16 paths in compliance-docs)', null),
    ('support_artifact.storage_path',        'column', null,               true, 'fn_enqueue_doc_backups: STORAGE SWEEP (no writer today)', null),
    ('support_document_intake.storage_path', 'column', 'supplier-docs',    true, 'fn_enqueue_doc_backups: STORAGE SWEEP (the path is the one written into leads.*_doc_path)', null),
    ('wa_document_intake.storage_path',      'column', 'supplier-docs',    true, 'fn_enqueue_doc_backups: STORAGE SWEEP (the path is the one written into leads.*_doc_path)', null),
    ('messages.attachment_path',             'column', null,               true, 'fn_enqueue_doc_backups: STORAGE SWEEP (bucket chosen by the portal, recorded in public.documents)', null),
    ('customer_calls.recording_path',        'column', null,               true, 'fn_enqueue_doc_backups: STORAGE SWEEP (no writer today)', null),
    ('refunds.doc_path',                     'column', null,               true, 'fn_enqueue_doc_backups: STORAGE SWEEP (no writer today)', null),
    ('supplier_dues.demand_letter_path',     'column', null,               true, 'fn_enqueue_doc_backups: STORAGE SWEEP (no writer today; the legal notices on file sit in supplier-docs/legal/ and finance-reports/legal/)', null),
    ('supplier_dues.case_file_path',         'column', null,               true, 'fn_enqueue_doc_backups: STORAGE SWEEP (no writer today)', null),
    ('supplier_dues.evidence_terms_path',    'column', null,               true, 'fn_enqueue_doc_backups: STORAGE SWEEP (no writer today)', null),
    ('expense_entries.doc_path',             'column', 'receipt-files',    true, 'fn_enqueue_doc_backups: STORAGE SWEEP (52 of 52 paths in receipt-files; the inbound mailbox keeps about a month)', null),
    ('doc_reviews.file_path',                'column', 'supplier-docs',    true, 'fn_enqueue_doc_backups: STORAGE SWEEP (7 of 7 paths in supplier-docs/inbound/, none filed by an owner rule)', null),
    ('supplier_catalog.source_document_path','column', 'supplier-docs',    true, 'fn_enqueue_doc_backups: STORAGE SWEEP (written by supplier_catalog_ingest into supplier-docs/catalog/)', null),
    ('drawing_redaction_runs.source_path',   'column', 'drawing-files',    true, 'fn_enqueue_doc_backups: STORAGE SWEEP (the customer''s original drawing; also INQUIRIES)', null),
    ('accountant_weekly_report.pdf_path',    'column', 'agent-docs',       true, 'fn_enqueue_doc_backups: STORAGE SWEEP (agent-docs/accountant/weekly/)', null),
    ('accountant_spend_report.pdf_path',     'column', 'finance-reports',  true, 'fn_enqueue_doc_backups: STORAGE SWEEP (finance-reports/accountant/spend/)', null),
    ('finance_reports.html_path',            'column', 'finance-reports',  true, 'fn_enqueue_doc_backups: STORAGE SWEEP', null),
    ('finance_reports.xlsx_path',            'column', 'finance-reports',  true, 'fn_enqueue_doc_backups: STORAGE SWEEP', null),
    ('finance_reports.pdf_path',             'column', 'finance-reports',  true, 'fn_enqueue_doc_backups: STORAGE SWEEP', null),
    ('board_reports.pdf_path',               'column', 'reports',          true, 'fn_enqueue_doc_backups: STORAGE SWEEP (20 of 20 paths in reports)', null),
    ('exec_reports.pdf_path',                'column', 'reports',          true, 'fn_enqueue_doc_backups: STORAGE SWEEP (2 of 2 paths in reports)', null),
    ('it_incident.pdf_path',                 'column', 'agent-docs',       true, 'fn_enqueue_doc_backups: STORAGE SWEEP (rendered into agent-docs/it_engineer/incidents/)', null),
    ('ceo_daily_digest.pdf_path',            'column', 'agent-docs',       true, 'fn_enqueue_doc_backups: STORAGE SWEEP (rendered into agent-docs/ceo/daily_brief/)', null),
    ('ceo_weekly_report.pdf_path',           'column', 'agent-docs',       true, 'fn_enqueue_doc_backups: STORAGE SWEEP (rendered into agent-docs by resilience_ping renderPdfAndAttach)', null),
    ('marketing_post.media_paths',           'column', 'marketing-media',  true, 'fn_enqueue_doc_backups: STORAGE SWEEP (marketing-media/posts/<ingest_key>/, written by marketing_channels ingest)', null),

    -- ── (b) EXEMPT (not a file or not ours) ──
    ('doc_backups.dropbox_path',             'column', null, false, null, 'EXEMPT (not a file or not ours): the Dropbox destination of a backup, not a source'),
    ('pdpl_erase_files.storage_path',        'column', null, false, null, 'EXEMPT (not a file or not ours): the PDPL erasure ledger names files being REMOVED under a data subject''s request; fn_backup_sweep_objects never offers a file it names, so an erased file is never copied again'),
    ('pdpl_erase_files.dropbox_path',        'column', null, false, null, 'EXEMPT (not a file or not ours): the PDPL erasure ledger names Dropbox copies being REMOVED; never a source'),
    -- The knowledge source paths are LABELS: none of the sampled paths exists as a storage object or in
    -- the repository (review, 15 Sep 2026). The knowledge is the table rows, which the daily table export
    -- (fn_table_export_list) carries to Dropbox.
    ('support_knowledge.source_path',        'column', null, false, null, 'EXEMPT (not a file or not ours): a label naming where a knowledge entry came from, not a stored file; the entries themselves are table rows in the daily table export'),
    ('ops_knowledge.source_path',            'column', null, false, null, 'EXEMPT (not a file or not ours): a label naming where a knowledge entry came from, not a stored file; the entries themselves are table rows in the daily table export'),
    ('ceo_knowledge.source_path',            'column', null, false, null, 'EXEMPT (not a file or not ours): a label naming where a knowledge entry came from, not a stored file; the entries themselves are table rows in the daily table export'),
    ('cad_read_jobs.source_path',            'column', null, false, null, 'EXEMPT (not a file or not ours): a work-queue pointer to the customer''s original drawing in drawing-files, which is backed up through inquiries.drawing_file_path; the job holds no second copy'),
    ('demo-assets',                          'bucket', null, false, null, 'EXEMPT (not a file or not ours): a rehearsal fixture (one sample recording), never a record'),

    -- ── (c) EXEMPT (derived): no registry source. The one derived thing left out is a folder, not a
    -- source: signed-terms/registers/ (the customer register compliance_archive uploads to Dropbox
    -- itself), excluded in fn_backup_sweep_objects. The anonymised drawings are derived, but 2 of the 3
    -- redacted files have no original left (review, 15 Sep 2026), so they are kept like any other file. ──
    ('inquiries.drawing_redacted_paths',     'column', 'drawing-files', true, 'fn_enqueue_doc_backups: STORAGE SWEEP (drawing-files/redacted/; derived, but not every original survives)', null),
    ('drawing_redaction_runs.output_paths',  'column', 'drawing-files', true, 'fn_enqueue_doc_backups: STORAGE SWEEP (drawing-files/redacted/; derived, but not every original survives)', null)
$function$
;
revoke execute on function public.fn_backup_source_registry() from public, anon, authenticated;

commit;
