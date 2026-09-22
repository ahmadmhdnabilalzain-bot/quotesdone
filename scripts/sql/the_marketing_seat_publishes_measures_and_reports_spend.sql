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
--   marketing_ad_spend_day        Meta spend per campaign per day; each closed day goes to the accountant
--                                 through #836's fn_marketing_records_ad_spend (adspend.recorded)
--   fn_accountant_keeps_reported_ad_spend / fn_marketing_notes_ad_spend_booked   #836's two consumers,
--                                 REPLACED under their names with #836's contract kept whole (adspend.booked
--                                 carries recorded_handoff; marketing returns evidence.verified, which #836's
--                                 fn_marketing_closes_ad_spend_loops reads to close adspend.recorded), plus:
--                                 Meta's month total also kept in accountant_ad_spend_month (the invoice match)
--   fn_marketing_report_figures   #836's (p_from, p_to) body replaced with the same shape plus posts,
--                                 insights and measured connections -- what marketing.report carries
--   fn_table_export_list          + the five marketing tables, so they reach the daily export and Dropbox
--   fn_backup_source_registry     + the marketing-media bucket and marketing_post.media_paths
--
-- WHAT IT DELIBERATELY DOES NOT DO:
--   * Nothing posts publicly: the scheduler publishes only when app_secrets.marketing_golive is 'true'
--     (measured 'false'), and never a ZZ DEMO post; otherwise it records the payload it WOULD send (dry_run).
--   * No ad money is spent and no budget is raised: nothing here writes to Meta, and the dormant autopilot
--     (fn_ads_manage, ad_decision) is left exactly as it is.
--   * The reported spend is NOT booked to the ledger: the Meta invoice is the tax document and is already
--     booked by the expenses duty; booking the reported figure as well would count the spend twice. The
--     accountant keeps it as the REPORTED side of the invoice match, which is what adspend.booked confirms.
--   * The seat, its handoff kinds (marketing.report, adspend.recorded, adspend.booked), ad_spend_reported,
--     fn_marketing_records_ad_spend, fn_marketing_closes_ad_spend_loops and fn_marketing_tick are the seat
--     build (#836, the_company_gets_a_marketing_seat_that_reports_the_picture_to_the_ceo.sql); APPLY THAT FILE
--     FIRST. This file calls them and does not redefine the closer.
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

-- ── 10. AD SPEND: RECORD THE READ, REPORT EACH CLOSED CAMPAIGN DAY THROUGH THE SEAT'S ONE DOOR ────
-- p_rows: [{campaign_id, campaign_name, day, spend, currency, impressions, clicks}] as Graph returned them.
-- p_business_id is the business the account reported on the SAME read; a mismatch records nothing.
-- Each closed (Asia/Dubai) campaign day with spend goes to the accountant through fn_marketing_records_ad_spend
-- (the contract of the seat build, #836): source_ref '<account>:<campaign>:<day>', so a revised figure is a
-- revision of the same reference and an unchanged one is not sent twice (fn_seat_handoff dedupes on ref@amount).
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

  -- Never today (still moving), never a demo row, never a zero.
  for d in
    select s.* from public.marketing_ad_spend_day s
     where s.account_id = p_account and not s.is_demo and s.day < v_today and s.handed_off_at is null and s.spend > 0
     order by s.day, s.campaign_id
  loop
    update public.marketing_ad_spend_day set handed_off_at = now()
     where account_id = d.account_id and campaign_id = d.campaign_id and day = d.day;
    perform public.fn_marketing_records_ad_spend('meta', d.day, d.currency, d.spend,
      d.account_id || ':' || d.campaign_id || ':' || d.day, d.campaign_name, false);
    v_handoffs := v_handoffs + 1;
  end loop;
  return jsonb_build_object('ok', true, 'rows', v_n, 'handoffs', v_handoffs);
end $fn$;
revoke execute on function public.fn_marketing_ad_spend_record(text, text, jsonb, boolean) from public, anon, authenticated;

-- ── 11. adspend.recorded -> accountant (replaces #836's body under the same name, same contract) ────
-- #836's body, kept whole: record on ad_spend_reported (test money never), answer adspend.booked carrying
-- recorded_handoff, and wait for marketing to close it. ONE ADDITION: Meta's month total is also kept in
-- accountant_ad_spend_month, the REPORTED side the existing invoice match reads
-- (every_meta_invoice_is_matched_to_the_spend_meta_reported.sql). Nothing is booked to the ledger here:
-- the Meta invoice is booked by the expenses duty, and booking the reported figure too would count it twice.
create or replace function public.fn_accountant_keeps_reported_ad_spend(p_id bigint)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare a public.agent_actions; d jsonb; v_test boolean; v_fx numeric; v_aed numeric; v_recorded boolean := false;
        v_month date; v_pos jsonb; v_inv jsonb; v_bid bigint; v_meta_month numeric;
begin
  select * into a from public.agent_actions where id = p_id and kind = 'handoff';
  if not found or a.detail->>'type' is distinct from 'adspend.recorded' then
    raise exception 'fn_accountant_keeps_reported_ad_spend: % is not an adspend.recorded handoff', p_id;
  end if;
  d := a.detail;
  v_test := coalesce((d->>'test')::boolean, false) or coalesce(d->>'source_ref', '') ~* 'zz[ _-]?demo';
  v_fx := coalesce((select num_value from public.gl_settings where key = 'usd_to_aed'), 3.6725);
  v_aed := case d->>'currency' when 'AED' then (d->>'amount')::numeric
                               when 'USD' then round((d->>'amount')::numeric * v_fx, 2) end;
  v_month := date_trunc('month', (d->>'spend_date')::date)::date;

  if not v_test then
    insert into public.ad_spend_reported (source_ref, platform, spend_date, currency, amount, amount_aed, campaign_ref, handoff_id)
    values (d->>'source_ref', d->>'platform', (d->>'spend_date')::date, d->>'currency', (d->>'amount')::numeric, v_aed,
            nullif(d->>'campaign_ref', ''), p_id)
    on conflict (source_ref) do update
      set amount = excluded.amount, amount_aed = excluded.amount_aed, currency = excluded.currency,
          spend_date = excluded.spend_date, campaign_ref = excluded.campaign_ref, handoff_id = excluded.handoff_id,
          revisions = ad_spend_reported.revisions + 1, updated_at = now();
    v_recorded := true;
  end if;

  select jsonb_build_object('platform', d->>'platform', 'month', to_char(v_month, 'YYYY-MM'),
                            'reported_aed', coalesce(sum(amount_aed), 0), 'rows', count(*),
                            'rows_unconverted', count(*) filter (where amount_aed is null))
    into v_pos from public.ad_spend_reported
   where platform = d->>'platform' and spend_date >= v_month and spend_date < (v_month + interval '1 month')::date;
  if d->>'platform' = 'meta' then
    -- the addition: Meta's month total feeds the invoice match's reported side
    if v_recorded then
      select round(sum(amount_aed), 2) into v_meta_month from public.ad_spend_reported
       where platform = 'meta' and amount_aed is not null
         and spend_date >= v_month and spend_date < (v_month + interval '1 month')::date;
      if coalesce(v_meta_month, 0) > 0 then
        insert into public.accountant_ad_spend_month (month, reported_spend_aed, reported_at, updated_at)
        values (v_month, v_meta_month, now(), now())
        on conflict (month) do update set reported_spend_aed = excluded.reported_spend_aed, reported_at = now(), updated_at = now();
        -- the hourly snapshot (fn_accountant_ad_spend_snapshot) reads this; keep it saying the same figure
        update public.ad_spend_policy set month_spent_aed = v_meta_month, month_label = to_char(v_month, 'YYYY-MM'), updated_at = now()
         where policy_key = 'default' and to_char(v_month, 'YYYY-MM') = to_char(now() at time zone 'Asia/Dubai', 'YYYY-MM');
      end if;
    end if;
    begin
      v_inv := public.fn_accountant_ad_spend_figures(v_month);
      v_pos := v_pos || jsonb_build_object('invoiced_aed', v_inv->'invoiced_aed', 'meta_invoices', v_inv->'meta_invoices');
    exception when others then
      v_pos := v_pos || jsonb_build_object('invoiced_aed', null, 'invoiced_error', left(sqlerrm, 200));
    end;
  end if;

  v_bid := public.fn_seat_handoff('accountant', 'marketing', 'adspend.booked', 'ad_spend_reported', (d->>'source_ref') || '@' || (d->>'amount'),
    jsonb_build_object('recorded_handoff', p_id, 'source_ref', d->>'source_ref', 'amount', d->'amount', 'currency', d->>'currency',
                       'amount_aed', v_aed, 'recorded', v_recorded, 'test', v_test, 'demo', v_test, 'month_position', v_pos,
                       'books', case when v_test then 'Test money: not recorded and never booked.'
                                     else 'Recorded on the accountant''s ad-spend record. The ledger entry is made from the platform''s invoice when it reaches the expenses mailbox (fn_gl_sync_business); booking the reported figure as well would count the same spend twice.' end));
  return jsonb_build_object('waiting', 'marketing re-verification of adspend.booked ' || v_bid, 'recorded', v_recorded,
                            'test', v_test, 'amount_aed', v_aed, 'booked_handoff', v_bid, 'month_position', v_pos);
end $fn$;
revoke execute on function public.fn_accountant_keeps_reported_ad_spend(bigint) from public, anon, authenticated;

-- ── 12. adspend.booked -> marketing (replaces #836's body under the same name, same contract) ──────
-- #836's re-verification, kept whole: it returns evidence.verified, which fn_marketing_closes_ad_spend_loops
-- (defined by #836, run by fn_marketing_tick) reads to close the adspend.recorded named by recorded_handoff.
-- ONE ADDITION: a verified answer stamps booked_ack_at on the campaign day it answers.
create or replace function public.fn_marketing_notes_ad_spend_booked(p_id bigint)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare a public.agent_actions; d jsonb; r public.ad_spend_reported; v_ok boolean; v_why text;
begin
  select * into a from public.agent_actions where id = p_id and kind = 'handoff';
  if not found or a.detail->>'type' is distinct from 'adspend.booked' then
    raise exception 'fn_marketing_notes_ad_spend_booked: % is not an adspend.booked handoff', p_id;
  end if;
  d := a.detail;
  select * into r from public.ad_spend_reported where source_ref = d->>'source_ref';
  if coalesce((d->>'recorded')::boolean, false) then
    v_ok := r.source_ref is not null and r.amount = (d->>'amount')::numeric;
    v_why := case when r.source_ref is null then 'the accountant said recorded and no row exists'
                  when not v_ok then 'the accountant''s row says ' || r.amount || ', marketing reported ' || (d->>'amount') end;
  else
    v_ok := coalesce((d->>'test')::boolean, false);
    v_why := case when not v_ok then 'the accountant did not record real spend' end;
  end if;
  if v_ok then
    update public.marketing_ad_spend_day set booked_ack_at = now()
     where account_id || ':' || campaign_id || ':' || day = d->>'source_ref' and spend = (d->>'amount')::numeric;
  end if;
  return jsonb_build_object('verified', v_ok, 'reason', v_why, 'recorded_handoff', d->'recorded_handoff');
end $fn$;
revoke execute on function public.fn_marketing_notes_ad_spend_booked(bigint) from public, anon, authenticated;

-- ── 13. THE DAILY REPORT'S FIGURES (replaces #836's body; same signature and shape) ─────────────────
-- #836: "the publishing, analytics and inbox builds replace this routine to add their own figures; the shape
-- (headline, measured, not_measured) stays." fn_marketing_report_tick reads posts_published,
-- ad_spend_reported_aed, conversations_handed_to_founder and customer_requests_posted, so those keys stay.
-- Posts are now read from marketing_post (the store this build owns); social_posts is the June-August history.
create or replace function public.fn_marketing_report_figures(p_from timestamptz, p_to timestamptz)
returns jsonb language plpgsql stable security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_posts int; v_posts_ever int; v_spend jsonb; v_spend_aed numeric; v_unconv int; v_asked int; v_inq numeric; v_head text;
        v_sched int; v_held int; v_failed int; v_stuck int; v_live boolean; v_ins jsonb; v_conn jsonb; v_ins_days int;
begin
  select count(*) filter (where published_at >= p_from and published_at < p_to), count(*)
    into v_posts, v_posts_ever from public.marketing_post where status = 'published' and not is_demo;
  select count(*) filter (where status = 'scheduled' and scheduled_at >= p_to and scheduled_at < p_to + interval '7 days'),
         count(*) filter (where status = 'scheduled' and scheduled_at <= p_to and dry_run is not null),
         count(*) filter (where status = 'failed' and updated_at >= p_from and updated_at < p_to),
         count(*) filter (where status = 'publishing' and updated_at < p_to - interval '30 minutes')
    into v_sched, v_held, v_failed, v_stuck from public.marketing_post where not is_demo;
  v_live := coalesce((select lower(value) = 'true' from public.app_secrets where key = 'marketing_golive'), false);
  select coalesce(jsonb_object_agg(platform, aed), '{}'::jsonb), coalesce(sum(aed), 0), coalesce(sum(unconv), 0)
    into v_spend, v_spend_aed, v_unconv
    from (select platform, sum(amount_aed) aed, count(*) filter (where amount_aed is null) unconv
            from public.ad_spend_reported where spend_date >= (p_from at time zone 'Asia/Dubai')::date
                                           and spend_date < (p_to at time zone 'Asia/Dubai')::date
           group by platform) s;
  select count(*) into v_asked from public.notifications
   where kind = 'social_human_request' and created_at >= p_from and created_at < p_to;
  v_inq := public.fn_ceo_plan_measure('inquiries_posted', p_from, p_to)::numeric;
  select coalesce(jsonb_object_agg(k, v), '{}'::jsonb), count(distinct d) into v_ins, v_ins_days from (
    select i.platform || '.' || i.metric k, sum(i.value) v, max(i.day) d
      from public.marketing_insight_day i
     where i.object_type <> 'post' and i.day >= (p_from at time zone 'Asia/Dubai')::date - 1
       and i.day < (p_to at time zone 'Asia/Dubai')::date
     group by 1) x;
  v_conn := public.fn_marketing_connection_status();
  v_head := format('%s post(s) published, %s scheduled for the next 7 days%s, AED %s ad spend reported, %s conversation(s) handed to the founder, %s customer request(s) posted.',
                   v_posts, v_sched, case when not v_live and v_held > 0 then format(' (%s due and held: publishing is off)', v_held) else '' end,
                   v_spend_aed, v_asked, coalesce(v_inq::text, 'unmeasured'));
  return jsonb_build_object(
    'headline', v_head,
    'measured', jsonb_build_object(
      'posts_published', v_posts, 'posts_published_ever', v_posts_ever, 'posts_scheduled_next_7_days', v_sched,
      'posts_due_held_by_switch', v_held, 'posts_failed', v_failed, 'posts_stuck_publishing', v_stuck, 'publishing_live', v_live,
      'ad_spend_reported_aed', v_spend_aed, 'ad_spend_by_platform_aed', v_spend, 'ad_spend_rows_unconverted', v_unconv,
      'conversations_handed_to_founder', v_asked, 'customer_requests_posted', v_inq,
      'insights', v_ins, 'connections_all_ok', v_conn->'all_ok',
      'connections_failing', coalesce((select jsonb_agg(c->'check') from jsonb_array_elements(v_conn->'checks') c where not (c->>'ok')::boolean), '[]'::jsonb),
      'connections_measured_at', v_conn->'oldest_measurement'),
    'not_measured', to_jsonb(array_remove(array[
      case when v_ins_days = 0 then 'followers, reach and engagement per channel: no insight was pulled for the window yet' end,
      case when coalesce((v_conn->>'never_measured')::boolean, true) then 'channel access: the access check has not run yet' end,
      'social conversations answered: no social inbox record is built yet',
      'search rankings and organic traffic: no SEO reader is built yet'], null)),
    'basis', 'Posts: marketing_post (published_at in the window; scheduled and held from its status and dry_run). Spend: ad_spend_reported by spend_date (Asia/Dubai), in AED at gl_settings usd_to_aed. Insights: marketing_insight_day, page and account metrics summed over the window. Connections: marketing_connection_check as last measured. Handed to the founder: notifications of kind social_human_request. Customer requests: fn_ceo_plan_measure(inquiries_posted), demo excluded. Window: the 24 hours before the report.');
end $fn$;
revoke execute on function public.fn_marketing_report_figures(timestamptz, timestamptz) from public, anon, authenticated;

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

-- ── 16. THE DAILY TABLE EXPORT: the five marketing tables (fn_table_export_list) ─────────────────────
-- Copied from its current definition (we_back_up_the_extra_stuff_only_unless_they_got_updated.sql) with the
-- marketing tables added under subject 'marketing'. All are far below the 64 MB change-tracking threshold,
-- so each is a full copy every day; the ZZ DEMO rows are left out by fn_table_export_filter (is_demo).
create or replace function public.fn_table_export_list()
returns table(table_name text, subject text, change_log text)
language sql stable set search_path to 'public', 'pg_temp' as $fn$
  select v.t, v.s,
         (select 'table_export_change' from public.table_export_change_tracked x where x.table_name = v.t)
  from (values
    ('customers','customer'), ('customer_preference','customer'), ('customer_calls','customer'), ('projects','customer'),
    ('leads','supplier'), ('lead_category','supplier'), ('lead_subcategory','supplier'), ('supplier_capabilities','supplier'),
    ('supplier_catalog','supplier'), ('supplier_product','supplier'), ('supplier_product_variant','supplier'),
    ('supplier_capability_confirmation','supplier'), ('supplier_collaboration','supplier'), ('supplier_collaboration_event','supplier'),
    ('supplier_negotiation_policy','supplier'), ('supplier_screening_hit','supplier'), ('supplier_lead_intake','supplier'),
    ('doc_reviews','supplier'), ('licence_renewal_ask','supplier'), ('outreach','supplier'), ('company_registration','company'),
    ('inquiries','inquiry'), ('inquiry_intake','inquiry'), ('inquiry_matches','inquiry'), ('inquiry_requirement','inquiry'),
    ('inquiry_cancellations','inquiry'), ('inquiry_supplier_brief','inquiry'), ('inquiry_state_audit','inquiry'),
    ('inquiry_gate','inquiry'), ('inquiry_answer','inquiry'), ('inquiry_answer_document','inquiry'), ('inquiry_answer_scope','inquiry'),
    ('inquiry_workstream','inquiry'), ('inquiry_workstream_group','inquiry'), ('inquiry_workstream_requirement','inquiry'),
    ('inquiry_trade_candidate','inquiry'), ('inquiry_trade_clarification','inquiry'), ('inquiry_scope_disposition','inquiry'),
    ('rfq_archives','inquiry'), ('rfq_clarification','inquiry'),
    ('quotes','quote'), ('quote_items','quote'), ('quote_reviews','quote'), ('quote_review_messages','quote'),
    ('quote_requirements','quote'), ('quote_committed_items','quote'), ('quote_comparisons','quote'), ('quote_spec_hold','quote'),
    ('spec_alternative_offer','quote'), ('po_orders','quote'), ('po_vendors','quote'), ('questions','quote'), ('reviews','quote'),
    ('category_specs','quote rules'), ('category_quote_specs','quote rules'),
    ('transactions','payment'), ('reveal_invoices','payment'), ('supplier_dues','payment'), ('refunds','payment'),
    ('refund_case','payment'), ('refund_incident','payment'), ('refund_ceo_review','payment'), ('refund_ceo_check','payment'),
    ('refund_ladder_evidence','payment'), ('refund_status_transition','payment'), ('stripe_events','payment'),
    ('stripe_payout','payment'), ('stripe_dispute','payment'), ('charge_audit','payment'), ('pricing_config','payment'),
    ('gl_journal','accounting'), ('gl_journal_lines','accounting'), ('gl_expense_map','accounting'), ('expenses','accounting'),
    ('expense_entries','accounting'), ('bank_statement_intake','accounting'), ('bank_statement_line','accounting'),
    ('accountant_month_close','accounting'), ('accountant_issued_document','accounting'),
    ('messages','conversation'), ('chat_threads','conversation'), ('conversation_archive','conversation'),
    ('inbound_messages','conversation'), ('contact_messages','conversation'), ('complaint_tickets','conversation'),
    ('support_case','conversation'), ('support_notification','conversation'), ('support_document_intake','conversation'),
    ('wa_messages','conversation'), ('wa_conversation','conversation'), ('wa_turn','conversation'),
    ('wa_document_intake','conversation'), ('notifications','conversation'), ('agent_chats','conversation'),
    ('legal_reviews','legal'), ('pdpl_requests','legal'), ('pdpl_erase_files','legal'), ('email_suppressions','legal'),
    ('founder_instruction','decision'), ('company_policy_decision','decision'),
    ('kb_chunks','knowledge'), ('dept_library','knowledge'), ('ops_knowledge','knowledge'), ('agent_knowledge','knowledge'),
    ('sales_knowledge','knowledge'), ('ceo_knowledge','knowledge'), ('support_knowledge','knowledge'),
    ('accountant_knowledge','knowledge'), ('it_engineer_knowledge','knowledge'), ('employee_knowledge','knowledge'),
    ('marketing_post','marketing'), ('marketing_connection_check','marketing'), ('marketing_insight_day','marketing'),
    ('marketing_ad_spend_day','marketing'), ('marketing_duty_run','marketing'),
    ('table_export_change','backup')
  ) v(t, s)
$fn$;
revoke execute on function public.fn_table_export_list() from public, anon, authenticated;

commit;
