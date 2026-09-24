-- ONE "APPROVE" SCHEDULES AND PUBLISHES THE MONTH, ON WORKING DAYS ONLY (24 Sep 2026; seat: marketing).
--
-- Founder, 24 Sep 2026: "It should be one shot. I say approve... it's done." (memory marketing-month-approval-flow)
-- and the standing rule the same day: never post on the UAE weekend (Saturday, Sunday) or on a UAE official
-- public holiday; a post that lands on a blocked day moves to the next working day. Everything here is code:
-- no model is called anywhere in this file (founder, 24 Sep 2026: routine work is code, not LLM).
--
-- WHAT WAS MEASURED (production, read-only, 24 Sep 2026 03:40 Dubai):
--   * campaign 7 (2026-month1-supplier-recruitment) is loaded: 60 posts 'scheduled', calendar never sent, not
--     approved; app_secrets.marketing_golive = 'false'. Under a_month_of_posts_is_approved_once_... his
--     "approve" could NOT publish anything: the gate also refused on marketing_golive, a second switch.
--   * a reply that was not exactly "approve" approved nothing and was answered "we could not read your reply";
--     what he asked for went nowhere.
--   * public.public_holidays + public.fn_is_working_day(date) already exist (Mon-Fri, minus holidays) and are
--     reused; 2027 had only New Year and National Day, none of the Hijri-calendar holidays.
--
-- WHAT THIS CHANGES:
--   fn_marketing_publishing_on       the ONE switch left: app_secrets.marketing_publishing_enabled, an EMERGENCY
--                                    STOP that defaults to ON (missing or anything but 'false' = on).
--                                    marketing_golive no longer gates an approved calendar (it still gates the
--                                    LinkedIn list and the article cadence, which are not calendars).
--   fn_marketing_post_publish_refusal  approval of exactly this content + working day + the emergency stop;
--                                    the marketing_golive step is gone.
--   a05_marketing_post_on_a_working_day   BEFORE trigger: a draft/scheduled post whose Dubai date is a Saturday,
--                                    Sunday or public holiday moves to the next working day at the SAME Dubai time.
--   public_holidays_move_the_posts   a holiday added or corrected later moves the posts already on that day
--                                    (which voids the approval by the hash, so the corrected calendar is re-sent).
--   public_holidays 2027             the Hijri-calendar holidays, confirmed = false (moon-sighting estimates; the
--                                    Cabinet confirms days before -- correct the row then, and the posts follow).
--   marketing_founder_request        the marketing seat's queue of the founder's own words: a calendar reply that
--                                    is not exactly "approve" (kind calendar_change), or his reply to the monthly
--                                    idea plan with his content (kind month_content). The adjustment itself is the
--                                    one place reasoning is allowed; the re-send is code (fn_marketing_calendar_due
--                                    fires on the changed hash).
--   fn_marketing_calendar_reply      approve -> approved AND publishing (no second switch); anything else he wrote
--                                    -> a marketing_founder_request with his text, and he is told it was passed on.
--                                    A calendar "expires" when its LAST post has passed, not at the end of the
--                                    calendar month (the first campaign runs 25 Sep to 21 Oct).
--   fn_marketing_calendar_due        the same expiry rule.
--   THE MONTHLY LOOP (from November 2026): marketing_video_idea (a bank of evergreen ideas, rotated),
--   marketing_month_plan (the existing table, reused), fn_marketing_month_plan_tick (on the 1st Dubai day of month M, M+1's plan of 12 videos
--   on working Mon/Wed/Thu is emailed to him, Reply-To plan+<token>@mail.quotesdone.com), and
--   fn_marketing_month_plan_reply (his reply -> a month_content request for the seat).
--
-- THE MAILBOX. Every email here goes through fn_marketing_mail_founder -> founder_mail_policy (kinds
-- marketing_calendar, marketing_calendar_reply, marketing_month_plan, marketing_month_plan_reply, all allowed,
-- owner marketing) -> the FIRST address of app_secrets.admin_emails, the same address fn_notify_founder uses.
-- Measured 24 Sep 2026: management@quotesdone.com.
--
-- Proved by one_approve_schedules_and_publishes_the_month_on_working_days_probe.sql (aborted transaction) and
-- supabase/functions/_shared/marketing_calendar_mail.test.ts; prevented by:
-- scripts/checks/marketing_posts_only_on_uae_working_days.test.mjs.
--
--   node scripts/apply_sql.mjs scripts/sql/one_approve_schedules_and_publishes_the_month_on_working_days.sql --apply --ddl

