-- A MONTH OF POSTS IS APPROVED ONCE AND GOES OUT EXACTLY AS APPROVED (23 Sep 2026; seat: marketing).
--
-- Founder, founder_instruction 865: a month-1 social campaign of 12 founder-made videos, scheduled
-- "perfectly" through Postiz by the marketing seat. Founder, founder_instruction 866: "I don't need to approve
-- a post by post. So we work on monthly basis ... you show it to me in an organized PDF. I say, OK, approve.
-- That's it ... I'm expecting everything to be perfect in terms of what captions was used, what hashtag was
-- used, everything, literally." Founder, 23 Sep 2026: TikTok is now connected in Postiz and is a platform.
--
-- WHAT WAS MEASURED (audit of 23 Sep 2026, read-only; production has 0 marketing_post rows):
--   * marketing_post holds ONE English + ONE Arabic text and publishing JOINED them for every channel, so an
--     X post would overflow; no hashtags, alt text, title, first comment, cover or post type existed.
--   * Giving a post a time WAS its approval: scheduled_at set -> status 'scheduled' -> published when due.
--   * The ZZ DEMO rule held one direction only (is_demo => text starts 'ZZ DEMO'); a post whose TEXT said
--     ZZ DEMO with is_demo false would have gone live.
--   * youtube was refused by the channels rule although Postiz has it connected (22 Sep 2026).
--   * A post Postiz accepted whose reply was lost was marked failed and never re-checked; a post stuck in
--     'publishing' after a crash stayed there for ever.
--
-- WHAT THIS BUILDS:
--   marketing_campaign             one month: key, theme, month, ORGANIC ONLY (spend_policy), and the founder's
--                                  approval, which binds to a SHA-256 of the exact content (approved_hash)
--   marketing_post (+ columns)     campaign_id, the Dubai wall-clock time beside the UTC one, the video and key
--                                  frame with their sha256, CTA link, rationale, music; youtube allowed;
--                                  status 'unconfirmed' (Postiz may have it: reconcile before anything else)
--   marketing_post_variant         one row per platform post (a thread on X is seq 1, 2): caption, hashtags,
--                                  body = the EXACT text sent (a generated column; the PDF and the publisher
--                                  both read it, so they cannot differ), alt text, title, first comment,
--                                  cover, post type reel/short/post/video
--   fn_marketing_variant_problems  the ONE hook the platform specs plug into (see PLATFORM LIMITS below)
--   fn_marketing_campaign_hash     the content hash printed on the approval PDF
--   fn_marketing_calendar_due / fn_marketing_calendar_sent   the monthly calendar EMAIL (PDF + xlsx, clickable
--                                  video links) through the outbox, founder_mail_policy kind marketing_calendar,
--                                  Reply-To calendar+<unguessable token>@mail.quotesdone.com
--   fn_marketing_calendar_reply    HIS REPLY "approve" (resend_inbound) is the approval: founder address + SPF/DKIM/
--                                  DMARC pass + this calendar's token + unchanged hash + month not over
--   notifications.reply_to         the per-email Reply-To send_outbox now honours (our inbound subdomain only)
--   fn_marketing_campaign_state
--   fn_marketing_post_publish_refusal + trigger   THE DATABASE REFUSES to move a post towards Postiz unless
--                                  its campaign is approved for exactly the current content, marketing_golive
--                                  is 'true', the platform specs pass, and nothing about it says ZZ DEMO
--   fn_marketing_calendar_load     loads a whole month in ONE transaction, idempotently
--   fn_table_export_list           + the two new tables
--
-- THE FOUNDER'S ONE ACTION (founder_instructions 866, 871, 872): each month the seat emails him the calendar --
-- a table on the company PDF template (date, Dubai time, platform, video name, a clickable video link, caption
-- as used, hashtags in their own column, the post's link) plus the same rows as a spreadsheet, both rendered
-- from the loaded rows and carrying the content hash. He replies "approve". Nothing else approves a month.
--
-- APPROVAL: EDITING VOIDS IT, IT IS NOT MADE IMPOSSIBLE. The approval is the hash of the content he saw; the
-- publish gate recomputes the hash at the moment of publishing and refuses on any difference. So a corrected
-- typo, a moved time or a swapped video leaves the whole month unapproved until he approves the new PDF --
-- what goes out is always byte-for-byte what he approved, and a mistake he spots is still fixable. Making
-- edits impossible would force a delete-and-reload for every typo and buy nothing the hash does not.
-- The void is computed, not stored, so no trigger can miss an edit path (a direct UPDATE included).
--
-- PLATFORM LIMITS ARE NOT HARD-CODED HERE (coordination, founder_instruction 869): a sibling build owns
-- marketing_platform_spec (caption, hashtag and title limits from the official docs) and its validation
-- routine public.fn_marketing_platform_spec_problems(platform, post_type, body, hashtags, title, alt_text,
-- first_comment) -> text[]. fn_marketing_variant_problems calls it when it exists; until it exists no limit is
-- checked on load and the publish gate REFUSES (platform_specs_not_loaded), so nothing unchecked goes out.
--
-- ORGANIC ONLY: spend_policy is 'organic_only' by constraint and nothing here, in marketing_channels, or in
-- the Postiz payload can buy reach. Measured 23 Sep 2026: the ad autopilot fn_ads_manage has no cron job, no
-- resilience step and no edge caller; nothing in the seat POSTs to Graph.
--
-- WHAT IT DELIBERATELY DOES NOT DO:
--   * marketing_golive stays 'false'; nothing is published by this file.
--   * (TikTok: first ruled out, then connected in Postiz and added the same day, 23 Sep 2026 -- a platform like the rest.)
--   * fn_marketing_post_ingest (the one-post door) is unchanged: a post it stores has no campaign, so the gate
--     refuses to publish it; it is a draft store until it is loaded as part of a campaign.
--
-- APPLY AFTER the_marketing_seat_publishes_measures_and_reports_spend.sql and
-- the_marketing_seat_writes_articles_and_drafts_linkedin_outreach.sql (whose fn_table_export_list this extends).
-- Proved by a_month_of_posts_is_approved_once_and_goes_out_exactly_as_approved_probe.sql (aborted transaction),
-- supabase/functions/_shared/marketing_channels.test.ts and scripts/checks/marketing_never_posts_or_spends_by_default.test.mjs.
--
--   node scripts/apply_sql.mjs scripts/sql/a_month_of_posts_is_approved_once_and_goes_out_exactly_as_approved.sql --apply --ddl --seat marketing

begin;

-- ── 1. THE CAMPAIGN (ONE MONTH) ──────────────────────────────────────────────────────────────────
create table if not exists public.marketing_campaign (
  id                bigint generated always as identity primary key,
  campaign_key      text not null unique check (campaign_key ~ '^[a-z0-9][a-z0-9-]{2,80}$'),
  theme             text not null check (btrim(theme) <> ''),
  title             text,
  month             date not null check (month = date_trunc('month', month)::date),
  spend_policy      text not null default 'organic_only' check (spend_policy = 'organic_only'),
  is_demo           boolean not null default false,
  -- the calendar email last sent to him: its PDF and spreadsheet, the content hash it carries, and the
  -- unguessable token his reply must carry back (Reply-To calendar+<token>@mail.quotesdone.com and the subject)
  calendar_pdf_path  text,
  calendar_xlsx_path text,
  calendar_hash      text check (calendar_hash ~ '^[0-9a-f]{64}$'),
  calendar_token     text unique check (calendar_token ~ '^[0-9a-f]{32}$'),
  calendar_sent_at   timestamptz,
  calendar_notification_id bigint,
  approved_by        text check (approved_by = 'founder'),
  approved_at        timestamptz,
  approved_hash      text check (approved_hash ~ '^[0-9a-f]{64}$'),
  approved_message_id text,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  constraint marketing_campaign_approval_is_whole check (
    (approved_by is null) = (approved_at is null) and (approved_at is null) = (approved_hash is null)
    and (approved_at is null) = (approved_message_id is null)),
  -- he approves what he was shown: the calendar email of exactly this content
  constraint marketing_campaign_approved_what_the_calendar_showed check (approved_hash is null or approved_hash = calendar_hash),
  constraint marketing_campaign_demo_both_ways check (
    is_demo = ((campaign_key || ' ' || theme || ' ' || coalesce(title, '')) ~* 'zz[ _-]?demo'))
);
comment on table public.marketing_campaign is
  'One month of organic social posts. The founder approves the whole month once, by replying "approve" to the monthly calendar email (fn_marketing_calendar_reply); the approval binds to fn_marketing_campaign_hash, so any later edit voids it until he approves again.';
alter table public.marketing_campaign enable row level security;
drop policy if exists marketing_campaign_service_role_only on public.marketing_campaign;
create policy marketing_campaign_service_role_only on public.marketing_campaign as permissive for all to public using (false) with check (false);
revoke all on public.marketing_campaign from anon, authenticated;

-- ── 2. THE POST: CAMPAIGN, DUBAI TIME, VIDEO, YOUTUBE, 'unconfirmed', ZZ DEMO BOTH WAYS ────────────
alter table public.marketing_post
  add column if not exists campaign_id        bigint references public.marketing_campaign(id),
  add column if not exists scheduled_local    timestamp,
  add column if not exists video_path         text,
  add column if not exists video_sha256       text check (video_sha256 ~ '^[0-9a-f]{64}$'),
  add column if not exists cover_path         text,
  add column if not exists cover_sha256       text check (cover_sha256 ~ '^[0-9a-f]{64}$'),
  add column if not exists cta_url            text check (cta_url ~ '^https://'),
  add column if not exists rationale          text,
  add column if not exists music              jsonb,
  add column if not exists publish_started_at timestamptz;
create index if not exists marketing_post_campaign_idx on public.marketing_post (campaign_id);

alter table public.marketing_post drop constraint if exists marketing_post_channels_check;
alter table public.marketing_post add constraint marketing_post_channels_check
  check (cardinality(channels) > 0 and channels <@ array['facebook', 'instagram', 'linkedin', 'x', 'youtube', 'tiktok']);
alter table public.marketing_post drop constraint if exists marketing_post_status_check;
alter table public.marketing_post add constraint marketing_post_status_check
  check (status in ('draft', 'scheduled', 'publishing', 'unconfirmed', 'published', 'failed', 'cancelled'));
alter table public.marketing_post drop constraint if exists marketing_post_local_time_is_dubai;
alter table public.marketing_post add constraint marketing_post_local_time_is_dubai
  check (scheduled_local is null or scheduled_local = (scheduled_at at time zone 'Asia/Dubai'));
-- The other direction of the ZZ DEMO rule (marketing_post_demo_is_marked holds is_demo => 'ZZ DEMO%').
alter table public.marketing_post drop constraint if exists marketing_post_demo_text_is_flagged;
alter table public.marketing_post add constraint marketing_post_demo_text_is_flagged
  check (is_demo or (text_en || ' ' || text_ar || ' ' || coalesce(title, '')) !~* 'zz[ _-]?demo');

-- ── 3. THE VARIANT: ONE PLATFORM POST, EXACTLY AS SENT ────────────────────────────────────────────
-- The text sent is the caption, a blank line, then the hashtags each prefixed '#'. One function, used by
-- the generated column, so the publisher, the PDF and the hash all read the same stored text.
create or replace function public.fn_marketing_variant_text(p_caption text, p_hashtags text[])
returns text language sql immutable set search_path to 'public', 'pg_temp' as $fn$
  select btrim(p_caption) || case when cardinality(coalesce(p_hashtags, '{}')) > 0
                                  then E'\n\n#' || array_to_string(p_hashtags, ' #') else '' end
$fn$;
revoke execute on function public.fn_marketing_variant_text(text, text[]) from public, anon, authenticated;

create or replace function public.fn_marketing_hashtags_ok(p text[])
returns boolean language sql immutable set search_path to 'public', 'pg_temp' as $fn$
  select coalesce(bool_and(h ~ '^[^[:space:]#]{1,100}$'), true) from unnest(coalesce(p, '{}')) h
$fn$;
revoke execute on function public.fn_marketing_hashtags_ok(text[]) from public, anon, authenticated;

create table if not exists public.marketing_post_variant (
  id            bigint generated always as identity primary key,
  post_id       bigint not null references public.marketing_post(id) on delete cascade,
  platform      text not null check (platform in ('facebook', 'instagram', 'linkedin', 'x', 'youtube', 'tiktok')),
  seq           smallint not null default 1 check (seq between 1 and 5),
  language      text not null check (language in ('en', 'ar', 'bi')),
  post_type     text not null check (post_type in ('reel', 'short', 'post', 'video')),
  caption       text not null check (btrim(caption) <> ''),
  hashtags      text[] not null default '{}' check (public.fn_marketing_hashtags_ok(hashtags)),
  body          text generated always as (public.fn_marketing_variant_text(caption, hashtags)) stored,
  alt_text      text,
  title         text,
  first_comment text,
  cover_path    text,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  unique (post_id, platform, seq),
  -- Arabic letters present (U+0600..U+06FF) wherever Arabic is claimed: question marks are refused here.
  constraint marketing_post_variant_arabic_is_arabic check (language = 'en' or caption ~ '[؀-ۿ]'),
  -- Which kinds each platform takes (reel vs post is chosen by the loader from the media: a video is a reel).
  constraint marketing_post_variant_type_fits_platform check (
    (platform = 'instagram' and post_type in ('reel', 'post')) or
    (platform = 'youtube'   and post_type in ('short', 'video')) or
    (platform = 'facebook'  and post_type in ('reel', 'video', 'post')) or
    (platform in ('linkedin', 'x') and post_type in ('video', 'post')) or
    (platform = 'tiktok'    and post_type = 'video')),
  constraint marketing_post_variant_youtube_has_a_title check (platform <> 'youtube' or btrim(coalesce(title, '')) <> '')
);
comment on table public.marketing_post_variant is
  'One platform post of a marketing_post, exactly as sent: body is caption + hashtags (generated), never the EN+AR joined text of the old publisher. A thread on X is seq 1, 2. Limits are checked by fn_marketing_variant_problems through marketing_platform_spec.';
alter table public.marketing_post_variant enable row level security;
drop policy if exists marketing_post_variant_service_role_only on public.marketing_post_variant;
create policy marketing_post_variant_service_role_only on public.marketing_post_variant as permissive for all to public using (false) with check (false);
revoke all on public.marketing_post_variant from anon, authenticated;

-- ── 4. THE ONE HOOK THE PLATFORM SPECS PLUG INTO ─────────────────────────────────────────────────
-- Returns the problems of a variant against the platform specs. NULL means the spec routine does not exist
-- yet (unchecked) -- the publish gate treats that as a refusal, the loader as "not known to overflow".
create or replace function public.fn_marketing_variant_problems(v public.marketing_post_variant)
returns text[] language plpgsql stable security definer set search_path to 'public', 'pg_temp' as $fn$
declare r text[];
begin
  if to_regprocedure('public.fn_marketing_platform_spec_problems(text,text,text,text[],text,text,text)') is null then
    return null;
  end if;
  execute 'select public.fn_marketing_platform_spec_problems($1,$2,$3,$4,$5,$6,$7)'
    into r using v.platform, v.post_type, v.body, v.hashtags, v.title, v.alt_text, v.first_comment;
  return coalesce(r, '{}');
end $fn$;
revoke execute on function public.fn_marketing_variant_problems(public.marketing_post_variant) from public, anon, authenticated;

-- ── 5. THE CONTENT HASH (what the PDF prints and the approval binds to) ────────────────────────────
-- Everything that reaches a platform: each live post's time (UTC), platforms, video and key frame by sha256,
-- CTA, and each variant's exact body, title, alt text, first comment, cover and type. Cancelled posts are
-- not part of the month. The field separator is U+001F, which no caption carries.
create or replace function public.fn_marketing_campaign_hash(p_campaign_id bigint)
returns text language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  select encode(sha256(convert_to(
    (select c.campaign_key || chr(31) || c.spend_policy from public.marketing_campaign c where c.id = p_campaign_id)
    || chr(30) || coalesce((
      select string_agg(concat_ws(chr(31), p.ingest_key, to_char(p.scheduled_at at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
               array_to_string(p.channels, ','), p.video_path, p.video_sha256, p.cover_path, p.cover_sha256,
               array_to_string(p.media_paths, ','), p.cta_url, p.is_demo::text,
               (select string_agg(concat_ws(chr(31), v.platform, v.seq::text, v.language, v.post_type, v.body, v.title,
                                            v.alt_text, v.first_comment, v.cover_path), chr(29) order by v.platform, v.seq)
                  from public.marketing_post_variant v where v.post_id = p.id)), chr(30) order by p.scheduled_at, p.ingest_key)
        from public.marketing_post p where p.campaign_id = p_campaign_id and p.status <> 'cancelled'), ''),
    'UTF8')), 'hex')
$fn$;
revoke execute on function public.fn_marketing_campaign_hash(bigint) from public, anon, authenticated;

create or replace function public.fn_marketing_campaign_state(p_campaign_key text)
returns jsonb language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  select jsonb_build_object('campaign_key', c.campaign_key, 'theme', c.theme, 'month', c.month, 'spend_policy', c.spend_policy,
           'current_hash', h.v, 'calendar_hash', c.calendar_hash, 'calendar_sent_at', c.calendar_sent_at,
           'calendar_is_current', c.calendar_hash = h.v,
           'approved', c.approved_hash = h.v, 'approved_by', c.approved_by, 'approved_at', c.approved_at,
           'approved_message_id', c.approved_message_id,
           'voided_by_an_edit', c.approved_hash is not null and c.approved_hash <> h.v,
           'posts', (select count(*) from public.marketing_post p where p.campaign_id = c.id and p.status <> 'cancelled'),
           'first_post_at', (select min(p.scheduled_at) from public.marketing_post p where p.campaign_id = c.id and p.status <> 'cancelled'),
           'variants', (select count(*) from public.marketing_post_variant v join public.marketing_post p on p.id = v.post_id
                         where p.campaign_id = c.id and p.status <> 'cancelled'))
    from public.marketing_campaign c, lateral (select public.fn_marketing_campaign_hash(c.id) v) h
   where c.campaign_key = p_campaign_key
$fn$;
revoke execute on function public.fn_marketing_campaign_state(text) from public, anon, authenticated;

-- ── 5b. THE MONTHLY CALENDAR EMAIL AND HIS REPLY (founder_instructions 871, 872) ──────────────────────
-- Founder mail goes through founder_mail_policy: these two kinds are registered, allowed to email, owned
-- by marketing. His address is app_secrets.admin_emails' first entry, as fn_notify_founder reads it.
insert into public.founder_mail_policy (kind, allowed_to_email, reason, owner_role, updated_at) values
  ('marketing_calendar', true, 'Founder instructions 866, 871, 872 (23 Sep 2026): the month''s social calendar (PDF + spreadsheet, clickable video links) is emailed to him once per month and whenever it changes; replying "approve" is his single approval action for the month.', 'marketing', now()),
  ('marketing_calendar_reply', true, 'Founder instruction 872 (23 Sep 2026): the answer to his reply to the monthly calendar -- one confirmation when it is approved, or plainly what to do when the reply could not approve it.', 'marketing', now())
on conflict (kind) do update set allowed_to_email = excluded.allowed_to_email, reason = excluded.reason,
       owner_role = excluded.owner_role, updated_at = now();

create or replace function public.fn_marketing_founder_email()
returns text language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  select lower(btrim(coalesce(nullif(split_part((select value from public.app_secrets where key = 'admin_emails'), ',', 1), ''),
                              'management@quotesdone.com')))
$fn$;
revoke execute on function public.fn_marketing_founder_email() from public, anon, authenticated;

-- One founder email of a registered marketing kind, through the outbox. Refused when the policy says no.
create or replace function public.fn_marketing_mail_founder(p_kind text, p_subject text, p_body text,
                                                           p_attachments jsonb default null, p_reply_to text default null)
returns bigint language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_id bigint;
begin
  if not coalesce((select allowed_to_email from public.founder_mail_policy where kind = p_kind), false) then
    raise exception 'founder_mail_policy does not allow % to email the founder', p_kind;
  end if;
  insert into public.notifications (type, kind, to_email, to_role, subject, body, status, channel, attachments, reply_to, requested_by)
  values (p_kind, p_kind, public.fn_marketing_founder_email(), 'founder', p_subject, p_body, 'queued', 'email',
          p_attachments, p_reply_to, 'marketing')
  returning id into v_id;
  return v_id;
end $fn$;
revoke execute on function public.fn_marketing_mail_founder(text, text, text, jsonb, text) from public, anon, authenticated;

-- Campaigns whose calendar email is owed: real (never ZZ DEMO), its month not over, content different from
-- the last calendar sent and not already approved as it stands, and quiet for 30 minutes (a month being
-- loaded or corrected is not mailed half-way). marketing_channels renders and sends each one.
create or replace function public.fn_marketing_calendar_due()
returns table(campaign_key text, current_hash text)
language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  select c.campaign_key, h.v
    from public.marketing_campaign c, lateral (select public.fn_marketing_campaign_hash(c.id) v) h
   where not c.is_demo
     and now() < ((c.month + interval '1 month')::timestamp at time zone 'Asia/Dubai')
     and exists (select 1 from public.marketing_post p where p.campaign_id = c.id and p.status <> 'cancelled')
     and h.v is distinct from c.calendar_hash
     and h.v is distinct from c.approved_hash
     and greatest(c.updated_at,
                  (select max(p.updated_at) from public.marketing_post p where p.campaign_id = c.id),
                  (select max(v.updated_at) from public.marketing_post_variant v join public.marketing_post p on p.id = v.post_id
                    where p.campaign_id = c.id)) < now() - interval '30 minutes'
$fn$;
revoke execute on function public.fn_marketing_calendar_due() from public, anon, authenticated;

-- The rendered calendar (PDF + xlsx in agent-docs, from the rows whose hash they print) is mailed to him.
-- A fresh unguessable token per email: a reply to any earlier calendar email no longer matches.
create or replace function public.fn_marketing_calendar_sent(p_campaign_key text, p_hash text, p_pdf_path text,
                                                            p_xlsx_path text, p_subject text, p_body text)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare c public.marketing_campaign; v_token text := encode(extensions.gen_random_bytes(16), 'hex'); v_nid bigint; v_att jsonb;
begin
  select * into c from public.marketing_campaign where campaign_key = p_campaign_key for update;
  if not found then return jsonb_build_object('ok', false, 'error', 'no_such_campaign'); end if;
  if c.is_demo then return jsonb_build_object('ok', false, 'error', 'demo_campaign_never_mailed'); end if;
  if p_hash is distinct from public.fn_marketing_campaign_hash(c.id) then
    return jsonb_build_object('ok', false, 'error', 'content_changed_while_rendering', 'message', 'Render the calendar again.');
  end if;
  v_att := jsonb_build_array(
    jsonb_build_object('bucket', 'agent-docs', 'path', p_pdf_path, 'filename', 'QuotesDone social calendar ' || to_char(c.month, 'YYYY-MM') || '.pdf'))
    || case when p_xlsx_path is null then '[]'::jsonb else jsonb_build_array(
    jsonb_build_object('bucket', 'agent-docs', 'path', p_xlsx_path, 'filename', 'QuotesDone social calendar ' || to_char(c.month, 'YYYY-MM') || '.xlsx')) end;
  v_nid := public.fn_marketing_mail_founder('marketing_calendar',
    left(p_subject, 200) || ' [ref ' || v_token || ']', p_body, v_att, 'calendar+' || v_token || '@mail.quotesdone.com');
  update public.marketing_campaign
     set calendar_pdf_path = p_pdf_path, calendar_xlsx_path = p_xlsx_path, calendar_hash = p_hash, calendar_token = v_token,
         calendar_sent_at = now(), calendar_notification_id = v_nid,
         -- an approval of OLDER content is already void (the gate compares hashes); clear it so the record says so
         approved_by = case when approved_hash = p_hash then approved_by end,
         approved_at = case when approved_hash = p_hash then approved_at end,
         approved_message_id = case when approved_hash = p_hash then approved_message_id end,
         approved_hash = case when approved_hash = p_hash then approved_hash end,
         updated_at = now()
   where id = c.id;
  return jsonb_build_object('ok', true, 'notification_id', v_nid, 'hash', p_hash);
end $fn$;
revoke execute on function public.fn_marketing_calendar_sent(text, text, text, text, text, text) from public, anon, authenticated;

-- HIS REPLY. resend_inbound reads the mail (token from the Reply-To tag or the subject, the From address, the
-- receiving server's SPF/DKIM/DMARC verdict through _shared/suppression_policy.ts fromDomainAuthenticated, and
-- the intent through _shared/marketing_calendar_mail.ts replyIntent) and hands it here. The month is approved
-- ONLY when all hold: (1) from the founder's address AND authenticated; (2) the token is THIS campaign's current
-- calendar email; (3) the content hash is unchanged since that email; (4) the month is not over and it is not
-- already approved; and the reply says approve. Anything else approves nothing and tells him what to do.
-- p = {token, from_email, authenticated, message_id, intent: 'approve' | 'unclear'}
create or replace function public.fn_marketing_calendar_reply(p jsonb)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  c public.marketing_campaign; v_from text := lower(btrim(coalesce(p->>'from_email', '')));
  v_now text; v_st jsonb; v_out text; v_msg text; v_subj text; v_nid bigint;
begin
  select * into c from public.marketing_campaign where calendar_token = lower(coalesce(p->>'token', '')) for update;
  -- A reply from anyone but him is recorded by the caller and never answered: we do not email strangers.
  if v_from is distinct from public.fn_marketing_founder_email() then
    return jsonb_build_object('outcome', 'not_the_founder', 'approved', false, 'campaign_key', c.campaign_key);
  end if;
  if c.id is null then
    v_out := 'unknown_calendar';
    v_msg := 'Your reply did not match the current social calendar email, so nothing was approved. Please reply to the latest calendar email you received from us (a newer one replaces any earlier one).';
  elsif not coalesce((p->>'authenticated')::boolean, false) then
    v_out := 'not_authenticated';
    v_msg := 'A reply to the ' || to_char(c.month, 'FMMonth YYYY') || ' social calendar arrived with your address but our mail server could not verify it came from your mailbox (no SPF/DKIM/DMARC pass), so nothing was approved. If it was you, reply again from your usual mail app.';
  else
    v_now := public.fn_marketing_campaign_hash(c.id);
    if c.approved_hash is not null and c.approved_hash = v_now then
      return jsonb_build_object('outcome', 'already_approved', 'approved', true, 'campaign_key', c.campaign_key);  -- idempotent: nothing sent
    elsif now() >= ((c.month + interval '1 month')::timestamp at time zone 'Asia/Dubai') then
      v_out := 'expired';
      v_msg := 'The ' || to_char(c.month, 'FMMonth YYYY') || ' calendar can no longer be approved: its month is over. Nothing was approved.';
    elsif c.calendar_hash is distinct from v_now then
      v_out := 'edited_after_sending';
      v_msg := 'The ' || to_char(c.month, 'FMMonth YYYY') || ' calendar was changed after we emailed it to you, so this approval would not match what will be posted. Nothing was approved; the updated calendar is being emailed to you now. Please reply "approve" to that one.';
    elsif coalesce(p->>'intent', '') <> 'approve' then
      v_out := 'unclear';
      v_msg := 'We could not read your reply as an approval of the ' || to_char(c.month, 'FMMonth YYYY') || ' social calendar, so nothing was approved. To approve it exactly as sent, reply with the single word "approve" (or "موافق"). To change something, tell us what, and we will send you a corrected calendar.';
    else
      update public.marketing_campaign set approved_by = 'founder', approved_at = now(), approved_hash = v_now,
             approved_message_id = coalesce(nullif(p->>'message_id', ''), 'unknown'), updated_at = now()
       where id = c.id;
      v_st := public.fn_marketing_campaign_state(c.campaign_key);
      v_out := 'approved';
      v_msg := 'Approved — ' || (v_st->>'posts') || ' posts scheduled from '
               || to_char(((v_st->>'first_post_at')::timestamptz at time zone 'Asia/Dubai'), 'FMDay DD FMMonth YYYY, HH24:MI') || ' (Dubai). '
               || 'They will go out exactly as in the calendar you approved (content reference ' || left(v_now, 12) || ').'
               || case when coalesce((select lower(value) from public.app_secrets where key = 'marketing_golive'), 'false') <> 'true'
                       then ' Publishing is currently switched off (marketing_golive); nothing will post until it is switched on.' else '' end;
    end if;
  end if;
  v_subj := case when v_out = 'approved' then 'Approved: ' else 'Not approved: ' end || 'social calendar '
            || coalesce(to_char(c.month, 'FMMonth YYYY'), '');
  v_nid := public.fn_marketing_mail_founder('marketing_calendar_reply', v_subj, v_msg);
  return jsonb_build_object('outcome', v_out, 'approved', v_out = 'approved', 'campaign_key', c.campaign_key, 'reply_notification_id', v_nid);
end $fn$;
revoke execute on function public.fn_marketing_calendar_reply(jsonb) from public, anon, authenticated;

-- the Reply-To the calendar email carries; send_outbox uses it when set (only our inbound subdomain)
alter table public.notifications add column if not exists reply_to text;
alter table public.notifications drop constraint if exists notifications_reply_to_is_our_inbound;
alter table public.notifications add constraint notifications_reply_to_is_our_inbound
  check (reply_to is null or reply_to ~ '^[a-z0-9._+-]+@mail\.quotesdone\.com$');

-- ── 6. THE PUBLISH GATE, IN THE DATABASE ─────────────────────────────────────────────────────────
-- NULL = may move towards Postiz. Otherwise the reason. Order: demo, campaign, approval, switch, specs.
create or replace function public.fn_marketing_post_publish_refusal(p public.marketing_post)
returns text language plpgsql stable security definer set search_path to 'public', 'pg_temp' as $fn$
declare c public.marketing_campaign; v record; v_probs text[];
begin
  -- ZZ DEMO both ways: the flag OR the words anywhere that is published
  if p.is_demo or (p.text_en || ' ' || p.text_ar || ' ' || coalesce(p.title, '') || ' ' || coalesce(p.cta_url, '')) ~* 'zz[ _-]?demo'
     or exists (select 1 from public.marketing_post_variant x where x.post_id = p.id
                 and (x.body || ' ' || coalesce(x.title, '') || ' ' || coalesce(x.alt_text, '') || ' ' || coalesce(x.first_comment, '')) ~* 'zz[ _-]?demo') then
    return 'demo: a ZZ DEMO post is never published';
  end if;
  if p.campaign_id is null then return 'no_campaign: only a post of an approved campaign is published'; end if;
  select * into c from public.marketing_campaign where id = p.campaign_id;
  if c.is_demo then return 'demo: a ZZ DEMO campaign is never published'; end if;
  if c.spend_policy <> 'organic_only' then return 'spend: only organic campaigns are published'; end if;
  if c.approved_hash is null then return 'not_approved: the founder has not approved campaign ' || c.campaign_key; end if;
  if c.approved_hash <> public.fn_marketing_campaign_hash(c.id) then
    return 'approval_void: campaign ' || c.campaign_key || ' was edited after the founder approved it';
  end if;
  if coalesce((select lower(value) from public.app_secrets where key = 'marketing_golive'), 'false') <> 'true' then
    return 'switch_off: app_secrets.marketing_golive is not true';
  end if;
  if not exists (select 1 from public.marketing_post_variant x where x.post_id = p.id) then return 'no_variants'; end if;
  for v in select x from public.marketing_post_variant x where x.post_id = p.id loop
    v_probs := public.fn_marketing_variant_problems(v.x);
    if v_probs is null then return 'platform_specs_not_loaded: fn_marketing_platform_spec_problems does not exist'; end if;
    if cardinality(v_probs) > 0 then return 'platform_spec: ' || (v.x).platform || ' ' || array_to_string(v_probs, '; '); end if;
  end loop;
  return null;
end $fn$;
revoke execute on function public.fn_marketing_post_publish_refusal(public.marketing_post) from public, anon, authenticated;

-- the same verdict by id, for marketing_channels to record on the dry run (the trigger below still decides)
create or replace function public.fn_marketing_post_refusal(p_post_id bigint)
returns text language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  select public.fn_marketing_post_publish_refusal(p) from public.marketing_post p where p.id = p_post_id
$fn$;
revoke execute on function public.fn_marketing_post_refusal(bigint) from public, anon, authenticated;

-- The claim (scheduled -> publishing) is the only door to Postiz; unconfirmed/published are what the door
-- leads to. Entering any of them from outside is refused unless the gate says yes. Leaving them (reconcile,
-- watchdog, cancel) is not gated: that records what really happened.
create or replace function public.fn_marketing_post_guard_publish()
returns trigger language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_why text;
begin
  -- Gated: the claim itself, an INSERT straight into flight, and a never-attempted post jumping to
  -- unconfirmed/published. A post with attempts > 0 passed this gate when it was claimed; recording that
  -- Postiz has it (reconcile, requeue) records what happened and is not gated again.
  if new.status in ('publishing', 'unconfirmed', 'published')
     and (tg_op = 'INSERT'
          or (old.status not in ('publishing', 'unconfirmed', 'published')
              and (new.status = 'publishing' or coalesce(old.attempts, 0) = 0))) then
    v_why := public.fn_marketing_post_publish_refusal(new);
    if v_why is not null then
      raise exception 'marketing_post % may not be published: %', coalesce(new.ingest_key, '?'), v_why
        using errcode = 'check_violation';
    end if;
  end if;
  return new;
end $fn$;
revoke execute on function public.fn_marketing_post_guard_publish() from public, anon, authenticated;
drop trigger if exists marketing_post_guard_publish on public.marketing_post;
create trigger marketing_post_guard_publish before insert or update of status on public.marketing_post
  for each row execute function public.fn_marketing_post_guard_publish();

-- ── 7. THE CALENDAR LOADER: A WHOLE MONTH IN ONE TRANSACTION, IDEMPOTENT ──────────────────────────
-- p = {campaign:{key, theme, month 'YYYY-MM', title?, is_demo?},
--      posts:[{key, platform, at_dubai 'YYYY-MM-DDTHH:MI:SS', at_utc ISO, post_type?, language?,
--              video:{path, sha256, title}, keyframe:{path, sha256}, caption_en, caption_ar, hashtags[],
--              alt_text?, title?, first_comment?, cta_url?, rationale?, music:{bpm, mood}?}]}
-- The sha256 of each asset is verified against its BYTES by scripts/marketing/load_calendar.mjs before this is
-- called; here each object must exist in the private bucket. Any error raises, so nothing of the month loads.
-- An unchanged record is not rewritten (updated_at stays): loading twice produces the same rows.
create or replace function public.fn_marketing_calendar_load(p jsonb)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  cj jsonb := p->'campaign'; r jsonb; v_cid bigint; v_key text; v_pid bigint; v_status text;
  v_platform text; v_utc timestamptz; v_local timestamp; v_video text; v_frame text; v_type text; v_lang text;
  v_tags text[]; v_bi text; v_seqs int[]; v_keys text[] := '{}'; v_ins int := 0; v_upd int := 0; v_same int := 0;
  v_skip int := 0; v_n int; v_probe public.marketing_post_variant; v_probs text[];
  v_title text; v_en text; v_ar text; v_demo boolean; v_cap text; v_vlang text;
begin
  if coalesce(cj->>'key', '') !~ '^[a-z0-9][a-z0-9-]{2,80}$' then raise exception 'calendar: campaign.key is missing or malformed'; end if;
  if coalesce(cj->>'month', '') !~ '^\d{4}-\d{2}$' then raise exception 'calendar: campaign.month must be YYYY-MM'; end if;
  if jsonb_typeof(p->'posts') is distinct from 'array' or jsonb_array_length(p->'posts') = 0 then raise exception 'calendar: no posts'; end if;
  v_demo := coalesce((cj->>'is_demo')::boolean, false);

  insert into public.marketing_campaign as t (campaign_key, theme, title, month, is_demo)
  values (cj->>'key', cj->>'theme', nullif(btrim(cj->>'title'), ''), (cj->>'month' || '-01')::date, v_demo)
  on conflict (campaign_key) do update set theme = excluded.theme, title = excluded.title, month = excluded.month,
         is_demo = excluded.is_demo, updated_at = now()
   where (t.theme, t.title, t.month, t.is_demo) is distinct from (excluded.theme, excluded.title, excluded.month, excluded.is_demo);
  select id into v_cid from public.marketing_campaign where campaign_key = cj->>'key';

  for r in select * from jsonb_array_elements(p->'posts') loop
    v_key := lower(btrim(coalesce(r->>'key', '')));
    if v_key !~ '^[a-z0-9][a-z0-9_-]{2,80}$' then raise exception 'calendar: post key % is malformed', r->>'key'; end if;
    if v_key = any (v_keys) then raise exception 'calendar: post key % appears twice', v_key; end if;
    v_keys := v_keys || v_key;
    v_platform := r->>'platform';
    if v_platform is null or v_platform not in ('facebook', 'instagram', 'linkedin', 'x', 'youtube', 'tiktok') then
      raise exception 'calendar %: platform % is not one of facebook, instagram, linkedin, x, youtube, tiktok', v_key, v_platform;
    end if;
    -- The two clocks must agree: Dubai is UTC+4 all year.
    v_utc := (r->>'at_utc')::timestamptz; v_local := (r->>'at_dubai')::timestamp;
    if v_utc is null or v_local is null or v_local <> (v_utc at time zone 'Asia/Dubai') then
      raise exception 'calendar %: at_dubai % is not at_utc % in Asia/Dubai', v_key, r->>'at_dubai', r->>'at_utc';
    end if;
    v_video := regexp_replace(coalesce(r#>>'{video,path}', ''), '^marketing-media/', '');
    v_frame := regexp_replace(coalesce(r#>>'{keyframe,path}', ''), '^marketing-media/', '');
    if v_video !~ ('^campaigns/' || (cj->>'key') || '/videos/[A-Za-z0-9._-]+\.mp4$') then
      raise exception 'calendar %: video.path % is not campaigns/%/videos/<name>.mp4', v_key, v_video, cj->>'key';
    end if;
    if v_frame !~ ('^campaigns/' || (cj->>'key') || '/(frames|videos)/[A-Za-z0-9._-]+\.(jpg|jpeg|png)$') then
      raise exception 'calendar %: keyframe.path % is not a jpg/png under campaigns/%/frames/', v_key, v_frame, cj->>'key';
    end if;
    if coalesce(r#>>'{video,sha256}', '') !~ '^[0-9a-f]{64}$' or coalesce(r#>>'{keyframe,sha256}', '') !~ '^[0-9a-f]{64}$' then
      raise exception 'calendar %: video.sha256 and keyframe.sha256 are required (64 lowercase hex)', v_key;
    end if;
    if not exists (select 1 from storage.objects o where o.bucket_id = 'marketing-media' and o.name = v_video)
       or not exists (select 1 from storage.objects o where o.bucket_id = 'marketing-media' and o.name = v_frame) then
      raise exception 'calendar %: % or % is not in the private marketing-media bucket', v_key, v_video, v_frame;
    end if;
    v_en := btrim(coalesce(r->>'caption_en', '')); v_ar := btrim(coalesce(r->>'caption_ar', ''));
    if v_en = '' or v_ar !~ '[؀-ۿ]' then raise exception 'calendar %: caption_en and an Arabic caption_ar are required', v_key; end if;
    v_title := coalesce(nullif(btrim(r->>'title'), ''), nullif(btrim(r#>>'{video,title}'), ''));
    if v_title is null then raise exception 'calendar %: video.title is required', v_key; end if;
    v_tags := coalesce((select array_agg(regexp_replace(btrim(x), '^#', '') order by n) from jsonb_array_elements_text(coalesce(r->'hashtags', '[]')) with ordinality h(x, n)), '{}');
    -- a video is a reel on Instagram and Facebook, a Short on YouTube, a video on LinkedIn and X
    v_type := coalesce(r->>'post_type', case v_platform when 'youtube' then 'short' when 'instagram' then 'reel'
                                                        when 'facebook' then 'reel' else 'video' end);

    -- the post
    select id, status into v_pid, v_status from public.marketing_post where ingest_key = v_key for update;
    if found and v_status not in ('draft', 'scheduled', 'failed') then v_skip := v_skip + 1; continue; end if;
    if found and exists (select 1 from public.marketing_post where id = v_pid and campaign_id is distinct from v_cid) then
      raise exception 'calendar %: this key belongs to another campaign', v_key;
    end if;
    insert into public.marketing_post as t (ingest_key, ingested_by, title, text_en, text_ar, media_paths, channels, scheduled_at,
                                            scheduled_local, status, is_demo, campaign_id, video_path, video_sha256, cover_path,
                                            cover_sha256, cta_url, rationale, music)
    values (v_key, 'claude', v_title, v_en, v_ar, array[v_video], array[v_platform], v_utc, v_local, 'scheduled', v_demo, v_cid,
            v_video, r#>>'{video,sha256}', v_frame, r#>>'{keyframe,sha256}', nullif(btrim(r->>'cta_url'), ''),
            nullif(btrim(r->>'rationale'), ''), r->'music')
    on conflict (ingest_key) do update set title = excluded.title, text_en = excluded.text_en, text_ar = excluded.text_ar,
           media_paths = excluded.media_paths, channels = excluded.channels, scheduled_at = excluded.scheduled_at,
           scheduled_local = excluded.scheduled_local, status = 'scheduled', is_demo = excluded.is_demo,
           video_path = excluded.video_path, video_sha256 = excluded.video_sha256, cover_path = excluded.cover_path,
           cover_sha256 = excluded.cover_sha256, cta_url = excluded.cta_url, rationale = excluded.rationale,
           music = excluded.music, dry_run = null, error = null, updated_at = now()
     where (t.title, t.text_en, t.text_ar, t.media_paths, t.channels, t.scheduled_at, t.scheduled_local, t.status, t.is_demo,
            t.video_path, t.video_sha256, t.cover_path, t.cover_sha256, t.cta_url, t.rationale, t.music)
       is distinct from
           (excluded.title, excluded.text_en, excluded.text_ar, excluded.media_paths, excluded.channels, excluded.scheduled_at,
            excluded.scheduled_local, 'scheduled'::text, excluded.is_demo, excluded.video_path, excluded.video_sha256,
            excluded.cover_path, excluded.cover_sha256, excluded.cta_url, excluded.rationale, excluded.music);
    get diagnostics v_n = row_count;
    if v_pid is null then v_ins := v_ins + 1; elsif v_n > 0 then v_upd := v_upd + 1; else v_same := v_same + 1; end if;
    select id into v_pid from public.marketing_post where ingest_key = v_key;

    -- the variants: EN+AR in one post where the platform spec says it fits; on X a thread (EN, then AR) when not
    v_bi := v_en || E'\n\n' || v_ar;
    v_lang := r->>'language';
    if v_lang is null then
      v_probe := row(null, v_pid, v_platform, 1, 'bi', v_type, v_bi, v_tags, public.fn_marketing_variant_text(v_bi, v_tags),
                     nullif(btrim(r->>'alt_text'), ''), case when v_platform = 'youtube' then v_title end,
                     nullif(btrim(r->>'first_comment'), ''), v_frame, now(), now())::public.marketing_post_variant;
      v_probs := public.fn_marketing_variant_problems(v_probe);
      v_lang := case when coalesce(cardinality(v_probs), 0) = 0 then 'bi' when v_platform = 'x' then 'thread' else 'bi' end;
    end if;
    v_seqs := '{}';
    for v_n, v_cap, v_vlang in
      select * from (values (1, case when v_lang = 'ar' then v_ar when v_lang in ('en', 'thread') then v_en else v_bi end,
                                case when v_lang = 'thread' then 'en' else v_lang end),
                            (2, v_ar, 'ar')) s(seq, cap, lang)
       where s.seq = 1 or v_lang = 'thread'
    loop
      insert into public.marketing_post_variant as t (post_id, platform, seq, language, post_type, caption, hashtags, alt_text,
                                                      title, first_comment, cover_path)
      values (v_pid, v_platform, v_n, v_vlang, v_type, v_cap, case when v_n = 1 then v_tags else '{}' end,
              nullif(btrim(r->>'alt_text'), ''), case when v_platform = 'youtube' then v_title end,
              case when v_n = 1 then nullif(btrim(r->>'first_comment'), '') end, v_frame)
      on conflict (post_id, platform, seq) do update set language = excluded.language, post_type = excluded.post_type,
             caption = excluded.caption, hashtags = excluded.hashtags, alt_text = excluded.alt_text, title = excluded.title,
             first_comment = excluded.first_comment, cover_path = excluded.cover_path, updated_at = now()
       where (t.language, t.post_type, t.caption, t.hashtags, t.alt_text, t.title, t.first_comment, t.cover_path)
             is distinct from (excluded.language, excluded.post_type, excluded.caption, excluded.hashtags, excluded.alt_text,
                               excluded.title, excluded.first_comment, excluded.cover_path);
      v_seqs := v_seqs || v_n;
    end loop;
    delete from public.marketing_post_variant where post_id = v_pid and not (seq = any (v_seqs) and platform = v_platform);
    -- a variant the platform spec refuses stops the whole month here, not at publish time
    for v_probe in select * from public.marketing_post_variant where post_id = v_pid loop
      v_probs := public.fn_marketing_variant_problems(v_probe);
      if cardinality(v_probs) > 0 then
        raise exception 'calendar %: % seq % breaks the platform spec: %', v_key, v_probe.platform, v_probe.seq, array_to_string(v_probs, '; ');
      end if;
    end loop;
  end loop;

  -- a post that left the calendar leaves the month (kept as history, never published)
  update public.marketing_post set status = 'cancelled', updated_at = now()
   where campaign_id = v_cid and status in ('draft', 'scheduled', 'failed') and not (ingest_key = any (v_keys));
  get diagnostics v_n = row_count;

  return jsonb_build_object('ok', true, 'campaign_key', cj->>'key', 'campaign_id', v_cid, 'inserted', v_ins, 'updated', v_upd,
    'unchanged', v_same, 'already_sent_not_touched', v_skip, 'cancelled_as_removed', v_n,
    'state', public.fn_marketing_campaign_state(cj->>'key'));
end $fn$;
revoke execute on function public.fn_marketing_calendar_load(jsonb) from public, anon, authenticated;

-- ── 8. THE DAILY TABLE EXPORT: + marketing_campaign, marketing_post_variant ────────────────────────
-- Copied from the_marketing_seat_writes_articles_and_drafts_linkedin_outreach.sql (the current winner) with
-- the two tables added under subject 'marketing'.
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
    ('marketing_ad_spend_day','marketing'), ('marketing_duty_run','marketing'), ('marketing_report','marketing'),
    ('marketing_article','marketing'), ('marketing_prospect','marketing'), ('marketing_outreach_message','marketing'),
    ('marketing_campaign','marketing'), ('marketing_post_variant','marketing'),
    ('table_export_change','backup')
  ) v(t, s)
$fn$;
revoke execute on function public.fn_table_export_list() from public, anon, authenticated;

commit;