begin;

-- ── 1. THE EMERGENCY STOP (defaults ON) ────────────────────────────────────────────────────────────
insert into public.app_secrets (key, value) values ('marketing_publishing_enabled', 'true') on conflict (key) do nothing;

create or replace function public.fn_marketing_publishing_on()
returns boolean language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  select coalesce((select lower(btrim(value)) from public.app_secrets where key = 'marketing_publishing_enabled'), 'true') <> 'false'
$fn$;
revoke execute on function public.fn_marketing_publishing_on() from public, anon, authenticated;

-- ── 2. THE UAE PUBLIC HOLIDAYS OF 2027 (Hijri-calendar dates are estimates until the Cabinet confirms) ─
-- Source: u.ae "Public holidays" and the MoHRE/Cabinet announcements; the Hijri dates follow the Umm al-Qura
-- estimate already recorded in public.company_calendar. confirmed = false says they may move by a day.
insert into public.public_holidays (holiday_date, name, confirmed) values
  ('2027-03-10', 'Eid al-Fitr', false), ('2027-03-11', 'Eid al-Fitr', false), ('2027-03-12', 'Eid al-Fitr', false),
  ('2027-05-15', 'Arafat Day', false),
  ('2027-05-16', 'Eid al-Adha', false), ('2027-05-17', 'Eid al-Adha', false), ('2027-05-18', 'Eid al-Adha', false),
  ('2027-06-07', 'Hijri New Year', false),
  ('2027-08-16', 'Prophet Muhammad''s Birthday', false)
on conflict (holiday_date) do nothing;

-- ── 3. A POST NEVER SITS ON A BLOCKED DAY ────────────────────────────────────────────────────────────
-- Next working day at the same Dubai wall-clock time (Dubai has no DST, so + 1 day keeps the time).
create or replace function public.fn_marketing_next_working_slot(p_at timestamptz)
returns timestamptz language plpgsql stable security definer set search_path to 'public', 'pg_temp' as $fn$
declare v timestamptz := p_at; i int := 0;
begin
  if v is null then return null; end if;
  while not public.fn_is_working_day((v at time zone 'Asia/Dubai')::date) loop
    v := v + interval '1 day'; i := i + 1;
    if i > 30 then raise exception 'no UAE working day within 30 days of %', p_at; end if;
  end loop;
  return v;
end $fn$;
revoke execute on function public.fn_marketing_next_working_slot(timestamptz) from public, anon, authenticated;

create or replace function public.fn_marketing_post_on_a_working_day()
returns trigger language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
begin
  if new.status in ('draft', 'scheduled') and new.scheduled_at is not null then
    new.scheduled_at := public.fn_marketing_next_working_slot(new.scheduled_at);
    new.scheduled_local := new.scheduled_at at time zone 'Asia/Dubai';
  end if;
  return new;
end $fn$;
revoke execute on function public.fn_marketing_post_on_a_working_day() from public, anon, authenticated;
drop trigger if exists a05_marketing_post_on_a_working_day on public.marketing_post;
create trigger a05_marketing_post_on_a_working_day before insert or update of scheduled_at, status on public.marketing_post
  for each row execute function public.fn_marketing_post_on_a_working_day();

-- A holiday added or corrected later moves the posts already sitting on it (the trigger above does the moving).
create or replace function public.fn_public_holiday_moves_the_posts()
returns trigger language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
begin
  update public.marketing_post set scheduled_at = scheduled_at, updated_at = now()
   where status in ('draft', 'scheduled') and (scheduled_at at time zone 'Asia/Dubai')::date = new.holiday_date;
  return null;
end $fn$;
revoke execute on function public.fn_public_holiday_moves_the_posts() from public, anon, authenticated;
drop trigger if exists public_holidays_move_the_posts on public.public_holidays;
create trigger public_holidays_move_the_posts after insert or update of holiday_date on public.public_holidays
  for each row execute function public.fn_public_holiday_moves_the_posts();

-- ── 4. THE PUBLISH GATE: APPROVAL OF THIS CONTENT, A WORKING DAY, AND THE EMERGENCY STOP ────────────
-- Body of a_month_of_posts_is_approved_once_and_goes_out_exactly_as_approved.sql with two changes: the
-- marketing_golive step is replaced by fn_marketing_publishing_on (default on), and a blocked day refuses.
create or replace function public.fn_marketing_post_publish_refusal(p public.marketing_post)
returns text language plpgsql stable security definer set search_path to 'public', 'pg_temp' as $fn$
declare c public.marketing_campaign; v record; v_probs text[];
begin
  -- ZZ DEMO both ways: the flag OR the words anywhere that is published
  if p.is_demo or (p.text_en || ' ' || coalesce(p.text_ar, '') || ' ' || coalesce(p.title, '') || ' ' || coalesce(p.cta_url, '')) ~* 'zz[ _-]?demo'
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
  -- A slot missed by more than 30 minutes is not posted late (review of #874).
  if p.scheduled_at < now() - interval '30 minutes' then
    return 'missed_slot: due ' || to_char(p.scheduled_at at time zone 'Asia/Dubai', 'YYYY-MM-DD HH24:MI') || ' Dubai; reschedule and re-approve';
  end if;
  -- Founder, 24 Sep 2026: never on the UAE weekend or a UAE public holiday (the trigger moves such posts; this
  -- is the backstop for a row that reached the day some other way).
  if not public.fn_is_working_day((p.scheduled_at at time zone 'Asia/Dubai')::date) then
    return 'blocked_day: ' || to_char(p.scheduled_at at time zone 'Asia/Dubai', 'YYYY-MM-DD') || ' is a UAE weekend day or public holiday';
  end if;
  if not public.fn_marketing_publishing_on() then
    return 'kill_switch: app_secrets.marketing_publishing_enabled is false (emergency stop)';
  end if;
  if not exists (select 1 from public.marketing_post_variant x where x.post_id = p.id) then return 'no_variants'; end if;
  for v in select x from public.marketing_post_variant x where x.post_id = p.id loop
    v_probs := public.fn_marketing_variant_problems(v.x);
    if v_probs is null then return 'platform_specs_not_loaded: fn_marketing_platform_spec_problems does not exist'; end if;
    if cardinality(v_probs) > 0 then return 'platform_spec: ' || (v.x).platform || ' ' || array_to_string(v_probs, '; '); end if;
  end loop;
  return null;
end $fn$;

-- ── 5. THE SEAT'S QUEUE OF HIS OWN WORDS ──────────────────────────────────────────────────────────
create table if not exists public.marketing_founder_request (
  id           bigint generated always as identity primary key,
  kind         text not null check (kind in ('calendar_change', 'month_content')),
  campaign_id  bigint references public.marketing_campaign(id),
  month        date check (month = date_trunc('month', month)::date),
  founder_text text not null default '',
  attachments  text[] not null default '{}',
  message_id   text,
  status       text not null default 'open' check (status in ('open', 'done', 'superseded')),
  done_at      timestamptz,
  done_note    text,
  created_at   timestamptz not null default now(),
  constraint marketing_founder_request_names_its_subject check (campaign_id is not null or month is not null),
  constraint marketing_founder_request_done_is_whole check ((status = 'open') = (done_at is null))
);
create unique index if not exists marketing_founder_request_one_per_message
  on public.marketing_founder_request (message_id) where message_id is not null and message_id <> '';
comment on table public.marketing_founder_request is
  'The marketing seat''s queue of the founder''s own words: a reply to the calendar email that is not exactly "approve" (calendar_change: adjust, and the corrected calendar is re-sent by fn_marketing_calendar_due), or his reply to the monthly idea plan with his content (month_content: build and load the calendar).';
alter table public.marketing_founder_request enable row level security;
drop policy if exists marketing_founder_request_service_role_only on public.marketing_founder_request;
create policy marketing_founder_request_service_role_only on public.marketing_founder_request as permissive for all to public using (false) with check (false);
revoke all on public.marketing_founder_request from anon, authenticated;

-- ── 6. HIS REPLY TO THE CALENDAR: "approve" publishes; anything else goes to the seat ────────────────
insert into public.founder_mail_policy (kind, allowed_to_email, reason, owner_role, updated_at) values
  ('marketing_calendar_reply', true, 'Founder instructions 872 (23 Sep 2026) and 24 Sep 2026 ("one shot"): the answer to his reply to the calendar -- approved and scheduled, or his change request passed to the marketing seat.', 'marketing', now()),
  ('marketing_month_plan', true, 'Founder, 24 Sep 2026: on the 1st of each month the marketing seat sends him next month''s video idea plan; he makes the content and shares it back.', 'marketing', now()),
  ('marketing_month_plan_reply', true, 'Founder, 24 Sep 2026: the acknowledgement of his reply to the monthly idea plan (his content was passed to the marketing seat).', 'marketing', now())
on conflict (kind) do update set allowed_to_email = excluded.allowed_to_email, reason = excluded.reason,
       owner_role = excluded.owner_role, updated_at = now();

-- p = {token, from_email, authenticated, message_id, intent: 'approve' | 'change' | 'unclear', text}
create or replace function public.fn_marketing_calendar_reply(p jsonb)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  c public.marketing_campaign; v_from text := lower(btrim(coalesce(p->>'from_email', '')));
  v_now text; v_st jsonb; v_out text; v_msg text; v_subj text; v_nid bigint; v_last timestamptz; v_rid bigint;
  v_text text := btrim(coalesce(p->>'text', ''));
begin
  select * into c from public.marketing_campaign where calendar_token = lower(coalesce(p->>'token', '')) for update;
  -- A reply from anyone but him is recorded by the caller and never answered: we do not email strangers.
  if v_from is distinct from public.fn_marketing_founder_email() then
    return jsonb_build_object('outcome', 'not_the_founder', 'approved', false, 'campaign_key', c.campaign_key);
  end if;
  select max(scheduled_at) into v_last from public.marketing_post where campaign_id = c.id and status <> 'cancelled';
  if c.id is null then
    v_out := 'unknown_calendar';
    v_msg := 'Your reply did not match the current social calendar email, so nothing was approved. Please reply to the latest calendar email you received from us (a newer one replaces any earlier one).';
  elsif not coalesce((p->>'authenticated')::boolean, false) then
    v_out := 'not_authenticated';
    v_msg := 'A reply to the social calendar arrived with your address but our mail server could not verify it came from your mailbox (no SPF/DKIM/DMARC pass), so nothing was approved or changed. If it was you, reply again from your usual mail app.';
  else
    v_now := public.fn_marketing_campaign_hash(c.id);
    if coalesce(p->>'intent', '') = 'approve' and c.approved_hash is not null and c.approved_hash = v_now then
      return jsonb_build_object('outcome', 'already_approved', 'approved', true, 'campaign_key', c.campaign_key);  -- idempotent: nothing sent
    elsif v_last is null or now() >= v_last then
      v_out := 'expired';
      v_msg := 'This social calendar has no posts left to go out, so nothing was approved or changed.';
    elsif coalesce(p->>'intent', '') = 'change' and v_text <> '' then
      -- HIS WORDS GO TO THE SEAT. Filed once per message; the corrected calendar is re-sent by code when it changes.
      insert into public.marketing_founder_request (kind, campaign_id, month, founder_text, message_id)
      values ('calendar_change', c.id, c.month, left(v_text, 4000), nullif(p->>'message_id', ''))
      on conflict (message_id) where message_id is not null and message_id <> '' do nothing
      returning id into v_rid;
      if v_rid is null then
        return jsonb_build_object('outcome', 'change_already_filed', 'approved', false, 'campaign_key', c.campaign_key);
      end if;
      v_out := 'change_requested';
      v_msg := 'Nothing was approved yet. Your change request was passed to the marketing seat (request ' || v_rid || '):' || E'\n\n'
               || left(v_text, 1500) || E'\n\n'
               || 'The corrected calendar will be emailed to you for approval; reply "approve" to that one and it is scheduled and published.';
    elsif c.calendar_hash is distinct from v_now then
      v_out := 'edited_after_sending';
      v_msg := 'The social calendar was changed after we emailed it to you, so this approval would not match what will be posted. Nothing was approved; the updated calendar is being emailed to you now. Please reply "approve" to that one.';
    elsif coalesce(p->>'intent', '') <> 'approve' then
      v_out := 'unclear';
      v_msg := 'Your reply had no text of its own, so nothing was approved. To approve the calendar exactly as sent, reply with the single word "approve" (or "موافق"). To change something, reply saying what.';
    else
      update public.marketing_campaign set approved_by = 'founder', approved_at = now(), approved_hash = v_now,
             approved_message_id = coalesce(nullif(p->>'message_id', ''), 'unknown'), updated_at = now()
       where id = c.id;
      v_st := public.fn_marketing_campaign_state(c.campaign_key);
      v_out := 'approved';
      v_msg := 'Approved — ' || (v_st->>'posts') || ' posts scheduled and publishing from '
               || to_char(((v_st->>'first_post_at')::timestamptz at time zone 'Asia/Dubai'), 'FMDay DD FMMonth YYYY, HH24:MI') || ' (Dubai), '
               || 'on UAE working days only. They go out exactly as in the calendar you approved (content reference ' || left(v_now, 12) || ').'
               || case when not public.fn_marketing_publishing_on()
                       then ' NOTE: the emergency stop is on (marketing_publishing_enabled = false); nothing posts until it is lifted.' else '' end;
    end if;
  end if;
  v_subj := case v_out when 'approved' then 'Approved: ' when 'change_requested' then 'Change request received: ' else 'Not approved: ' end
            || 'social calendar' || coalesce(' — ' || c.title, '');
  v_nid := public.fn_marketing_mail_founder('marketing_calendar_reply', left(v_subj, 200), v_msg);
  return jsonb_build_object('outcome', v_out, 'approved', v_out = 'approved', 'campaign_key', c.campaign_key,
                            'request_id', v_rid, 'reply_notification_id', v_nid);
end $fn$;

-- A calendar is owed while its last post is still to come (not "until the calendar month ends").
create or replace function public.fn_marketing_calendar_due()
returns table(campaign_key text, current_hash text)
language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  select c.campaign_key, h.v
    from public.marketing_campaign c, lateral (select public.fn_marketing_campaign_hash(c.id) v) h
   where not c.is_demo
     and now() < (select max(p.scheduled_at) from public.marketing_post p where p.campaign_id = c.id and p.status <> 'cancelled')
     and h.v is distinct from c.calendar_hash
     and h.v is distinct from c.approved_hash
     and greatest(c.updated_at,
                  (select max(p.updated_at) from public.marketing_post p where p.campaign_id = c.id),
                  (select max(v.updated_at) from public.marketing_post_variant v join public.marketing_post p on p.id = v.post_id
                    where p.campaign_id = c.id)) < now() - interval '30 minutes'
$fn$;

-- ── 7. THE MONTHLY LOOP: IDEAS OUT ON THE 1st, CONTENT BACK, CALENDAR FOR "approve" ─────────────────
create table if not exists public.marketing_video_idea (
  id                 bigint generated always as identity primary key,
  idea_key           text not null unique check (idea_key ~ '^[a-z0-9][a-z0-9-]{2,60}$'),
  title              text not null check (btrim(title) <> ''),
  hook               text not null check (btrim(hook) <> ''),
  film_plan          text not null check (btrim(film_plan) <> ''),
  cta                text not null check (btrim(cta) <> ''),
  audience           text not null check (audience in ('supplier', 'customer', 'both')),
  enabled            boolean not null default true,
  last_planned_month date,
  created_at         timestamptz not null default now()
);
comment on table public.marketing_video_idea is
  'The bank of evergreen short-video ideas the monthly plan rotates through (least recently planned first). The founder films them; he may replace any idea in his reply.';
alter table public.marketing_video_idea enable row level security;
drop policy if exists marketing_video_idea_service_role_only on public.marketing_video_idea;
create policy marketing_video_idea_service_role_only on public.marketing_video_idea as permissive for all to public using (false) with check (false);
revoke all on public.marketing_video_idea from anon, authenticated;

insert into public.marketing_video_idea (idea_key, title, hook, film_plan, cta, audience) values
  ('post-once-get-three', 'Post once, get three quotes', 'Stop chasing five suppliers on WhatsApp.', 'Screen recording: post one request in under a minute, then the three anonymous quotes arriving side by side.', 'Post your first request free at quotesdone.ae', 'customer'),
  ('identity-stays-private', 'Your identity stays private', 'Suppliers see the job, not who you are.', 'Split screen: what the customer types vs what a supplier sees (no name, no number) until the customer chooses.', 'See how it works at quotesdone.ae', 'both'),
  ('first-1000-free', 'The first 1,000 suppliers join free', 'No subscription, permanently, for the first 1,000.', 'Founder to camera, 20 seconds, counter graphic of places left, then the registration screen.', 'Register your business at quotesdone.ae/supplier', 'supplier'),
  ('only-matching-requests', 'Only requests that match your trade', 'No spam leads, no bidding wars on jobs you do not do.', 'Show a supplier profile with confirmed trades, then the inbox receiving only a matching request.', 'Confirm your trades at quotesdone.ae/supplier', 'supplier'),
  ('licence-verified', 'Every supplier is licence-verified', 'You only hear from licensed UAE businesses.', 'Walk through the verification badge and what is checked; close on a verified profile.', 'Post a request at quotesdone.ae', 'customer'),
  ('compare-like-for-like', 'Compare like for like', 'Three quotes in one table, same line items.', 'Screen recording of the comparison table; highlight price, lead time and warranty columns.', 'Try it on your next purchase at quotesdone.ae', 'customer'),
  ('fitout-example', 'A fit-out request, start to finish', 'From a photo of an empty office to three quotes.', 'Timelapse style: photo upload, spec lines, three quotes, the choice.', 'Post your fit-out request at quotesdone.ae', 'customer'),
  ('supplier-day-in-life', 'A supplier''s morning on QuotesDone', 'Coffee, one notification, one real job.', 'Film a supplier opening a matched request and sending a quote in two minutes.', 'Join free at quotesdone.ae/supplier', 'supplier'),
  ('no-commission-surprises', 'What it costs, plainly', 'No hidden commission, no surprise fees.', 'Founder explains the fee model in 30 seconds with one on-screen line per rule.', 'Read the pricing at quotesdone.ae', 'both'),
  ('every-emirate', 'From Abu Dhabi to Fujairah', 'Customers post from every emirate.', 'Map of the seven emirates lighting up as requests arrive (illustrative).', 'Serve all seven emirates: quotesdone.ae/supplier', 'supplier'),
  ('founder-why', 'Why we built QuotesDone', 'Buying for a business in the UAE should not take a week of calls.', 'Founder to camera, 45 seconds, one story of a purchase that took too long.', 'Post a request at quotesdone.ae', 'both'),
  ('quote-in-two-minutes', 'Send a quote in two minutes', 'Line items, price, lead time. Done.', 'Phone screen recording of a supplier filling a quote end to end.', 'Register free at quotesdone.ae/supplier', 'supplier'),
  ('logistics-example', 'Moving goods? Get three prices', 'One request reaches licensed logistics companies.', 'Show a logistics request with pallet count and route, then quotes arriving.', 'Post your shipment at quotesdone.ae', 'customer'),
  ('it-hardware-example', 'Laptops for the team', 'Twenty laptops, three quotes, one afternoon.', 'Screen recording of an IT hardware request and the comparison.', 'Post your IT request at quotesdone.ae', 'customer'),
  ('choose-and-reveal', 'You choose, then we introduce', 'Pick the best quote; only then are contacts shared.', 'Animation of the choice step and both parties receiving each other''s details.', 'See the flow at quotesdone.ae', 'both'),
  ('faq-in-60', 'Five questions in sixty seconds', 'The five things everyone asks first.', 'Founder answers five on-screen questions, twelve seconds each.', 'More answers at quotesdone.ae', 'both')
on conflict (idea_key) do nothing;

-- REUSED, NOT REBUILT: public.marketing_month_plan (the_marketing_seat_watches_its_videos_studies_the_market_and_
-- argues_its_month_with_the_ceo.sql) already holds one row per month with plan / content_brief / status. That file
-- drafts the plan with a model and a CEO debate (held today). The founder ruled on 24 Sep 2026 that the monthly
-- idea plan is routine work and is CODE, so the tick below writes the same row -- plan = the 12 ideas,
-- content_brief = what to film, status 'sent_to_founder', a code verdict so no model step is ever due for it --
-- and the founder's reply records his decision in the same columns fn_marketing_month_plan_founder_decides uses.
alter table public.marketing_month_plan
  add column if not exists plan_token           text unique check (plan_token ~ '^[0-9a-f]{32}$'),
  add column if not exists plan_notification_id bigint,
  add column if not exists plan_sent_at         timestamptz;
comment on column public.marketing_month_plan.plan_token is
  'The token of the idea plan email (Reply-To plan+<token>@mail.quotesdone.com, subject "[plan <token>]"); his reply to it is filed by fn_marketing_month_plan_reply.';

-- The 12 video days of a month: working days, Monday/Wednesday/Thursday first, then other working days if a
-- holiday-heavy month has fewer than 12 of those; returned in date order.
create or replace function public.fn_marketing_video_days(p_month date, p_n int default 12)
returns setof date language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  select d from (
    select d::date d from generate_series(p_month, (p_month + interval '1 month' - interval '1 day'), interval '1 day') d
     where public.fn_is_working_day(d::date)
     order by (extract(isodow from d) in (1, 3, 4)) desc, d
     limit p_n) x
  order by d
$fn$;
revoke execute on function public.fn_marketing_video_days(date, int) from public, anon, authenticated;

-- On any Dubai day of month M (normally the 1st; later only if the 1st was missed), M+1's plan is owed once.
-- The loop starts with the November 2026 plan (sent 1 Oct 2026). p_today is for the probe only.
create or replace function public.fn_marketing_month_plan_tick(p_today date default null)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  v_today date := coalesce(p_today, (now() at time zone 'Asia/Dubai')::date);
  v_month date := (date_trunc('month', v_today) + interval '1 month')::date;
  v_token text := encode(extensions.gen_random_bytes(16), 'hex'); v_ideas jsonb; v_body text; v_nid bigint; v_mname text;
begin
  if v_month < date '2026-11-01' then return jsonb_build_object('sent', false, 'reason', 'the monthly loop starts with November 2026'); end if;
  -- once per month: a plan already emailed, or one the model path already carried past the CEO, is not replaced
  if exists (select 1 from public.marketing_month_plan where month = v_month
              and (plan_sent_at is not null or status not in ('draft', 'with_ceo'))) then
    return jsonb_build_object('sent', false, 'reason', 'already planned', 'month', v_month);
  end if;
  v_mname := to_char(v_month, 'FMMonth YYYY');
  with days as (select d, row_number() over (order by d) n from public.fn_marketing_video_days(v_month, 12) d),
       picks as (select i.*, row_number() over (order by i.last_planned_month nulls first, i.id) n
                   from public.marketing_video_idea i where i.enabled
                  order by i.last_planned_month nulls first, i.id limit 12)
  select jsonb_agg(jsonb_build_object('n', d.n, 'date', d.d, 'idea_key', p.idea_key, 'title', p.title, 'hook', p.hook,
                                      'film_plan', p.film_plan, 'cta', p.cta, 'audience', p.audience) order by d.n)
    into v_ideas
    from days d join picks p on p.n = d.n;
  if v_ideas is null then raise exception 'marketing_month_plan: no enabled ideas or no working days in %', v_month; end if;

  v_body := 'Here is the video plan for ' || v_mname || ': ' || jsonb_array_length(v_ideas)
         || ' short videos on UAE working days (Monday, Wednesday, Thursday first; no weekends or public holidays).' || E'\n\n'
         || (select string_agg(format(E'%s. %s — %s\n   Hook: %s\n   Film: %s\n   Call to action: %s',
                                      e->>'n', to_char((e->>'date')::date, 'Dy DD Mon'), e->>'title', e->>'hook', e->>'film_plan', e->>'cta'),
                               E'\n\n' order by (e->>'n')::int)
               from jsonb_array_elements(v_ideas) e)
         || E'\n\nWhen the videos are ready, reply to this email with them (attachments or links). Change any idea by saying so in the same reply. '
         || 'The marketing seat then builds the calendar (dates, times per platform, captions, hashtags, links) and sends it to you; '
         || 'replying "approve" to that calendar schedules and publishes it.';
  v_nid := public.fn_marketing_mail_founder('marketing_month_plan', 'Video plan for ' || v_mname || ' [plan ' || v_token || ']',
                                            v_body, null, 'plan+' || v_token || '@mail.quotesdone.com');
  insert into public.marketing_month_plan as t (month, status, verdict, plan, content_brief, plan_token, plan_notification_id, plan_sent_at)
  values (v_month, 'sent_to_founder', jsonb_build_object('by', 'code', 'rule', 'founder 24 Sep 2026: the monthly idea plan is routine work, coded'),
          jsonb_build_object('by', 'code', 'ideas', v_ideas), jsonb_build_object('videos', jsonb_build_object('count', jsonb_array_length(v_ideas)), 'ideas', v_ideas),
          v_token, v_nid, now())
  on conflict (month) do update set status = excluded.status, verdict = coalesce(t.verdict, excluded.verdict), plan = excluded.plan,
         content_brief = excluded.content_brief, plan_token = excluded.plan_token, plan_notification_id = excluded.plan_notification_id,
         plan_sent_at = excluded.plan_sent_at, updated_at = now();
  update public.marketing_video_idea set last_planned_month = v_month
   where idea_key in (select e->>'idea_key' from jsonb_array_elements(v_ideas) e);
  return jsonb_build_object('sent', true, 'month', v_month, 'ideas', jsonb_array_length(v_ideas), 'notification_id', v_nid);
end $fn$;
revoke execute on function public.fn_marketing_month_plan_tick(date) from public, anon, authenticated;

-- p = {token, from_email, authenticated, message_id, text, attachments[]}
create or replace function public.fn_marketing_month_plan_reply(p jsonb)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  m public.marketing_month_plan; v_from text := lower(btrim(coalesce(p->>'from_email', ''))); v_rid bigint; v_msg text; v_out text;
  v_atts text[] := coalesce((select array_agg(x) from jsonb_array_elements_text(coalesce(p->'attachments', '[]'::jsonb)) x), '{}');
begin
  select * into m from public.marketing_month_plan where plan_token = lower(coalesce(p->>'token', '')) for update;
  if v_from is distinct from public.fn_marketing_founder_email() then
    return jsonb_build_object('outcome', 'not_the_founder', 'month', m.month);
  end if;
  if m.month is null then
    v_out := 'unknown_plan';
    v_msg := 'Your reply did not match a video plan email, so nothing was filed. Please reply to the latest plan email.';
  elsif not coalesce((p->>'authenticated')::boolean, false) then
    v_out := 'not_authenticated';
    v_msg := 'A reply to the video plan arrived with your address but our mail server could not verify it came from your mailbox, so nothing was filed. If it was you, reply again from your usual mail app.';
  else
    insert into public.marketing_founder_request (kind, month, founder_text, attachments, message_id)
    values ('month_content', m.month, left(btrim(coalesce(p->>'text', '')), 4000), v_atts, nullif(p->>'message_id', ''))
    on conflict (message_id) where message_id is not null and message_id <> '' do nothing
    returning id into v_rid;
    if v_rid is null then return jsonb_build_object('outcome', 'already_filed', 'month', m.month); end if;
    -- his reply with the content IS his acceptance of the plan (the columns fn_marketing_month_plan_founder_decides writes)
    update public.marketing_month_plan set status = 'accepted', founder_decided_at = now(),
           founder_note = left(btrim(coalesce(p->>'text', '')), 2000), updated_at = now() where month = m.month;
    v_out := 'content_received';
    v_msg := 'Received for ' || to_char(m.month, 'FMMonth YYYY') || ' (' || cardinality(v_atts) || ' attachment(s)). The marketing seat builds the calendar from it '
             || '(request ' || v_rid || ') and emails it to you; reply "approve" to that calendar and it is scheduled and published.';
  end if;
  perform public.fn_marketing_mail_founder('marketing_month_plan_reply',
    case when v_out = 'content_received' then 'Received: ' else 'Not filed: ' end || 'video plan ' || coalesce(to_char(m.month, 'FMMonth YYYY'), ''), v_msg);
  return jsonb_build_object('outcome', v_out, 'month', m.month, 'request_id', v_rid);
end $fn$;
revoke execute on function public.fn_marketing_month_plan_reply(jsonb) from public, anon, authenticated;

-- ── THE DAILY TABLE EXPORT: + the new tables (body of every_verified_pack_has_a_home_and_every_seat_reads_its_own.sql) ──
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
    ('marketing_platform_spec','marketing'), ('marketing_platform_spec_source','marketing'),
    ('marketing_campaign','marketing'), ('marketing_founder_request','marketing'), ('marketing_video_idea','marketing'), ('marketing_post_variant','marketing'),
    ('marketing_post_platform','marketing'), ('marketing_post_metric','marketing'), ('marketing_first_touch','marketing'),
    ('marketing_goal','marketing'), ('marketing_scorecard_report','marketing'),
    ('marketing_asset_feature','marketing'), ('marketing_asset_perception','marketing'), ('marketing_asset_review','marketing'),
    ('marketing_insight_note','marketing'), ('marketing_month_plan','marketing'), ('marketing_plan_review_turn','marketing'),
    ('marketing_model_run','marketing'), ('market_intel','marketing'), ('competitor','marketing'), ('marketing_knowledge','knowledge'),
    ('table_export_change','backup')
  ) v(t, s)
  -- The sibling PRs' tables may not exist yet when this applies; backup/index.ts fails the whole day on a
  -- missing table, so ONLY those nine are skipped until their own file creates them. Every other table in the
  -- list still fails loudly if it disappears.
  where v.t not in ('marketing_platform_spec','marketing_platform_spec_source','marketing_campaign','marketing_post_variant',
                    'marketing_post_platform','marketing_post_metric','marketing_first_touch','marketing_goal','marketing_scorecard_report')
     or to_regclass('public.' || v.t) is not null
$fn$;
update public.resilience_step set note = 'marketing: publishes due posts every beat once the founder has approved the calendar (one "approve"; app_secrets.marketing_publishing_enabled is the emergency stop); on the 1st of each month sends next month''s video idea plan; the access check, insights and ad spend reads run once per Dubai day' where step = 'marketingChannels';

revoke execute on function public.fn_table_export_list() from public, anon, authenticated;
grant execute on function public.fn_table_export_list() to service_role;

commit;
