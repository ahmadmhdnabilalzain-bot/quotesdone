-- THE MARKETING SEAT PUTS ITS PLAN, GEO, ARTICLE, LAUNCH AND COMPETITOR WORK ON A CLOCK.
-- Seat: marketing. 28 Sep 2026.
-- Needs every_seat_duty_has_an_owner_a_clock_and_a_check.sql, one_approve_schedules_and_publishes_the_month_on_working_days.sql,
-- the_marketing_seat_writes_articles_and_drafts_linkedin_outreach.sql, marketing_watches_trends_audits_answer_engines_and_reviews_the_brand_each_quarter.sql,
-- the_ceo_sets_the_target_runs_experiments_and_watches_competitors.sql, pricing_has_no_date_no_discount_and_no_cap.sql.
--
-- WHAT WAS MEASURED (28 Sep 2026, production):
--   * public.seat_duty held THREE marketing rows: recruitment_funnel, reputation, competitor_scan. The monthly plan,
--     the GEO check, the article release and the competitor refresh ran only as steps inside edge functions, with no
--     owner/clock/check row, so an overdue one was never a finding. There was no January 2027 launch plan at all.
--   * marketing_article: 4 rows, all status 'draft', none ever sent to the founder: there was no path by which he
--     could approve one, and fn_marketing_article_approve also accepted p_by = 'claude'.
--   * The OS marketing studio read marketing_kpis.blog_published = 32 (public.blog_posts, the site's 32 legacy pages
--     from src/content/blog.json) and labelled it the blog, while the seat's own article table held 4 drafts.
--   * fn_marketing_studio built every blog link as https://quotesdone.com/blog/<slug>; 4 blog_posts bodies link to
--     quotesdone.com. UAE visitors are served on quotesdone.ae.
--
-- RULES IT KEEPS (founder): organic only until every category has 10 verified suppliers (pricing_config.
-- category_open_min_suppliers, v_category_open); no posting on a UAE weekend or public holiday (fn_is_working_day);
-- routine work is code, not the model - nothing below calls a model; one-shot approval: he replies "approve".
--
-- WHAT THIS ADDS
--   1. fn_marketing_paid_allowed(): true only when every category is open. Every plan below prints it.
--   2. Five seat duties, each a no-argument routine run by fn_seat_duties_tick and checked by fn_seat_duty_health:
--        marketing.month_plan         daily   next month's plan drafted and sent for his one-shot approval
--        marketing.geo_check          daily   this month's answer-engine checks progress; a stall is a failure
--        marketing.article_release    daily   one draft a Dubai week goes to him for "approve"; release checked
--        marketing.launch_plan        daily   the January 2027 launch plan kept current; sent for approval from 1 Dec
--        marketing.competitor_refresh 7 days  the week's competitor intelligence brief, stale profiles re-fetched
--   3. marketing_plan_doc: the launch plan and the weekly competitor brief (one row per kind and period).
--   4. fn_marketing_approval_reply(p): his reply to approve+<token>@mail.quotesdone.com, for an article or the
--      launch plan. Same gate as the calendar: the founder, SPF/DKIM/DMARC-authenticated, exactly "approve".
--   5. Articles are released only when HE approved them, and only on a UAE working day.
--   6. The studio's blog count and list are the seat's article table; the site's legacy pages are shown apart.
--      Blog links point at https://quotesdone.ae.
--
-- Prevented by: scripts/checks/marketing_duties_are_on_a_clock.test.mjs (every duty named here is in seat_duty in
-- the live mirror, and no blog link in the studio or the site content points at quotesdone.com).

-- ── 0. rows the duties write ─────────────────────────────────────────────────────────────────────
alter table public.marketing_article add column if not exists approval_token text unique;
alter table public.marketing_article add column if not exists approval_sent_at timestamptz;
alter table public.marketing_article add column if not exists founder_change_request text;

create table if not exists public.marketing_plan_doc (
  id               bigint generated always as identity primary key,
  kind             text not null check (kind in ('launch_plan', 'competitor_intel')),
  period           date not null,
  body             jsonb not null,
  status           text not null default 'draft' check (status in ('draft', 'sent_to_founder', 'approved', 'change_requested')),
  approval_token   text unique,
  sent_at          timestamptz,
  notification_id  bigint,
  decided_at       timestamptz,
  founder_note     text,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  unique (kind, period)
);
alter table public.marketing_plan_doc enable row level security;
drop policy if exists marketing_plan_doc_service_role_only on public.marketing_plan_doc;
create policy marketing_plan_doc_service_role_only on public.marketing_plan_doc as permissive for all to public using (false) with check (false);
revoke all on public.marketing_plan_doc from anon, authenticated;

insert into public.founder_mail_policy (kind, allowed_to_email, reason, owner_role) values
  ('marketing_article_approval', true, 'Founder, 28 Sep 2026: one article draft a week is sent to him; replying "approve" releases it on the weekly cadence, on a UAE working day.', 'marketing'),
  ('marketing_launch_plan', true, 'Founder, 28 Sep 2026: the January 2027 launch plan is sent to him from 1 December 2026 for his one-shot approval.', 'marketing'),
  ('marketing_approval_reply', true, 'The answer to his reply to an article or launch-plan approval email: approved, or his change passed to the marketing seat.', 'marketing')
on conflict (kind) do update set allowed_to_email = true, reason = excluded.reason, owner_role = excluded.owner_role, updated_at = now();

-- ── 1. organic only until every category has its suppliers ─────────────────────────────────────
create or replace function public.fn_marketing_paid_allowed()
returns boolean language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  select exists (select 1 from public.v_category_open) and not exists (select 1 from public.v_category_open where not is_open)
$fn$;
revoke execute on function public.fn_marketing_paid_allowed() from public, anon, authenticated;

-- ── 2. marketing.month_plan ──────────────────────────────────────────────────────────────────────
-- fn_marketing_month_plan_tick drafts next month's plan and mails it the first time it runs in the month (so it is
-- with him about a month before the month starts); it is idempotent. The duty adds the clock and the check: from the
-- 20th, a month after November 2026 with no plan sent is a failure, not a quiet skip.
create or replace function public.fn_marketing_month_plan_duty()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  v_today date := (now() at time zone 'Asia/Dubai')::date;
  v_month date := (date_trunc('month', v_today) + interval '1 month')::date;
  v_tick jsonb; m public.marketing_month_plan;
begin
  v_tick := public.fn_marketing_month_plan_tick(v_today);
  select * into m from public.marketing_month_plan where month = v_month;
  if v_month >= date '2026-11-01' and extract(day from v_today) >= 20 and m.plan_sent_at is null
     and not public.fn_marketing_month_covered_by_approved_calendar(v_month) then
    raise exception 'the plan for % is not with the founder on %: %', to_char(v_month, 'YYYY-MM'), v_today, v_tick::text;
  end if;
  return jsonb_build_object('month', v_month, 'tick', v_tick, 'status', m.status, 'sent_at', m.plan_sent_at,
    'founder_decided_at', m.founder_decided_at, 'paid_allowed', public.fn_marketing_paid_allowed());
end $fn$;
revoke execute on function public.fn_marketing_month_plan_duty() from public, anon, authenticated;

-- ── 3. marketing.geo_check ───────────────────────────────────────────────────────────────────────
-- Defined in section 9c below, with the answer engines it measures.

-- ── 4. marketing.article_release ─────────────────────────────────────────────────────────────────
-- Only he approves an article (the 'claude' approver is refused from now on).
create or replace function public.fn_marketing_article_approve(p_slug text, p_by text)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_id bigint;
begin
  if p_by is distinct from 'founder' then return jsonb_build_object('ok', false, 'error', 'only_the_founder_approves_an_article'); end if;
  update public.marketing_article set status = 'approved', approved_by = 'founder', approved_at = now(), updated_at = now()
   where slug = p_slug and status = 'draft' returning id into v_id;
  return jsonb_build_object('ok', v_id is not null, 'slug', p_slug, 'error', case when v_id is null then 'not_a_draft' end);
end $fn$;

-- The cadence, now: his approval only, a UAE working day only, at most marketing_articles_per_week a Dubai week and one a day.
create or replace function public.fn_marketing_article_release_due()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  v_now timestamp := now() at time zone 'Asia/Dubai';
  v_week int; v_today int; v_next public.marketing_article;
begin
  if not public.fn_is_working_day(v_now::date) then
    return jsonb_build_object('released', null, 'reason', 'not a UAE working day');
  end if;
  select count(*) filter (where released_at at time zone 'Asia/Dubai' >= date_trunc('week', v_now)),
         count(*) filter (where (released_at at time zone 'Asia/Dubai')::date = v_now::date)
    into v_week, v_today from public.marketing_article where released_at is not null and not is_demo;
  if v_week >= greatest(0, public.fn_marketing_policy_int('marketing_articles_per_week', 2)) or v_today > 0 then
    return jsonb_build_object('released', null, 'this_week', v_week, 'reason', 'cadence');
  end if;
  select * into v_next from public.marketing_article
   where status = 'approved' and approved_by = 'founder' and not is_demo order by approved_at, id limit 1 for update skip locked;
  if not found then return jsonb_build_object('released', null, 'this_week', v_week, 'reason', 'nothing_approved_by_the_founder'); end if;
  if not public.fn_marketing_publishing_live() then
    return jsonb_build_object('released', null, 'held', true, 'would_release', v_next.slug, 'reason', 'marketing_golive is not true');
  end if;
  update public.marketing_article set status = 'released', released_at = now(), updated_at = now() where id = v_next.id;
  return jsonb_build_object('released', v_next.slug, 'this_week', v_week + 1);
end $fn$;

-- The weekly request: on a working day, when no request is open, the oldest draft goes to him once a Dubai week.
-- The release itself stays on marketingOutreach's beat (fn_marketing_article_release_due); this duty checks it moved:
-- an article he approved that has waited 8 days on a live switch is a failure.
create or replace function public.fn_marketing_article_release_duty()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  v_now timestamp := now() at time zone 'Asia/Dubai';
  a public.marketing_article; v_token text; v_nid bigint; v_stuck text; v_sent text;
begin
  select slug into v_stuck from public.marketing_article
   where status = 'approved' and approved_by = 'founder' and not is_demo and approved_at < now() - interval '8 days' limit 1;
  if v_stuck is not null and public.fn_marketing_publishing_live() then
    raise exception 'article % was approved by the founder more than 8 days ago and is not released', v_stuck;
  end if;
  if public.fn_is_working_day(v_now::date)
     and not exists (select 1 from public.marketing_article where status = 'draft' and approval_sent_at is not null and not is_demo
                       and approval_sent_at at time zone 'Asia/Dubai' >= date_trunc('week', v_now)) then
    select * into a from public.marketing_article
     where status = 'draft' and not is_demo and approval_sent_at is null and founder_change_request is null
     order by created_at, id limit 1 for update skip locked;
    if found then
      v_token := encode(extensions.gen_random_bytes(16), 'hex');
      v_nid := public.fn_marketing_mail_founder('marketing_article_approval',
        'Article for this week: ' || left(a.title_en, 120) || ' [approve ' || v_token || ']',
        'This week''s article, ready to publish on quotesdone.ae/blog/' || a.slug || E' in English and Arabic:\n\n'
        || a.title_en || E'\n' || a.excerpt_en || E'\n\n' || a.title_ar || E'\n' || a.excerpt_ar || E'\n\n'
        || 'Reply "approve" and it is released on the next UAE working day (never a weekend or a public holiday) with its LinkedIn post. '
        || 'Any other reply is passed to the marketing seat as a change and nothing is published.',
        null, 'approve+' || v_token || '@mail.quotesdone.com');
      update public.marketing_article set approval_token = v_token, approval_sent_at = now(), updated_at = now() where id = a.id;
      v_sent := a.slug;
    end if;
  end if;
  return jsonb_build_object('requested', v_sent,
    'drafts', (select count(*) from public.marketing_article where status = 'draft' and not is_demo),
    'awaiting_founder', (select count(*) from public.marketing_article where status = 'draft' and approval_sent_at is not null and not is_demo),
    'approved', (select count(*) from public.marketing_article where status = 'approved' and not is_demo),
    'live', (select count(*) from public.marketing_article where status = 'live' and not is_demo));
end $fn$;
revoke execute on function public.fn_marketing_article_release_duty() from public, anon, authenticated;

-- ── 5. marketing.launch_plan ─────────────────────────────────────────────────────────────────────
-- Code only: the plan is the readiness of every category, the channels the rule allows, and the January 2027
-- working days to post on. Redrawn every day while it is a draft; from 1 December 2026 it goes to him once.
create or replace function public.fn_marketing_launch_plan_duty()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  v_today date := (now() at time zone 'Asia/Dubai')::date;
  v_launch date := date '2027-01-01';
  v_body jsonb; d public.marketing_plan_doc; v_token text; v_nid bigint; v_paid boolean := public.fn_marketing_paid_allowed();
  v_open int; v_total int; v_short jsonb;
begin
  select count(*) filter (where is_open), count(*) into v_open, v_total from public.v_category_open;
  select coalesce(jsonb_agg(jsonb_build_object('category', name, 'verified', verified_registered_suppliers, 'needed', min_required)
           order by min_required - verified_registered_suppliers desc, num), '[]'::jsonb)
    into v_short from public.v_category_open where not is_open;
  v_body := jsonb_build_object(
    'launch_month', v_launch, 'drawn_on', v_today,
    'categories', jsonb_build_object('open', v_open, 'total', v_total, 'short', v_short),
    'paid_allowed', v_paid,
    'channels', case when v_paid then jsonb_build_array('organic social', 'blog and GEO', 'LinkedIn outreach', 'paid Meta within the ad cap')
                     else jsonb_build_array('organic social', 'blog and GEO', 'LinkedIn outreach') end,
    'rule', 'Organic only until every category has its verified suppliers; no post on a UAE weekend or public holiday.',
    'posting_days', (select coalesce(jsonb_agg(g::date order by g), '[]'::jsonb)
                       from generate_series(v_launch, date '2027-01-31', interval '1 day') g where public.fn_is_working_day(g::date)),
    'articles_ready', (select count(*) from public.marketing_article where status in ('approved', 'released', 'live') and not is_demo),
    'supplier_recruitment', (select last_result from public.seat_duty where duty = 'marketing.recruitment_funnel'));
  insert into public.marketing_plan_doc (kind, period, body) values ('launch_plan', v_launch, v_body)
  on conflict (kind, period) do update set body = excluded.body, updated_at = now()
    where marketing_plan_doc.status in ('draft', 'change_requested')
  returning * into d;
  if d.id is null then select * into d from public.marketing_plan_doc where kind = 'launch_plan' and period = v_launch; end if;

  if v_today >= date '2026-12-01' and v_today < v_launch and d.status in ('draft', 'change_requested') then
    v_token := encode(extensions.gen_random_bytes(16), 'hex');
    v_nid := public.fn_marketing_mail_founder('marketing_launch_plan', 'Launch plan for January 2027 [approve ' || v_token || ']',
      'The launch plan for January 2027.' || E'\n\n'
      || 'Categories open: ' || v_open || ' of ' || v_total || ' (a category opens at its verified supplier minimum).' || E'\n'
      || 'Channels: ' || (select string_agg(x, ', ') from jsonb_array_elements_text(v_body->'channels') x)
      || case when v_paid then '' else ' - organic only, because not every category is open yet.' end || E'\n'
      || 'Posting days: ' || jsonb_array_length(v_body->'posting_days') || ' UAE working days (no weekends or public holidays).' || E'\n'
      || 'Articles approved and ready: ' || (v_body->>'articles_ready') || E'\n\n'
      || 'Reply "approve" and the marketing seat runs it. Any other reply is passed to the seat as a change.',
      null, 'approve+' || v_token || '@mail.quotesdone.com');
    update public.marketing_plan_doc set status = 'sent_to_founder', approval_token = v_token, sent_at = now(), notification_id = v_nid, updated_at = now()
     where id = d.id;
    d.status := 'sent_to_founder';
  end if;
  return jsonb_build_object('status', d.status, 'open', v_open, 'total', v_total, 'paid_allowed', v_paid,
    'posting_days', jsonb_array_length(v_body->'posting_days'));
end $fn$;
revoke execute on function public.fn_marketing_launch_plan_duty() from public, anon, authenticated;

-- ── 6. marketing.competitor_refresh ──────────────────────────────────────────────────────────────
-- The week's brief from what the hourly scan and the Instagram study already collected; a profile unverified for
-- 90 days is re-fetched now (its old scan rows are older than 30 days, so fn_marketing_competitor_scan requests it).
create or replace function public.fn_marketing_competitor_refresh_duty()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  v_week date := date_trunc('week', now() at time zone 'Asia/Dubai')::date;
  v_body jsonb; v_stale int;
begin
  select count(*) into v_stale from public.competitor
   where watched and kind <> 'incumbent_behaviour' and (verified_at is null or verified_at < current_date - 90);
  v_body := jsonb_build_object(
    'week', v_week,
    'watched', (select count(*) from public.competitor where watched),
    'stale_profiles', v_stale,
    'changes', (select coalesce(jsonb_agg(jsonb_build_object('competitor', c.name, 'page', s.page_kind, 'decision', s.decision,
                  'what_changed', s.fields->>'what_changed', 'ceo_task', s.task_id) order by s.decided_at), '[]'::jsonb)
                  from public.competitor_scan s join public.competitor c on c.id = s.competitor_id
                 where s.decided_at >= now() - interval '7 days'),
    'fetch_failures', (select count(*) from public.competitor_scan where status = 'failed' and requested_at >= now() - interval '7 days'),
    'social_posts_seen', (select count(*) from public.market_intel where platform = 'instagram' and fetched_at >= now() - interval '7 days'),
    'scan', public.fn_marketing_competitor_scan());
  insert into public.marketing_plan_doc (kind, period, body) values ('competitor_intel', v_week, v_body)
  on conflict (kind, period) do update set body = excluded.body, updated_at = now();
  return v_body - 'changes';
end $fn$;
revoke execute on function public.fn_marketing_competitor_refresh_duty() from public, anon, authenticated;

-- ── 7. his reply to approve+<token> ──────────────────────────────────────────────────────────────
-- p = {token, from_email, authenticated, intent ('approve'|'change'|'unclear'), text, message_id}
create or replace function public.fn_marketing_approval_reply(p jsonb)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  v_token text := lower(coalesce(p->>'token', '')); v_from text := lower(btrim(coalesce(p->>'from_email', '')));
  a public.marketing_article; d public.marketing_plan_doc; v_out text; v_what text; v_msg text;
begin
  if v_from is distinct from public.fn_marketing_founder_email() then return jsonb_build_object('outcome', 'not_the_founder'); end if;
  select * into a from public.marketing_article where approval_token = v_token and v_token <> '' for update;
  if a.id is null then select * into d from public.marketing_plan_doc where approval_token = v_token and v_token <> '' for update; end if;
  v_what := coalesce('article "' || a.title_en || '"', case when d.id is not null then 'launch plan for ' || to_char(d.period, 'FMMonth YYYY') end);
  if v_what is null then
    v_out := 'unknown'; v_msg := 'Your reply did not match an approval email, so nothing was changed. Please reply to the latest one.';
  elsif not coalesce((p->>'authenticated')::boolean, false) then
    v_out := 'not_authenticated';
    v_msg := 'A reply about the ' || v_what || ' arrived with your address but could not be verified as coming from your mailbox, so nothing was changed.';
  elsif (a.id is not null and a.status <> 'draft') or (d.id is not null and d.status <> 'sent_to_founder') then
    v_out := 'already_decided'; v_msg := 'The ' || v_what || ' was already decided; nothing was changed.';
  elsif p->>'intent' = 'approve' then
    if a.id is not null then perform public.fn_marketing_article_approve(a.slug, 'founder');
    else update public.marketing_plan_doc set status = 'approved', decided_at = now(), updated_at = now() where id = d.id; end if;
    v_out := 'approved';
    v_msg := 'Approved: the ' || v_what || '. ' || case when a.id is not null
      then 'It is released on the next UAE working day on the weekly cadence.' else 'The marketing seat runs it from 1 January 2027.' end;
  else
    if a.id is not null then
      update public.marketing_article set founder_change_request = left(btrim(coalesce(p->>'text', '')), 4000), approval_token = null, updated_at = now() where id = a.id;
    else
      update public.marketing_plan_doc set status = 'change_requested', founder_note = left(btrim(coalesce(p->>'text', '')), 4000),
             approval_token = null, decided_at = now(), updated_at = now() where id = d.id;
    end if;
    v_out := 'change_requested';
    v_msg := 'Your change to the ' || v_what || ' was passed to the marketing seat; nothing is published until you approve the new version.';
  end if;
  perform public.fn_marketing_mail_founder('marketing_approval_reply',
    case when v_out = 'approved' then 'Approved: ' when v_out = 'change_requested' then 'Change noted: ' else 'Not changed: ' end || coalesce(v_what, 'approval'), v_msg);
  return jsonb_build_object('outcome', v_out, 'article', a.slug, 'plan_doc', d.id);
end $fn$;
revoke execute on function public.fn_marketing_approval_reply(jsonb) from public, anon, authenticated;

-- ── 8. the register ──────────────────────────────────────────────────────────────────────────────
insert into public.seat_duty (duty, owner_seat, every, routine, what, owner_file) values
  ('marketing.month_plan', 'marketing', interval '1 day', 'fn_marketing_month_plan_duty',
   'Next month''s plan drafted and mailed to the founder for his one-shot approval the first day of the month; from the 20th a missing plan is a failure.',
   'scripts/sql/the_marketing_seat_puts_its_plan_geo_articles_launch_and_competitor_work_on_a_clock.sql'),
  ('marketing.geo_check', 'marketing', interval '1 day', 'fn_marketing_geo_check_duty',
   'The month''s answer-engine (GEO) checks progress; from the 10th, web checks owed with none in two days is a failure.',
   'scripts/sql/the_marketing_seat_puts_its_plan_geo_articles_launch_and_competitor_work_on_a_clock.sql'),
  ('marketing.article_release', 'marketing', interval '1 day', 'fn_marketing_article_release_duty',
   'One article draft a Dubai week is sent to the founder for "approve"; only his approval releases it, on a UAE working day.',
   'scripts/sql/the_marketing_seat_puts_its_plan_geo_articles_launch_and_competitor_work_on_a_clock.sql'),
  ('marketing.launch_plan', 'marketing', interval '1 day', 'fn_marketing_launch_plan_duty',
   'The January 2027 launch plan redrawn daily from category readiness (organic only until every category is open) and sent for approval from 1 December.',
   'scripts/sql/the_marketing_seat_puts_its_plan_geo_articles_launch_and_competitor_work_on_a_clock.sql'),
  ('marketing.competitor_refresh', 'marketing', interval '7 days', 'fn_marketing_competitor_refresh_duty',
   'The week''s competitor intelligence brief (changes, failures, social posts seen, stale profiles) kept in marketing_plan_doc.',
   'scripts/sql/the_marketing_seat_puts_its_plan_geo_articles_launch_and_competitor_work_on_a_clock.sql')
on conflict (duty) do update set every = excluded.every, routine = excluded.routine, what = excluded.what,
  owner_file = excluded.owner_file, enabled = true;

-- ── 9. the studio counts the seat's articles; blog links point at quotesdone.ae ────────────────────
create or replace view public.marketing_kpis as
 WITH f AS (SELECT funnel_metrics(30) AS fm),
 mi AS (
   SELECT COALESCE(sum(meta_insights.spend), 0::numeric) AS meta_spend, COALESCE(sum(meta_insights.impressions), 0::numeric) AS meta_impr,
          COALESCE(sum(meta_insights.clicks), 0::numeric) AS meta_clicks, COALESCE(sum(meta_insights.results), 0::numeric) AS meta_results,
          count(*) FILTER (WHERE meta_insights.effective_status = 'ACTIVE'::text) AS meta_active
     FROM meta_insights WHERE meta_insights.time_window = 'last_30d'::text AND meta_insights.campaign_name ~~* '%quotesdone%'::text)
 SELECT (f.fm ->> 'inquiries')::integer AS inquiries_30d, (f.fm ->> 'matched')::integer AS matched_30d,
    (f.fm ->> 'quoted')::integer AS quoted_30d, (f.fm ->> 'revealed')::integer AS revealed_30d,
    (f.fm ->> 'reveal_fees')::numeric AS revenue_30d,
    CASE WHEN (f.fm ->> 'inquiries')::integer > 0 THEN round(100.0 * ((f.fm ->> 'quoted')::integer)::numeric / ((f.fm ->> 'inquiries')::integer)::numeric, 1) ELSE NULL::numeric END AS inq_to_quote_pct,
    CASE WHEN (f.fm ->> 'quoted')::integer > 0 THEN round(100.0 * ((f.fm ->> 'revealed')::integer)::numeric / ((f.fm ->> 'quoted')::integer)::numeric, 1) ELSE NULL::numeric END AS quote_to_reveal_pct,
    -- the seat's articles (marketing_article), not the site's legacy pages (site_blog_pages below)
    (SELECT count(*) FROM marketing_article WHERE status = 'live' AND NOT is_demo) AS blog_published,
    (SELECT count(*) FROM marketing_article WHERE status <> 'withdrawn' AND NOT is_demo) AS blog_total,
    (SELECT count(*) FROM content_drafts WHERE COALESCE(content_drafts.status, ''::text) <> ALL (ARRAY['published'::text, 'discarded'::text])) AS drafts_pending,
    (SELECT count(*) FROM social_posts WHERE COALESCE(social_posts.status, ''::text) = ANY (ARRAY['staged'::text, 'scheduled'::text, 'draft'::text, 'pending'::text])
        OR social_posts.mode = 'draft'::text AND COALESCE(social_posts.status, ''::text) = ANY (ARRAY['published'::text, 'sent'::text])) AS social_staged,
    (SELECT count(*) FROM social_posts WHERE social_posts.mode = 'now'::text AND COALESCE(social_posts.status, ''::text) = ANY (ARRAY['published'::text, 'sent'::text])) AS social_published,
    (SELECT count(*) FROM seo_categories) AS seo_pages,
    (SELECT count(*) FROM seo_categories WHERE seo_categories.generated) AS seo_generated,
    (SELECT count(*) FROM leads) AS leads_total,
    (SELECT count(*) FROM outreach) AS outreach_sent,
    (SELECT COALESCE(gl_account_balances.balance, 0::numeric) FROM gl_account_balances WHERE gl_account_balances.code = '6200'::text) AS mkt_spend,
    (SELECT count(*) FROM customers WHERE customers.created_at >= (now() - '30 days'::interval)) AS new_customers_30d,
    CASE WHEN mi.meta_spend > 0::numeric THEN round(mi.meta_spend / NULLIF((SELECT count(*) FROM customers WHERE customers.created_at >= (now() - '30 days'::interval)), 0)::numeric, 2) ELSE NULL::numeric END AS cac,
    CASE WHEN mi.meta_spend > 0::numeric THEN round((f.fm ->> 'reveal_fees')::numeric / mi.meta_spend, 2)
         WHEN (SELECT COALESCE(gl_account_balances.balance, 0::numeric) FROM gl_account_balances WHERE gl_account_balances.code = '6200'::text) > 0::numeric
           THEN round((f.fm ->> 'reveal_fees')::numeric / (SELECT COALESCE(gl_account_balances.balance, 0::numeric) FROM gl_account_balances WHERE gl_account_balances.code = '6200'::text), 2)
         ELSE NULL::numeric END AS roi,
    (SELECT count(*) FROM marketing_category_demand WHERE marketing_category_demand.inquiries_90d > 0 AND marketing_category_demand.suppliers = 0) AS supply_gaps,
    (SELECT count(*) FROM marketing_category_demand WHERE NOT marketing_category_demand.has_seo_page) AS seo_gaps,
    mi.meta_spend AS meta_spend_30d, mi.meta_impr AS meta_impressions_30d, mi.meta_clicks AS meta_clicks_30d,
    mi.meta_results AS meta_results_30d, mi.meta_active AS meta_active_campaigns,
    CASE WHEN mi.meta_results > 0::numeric THEN round(mi.meta_spend / mi.meta_results, 2) ELSE NULL::numeric END AS meta_cpl,
    CASE WHEN mi.meta_spend > 0::numeric THEN round((f.fm ->> 'reveal_fees')::numeric / mi.meta_spend, 2) ELSE NULL::numeric END AS meta_roi,
    (SELECT count(*) FROM marketing_article WHERE status = 'draft' AND NOT is_demo) AS blog_drafts,
    (SELECT count(*) FROM blog_posts WHERE blog_posts.published) AS site_blog_pages
   FROM f, mi;

CREATE OR REPLACE FUNCTION public.fn_marketing_studio()
 RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_catalog'
AS $function$
  select jsonb_build_object(
    'kpis', (select to_jsonb(k) from marketing_kpis k limit 1),
    'trend', coalesce((select jsonb_agg(jsonb_build_object(
        'd', to_char(s.snapshot_date,'Mon DD'),
        'leads', nullif(s.kpis->>'leads_total','')::numeric,
        'blog', nullif(s.kpis->>'blog_published','')::numeric,
        'social', nullif(s.kpis->>'social_published','')::numeric,
        'seo', nullif(s.kpis->>'seo_pages','')::numeric
      ) order by s.snapshot_date) from marketing_snapshots s),'[]'::jsonb),
    -- the pipeline's own smoke rows (source = 'selftest') are not posts anyone prepared or designed
    'social', coalesce((select jsonb_agg(jsonb_build_object(
        'id', p.id, 'image_url', p.image_url,
        'text', coalesce(p.content->>'all', p.content->>'text', left(p.content::text,400)),
        'channels', to_jsonb(p.channels), 'status', p.status, 'mode', p.mode, 'error', p.error, 'created_at', p.created_at,
        'live', (p.mode = 'now' and p.status in ('sent','published')),
        'permalinks', p.permalinks, 'permalink_missing', p.permalink_missing,
        'media_missing', p.media_missing, 'preview_url', p.preview_url
      ) order by p.created_at desc) from social_posts p where coalesce(p.source, '') <> 'selftest'),'[]'::jsonb),
    -- the blog is the seat's article table: the same rows the count above reads
    'blog', coalesce((select jsonb_agg(jsonb_build_object(
        'id', a.id, 'title', a.title_en, 'slug', a.slug, 'category', a.category_en, 'excerpt', a.excerpt_en,
        'status', a.status, 'published', a.status = 'live', 'published_at', a.live_at, 'body_html', left(a.body_html_en, 24000),
        'url', case when a.status = 'live' then 'https://quotesdone.ae/blog/' || a.slug end
      ) order by a.updated_at desc) from marketing_article a where not a.is_demo),'[]'::jsonb),
    'site_blog', coalesce((select jsonb_agg(jsonb_build_object(
        'id', b.id, 'title', b.title, 'slug', b.slug, 'published', b.published,
        'url', case when b.published and b.slug is not null then 'https://quotesdone.ae/blog/' || b.slug end
      ) order by b.updated_at desc) from blog_posts b),'[]'::jsonb),
    'review', (select coalesce(fn_review_pending(),'[]'::jsonb))
  );
$function$;

-- The site's legacy pages linked to quotesdone.com; the same text in src/content/blog.json is corrected in this PR.
update public.blog_posts set body_html = replace(replace(body_html, 'https://www.quotesdone.com', 'https://quotesdone.ae'),
                                                 'https://quotesdone.com', 'https://quotesdone.ae'), updated_at = now()
 where body_html like '%quotesdone.com%';

-- ── 9b. the new table is in the daily export (every_marketing_table_is_in_the_daily_export) ─────────
-- The definition from the_calendar_resend_decisions_are_in_the_daily_export.sql with marketing_plan_doc added.
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
    ('marketing_campaign','marketing'), ('marketing_founder_request','marketing'), ('marketing_video_idea','marketing'), ('supplier_campaign_daily_list','supplier'), ('marketing_post_variant','marketing'),
    ('marketing_post_platform','marketing'), ('marketing_post_channel_result','marketing'), ('marketing_calendar_resend_decision','marketing'), ('marketing_plan_doc','marketing'), ('marketing_post_metric','marketing'), ('marketing_first_touch','marketing'),
    ('marketing_goal','marketing'), ('marketing_scorecard_report','marketing'),
    ('marketing_asset_feature','marketing'), ('marketing_asset_perception','marketing'), ('marketing_asset_review','marketing'),
    ('marketing_insight_note','marketing'), ('marketing_month_plan','marketing'), ('marketing_plan_review_turn','marketing'),
    ('marketing_model_run','marketing'), ('marketing_trend_source','marketing'), ('marketing_trend','marketing'),
    ('marketing_geo_question','marketing'), ('marketing_geo_check','marketing'), ('marketing_review','marketing'), ('market_intel','marketing'), ('competitor','marketing'), ('marketing_knowledge','knowledge'),
    ('table_export_change','backup')
  ) v(t, s)
  -- The sibling PRs' tables may not exist yet when this applies; backup/index.ts fails the whole day on a
  -- missing table, so ONLY those nine are skipped until their own file creates them. Every other table in the
  -- list still fails loudly if it disappears.
  where v.t not in ('marketing_platform_spec','marketing_platform_spec_source','marketing_campaign','marketing_post_variant',
                    'marketing_post_platform','marketing_post_metric','marketing_first_touch','marketing_goal','marketing_scorecard_report')
     or to_regclass('public.' || v.t) is not null
$fn$;

-- ── 9c. GEO IS MEASURED IN THE ANSWER ENGINES THEMSELVES ─────────────────────────────────────────
-- Measured 28 Sep 2026: 0 marketing_geo_check rows ever; the edge geo_audit's DuckDuckGo scrape is answered with a
-- bot-check page from every datacenter call (finding duty:marketing_duties:geo_audit). GEO means being named by AI
-- answer engines, so they are asked directly through ai_gateway (coordinator, 28 Sep 2026): perplexity/sonar (a
-- web-search answer engine) and the :online (web-grounded) variant of a routed model. No new key: both go through
-- the existing OpenRouter gateway. A fixed set of 12 questions a month (6 trades x Dubai, Abu Dhabi) x 2 engines =
-- 24 calls a month, bounded by 500 output tokens each; the estimate is well under USD 1 a month against the
-- USD 1-2/day idle ceiling. Prices below are OpenRouter's list prices as last known, NOT measured on this estate.
-- THE FOUNDER'S HOLD IS NOT TOUCHED: both new routes get llm_route_health rows held to the same date as every
-- other route (fn_llm_preflight refuses an unmeasured or held route), and the edge duty calls nothing while held.
alter table public.marketing_geo_question add column if not exists trade text;
alter table public.marketing_geo_question add column if not exists city text;
alter table public.marketing_geo_check add column if not exists competitors_cited text[] not null default '{}';
alter table public.marketing_geo_check drop constraint if exists marketing_geo_check_engine_check;
alter table public.marketing_geo_check add constraint marketing_geo_check_engine_check
  check (engine in ('web', 'model', 'answer_search', 'answer_online'));

-- the generic six are replaced by the trade x city set (their rows, none today, would stay readable)
update public.marketing_geo_question set active = false where trade is null;
insert into public.marketing_geo_question (question, audience, trade, city)
select format('Where can I get quotes from several %s in %s?', t.label, c.city), 'customer', t.trade, c.city
  from (values ('interior_fitout', 'fit-out contractors'), ('mep_general', 'MEP contractors'), ('hvac', 'HVAC and AC contractors'),
               ('electrical', 'electrical contractors'), ('waterproofing', 'waterproofing contractors'), ('steel', 'steel and rebar suppliers')) t(trade, label)
  cross join (values ('Dubai'), ('Abu Dhabi')) c(city)
on conflict (question) do update set active = true, trade = excluded.trade, city = excluded.city;

create or replace function public.fn_marketing_geo_due(p_limit integer default 2, p_include_model boolean default true)
returns table (question_id bigint, question text, engine text, month date)
language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  with m as (select date_trunc('month', now() at time zone 'Asia/Dubai')::date as month)
  select q.id, q.question, e.engine, m.month
    from public.marketing_geo_question q cross join (values ('answer_search'), ('answer_online')) e(engine) cross join m
   where q.active and p_include_model and not exists (select 1 from public.marketing_geo_check c
                                   where c.month = m.month and c.question_id = q.id and c.engine = e.engine)
   order by q.id, e.engine limit greatest(p_limit, 0)
$fn$;

drop function if exists public.fn_marketing_geo_record(date, bigint, text, boolean, integer, text, text);
create function public.fn_marketing_geo_record(p_month date, p_question_id bigint, p_engine text, p_cited boolean,
  p_rank integer, p_evidence text, p_model text, p_competitors text[] default '{}')
returns bigint language sql security definer set search_path to 'public', 'pg_temp' as $fn$
  insert into public.marketing_geo_check (month, question_id, engine, cited, rank, evidence, model, competitors_cited)
  values (p_month, p_question_id, p_engine, p_cited, p_rank, left(p_evidence, 2000), p_model, coalesce(p_competitors, '{}'))
  on conflict (month, question_id, engine) do update set cited = excluded.cited, rank = excluded.rank, evidence = excluded.evidence,
    model = excluded.model, competitors_cited = excluded.competitors_cited, checked_at = now()
  returning id
$fn$;
revoke execute on function public.fn_marketing_geo_record(date, bigint, text, boolean, integer, text, text, text[]) from public, anon, authenticated;
grant execute on function public.fn_marketing_geo_record(date, bigint, text, boolean, integer, text, text, text[]) to service_role;

create or replace function public.fn_marketing_geo_summary(p_month date)
returns jsonb language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  select jsonb_build_object('month', p_month,
    'questions', (select count(distinct question_id) from public.marketing_geo_check where month = p_month),
    'answer_checked', (select count(*) from public.marketing_geo_check where month = p_month and engine like 'answer_%'),
    'answer_cited', (select count(*) from public.marketing_geo_check where month = p_month and engine like 'answer_%' and cited),
    'by_engine', (select coalesce(jsonb_object_agg(engine, jsonb_build_object('checked', n, 'cited', k)), '{}'::jsonb)
                    from (select engine, count(*) n, count(*) filter (where cited) k from public.marketing_geo_check where month = p_month group by engine) e),
    'competitors_cited', (select coalesce(jsonb_object_agg(name, n), '{}'::jsonb)
                            from (select x name, count(*) n from public.marketing_geo_check, unnest(competitors_cited) x
                                   where month = p_month group by x) z),
    'blog_posts_published', (select count(*) from public.blog_posts where published),
    'rows', (select coalesce(jsonb_agg(jsonb_build_object('question', q.question, 'trade', q.trade, 'city', q.city, 'engine', c.engine,
               'cited', c.cited, 'competitors', c.competitors_cited, 'evidence', left(c.evidence, 300)) order by q.id, c.engine), '[]'::jsonb)
               from public.marketing_geo_check c join public.marketing_geo_question q on q.id = c.question_id where c.month = p_month))
$fn$;

insert into public.model_registry (model_id, provider, tier, in_per_mtok_usd, out_per_mtok_usd, supports_cache, supports_streaming,
                                   context_len, approved, active, note, supports_vision, supports_audio, supports_tools)
values ('perplexity/sonar', 'perplexity', 'small', 1, 1, false, true, 127000, true, true,
        'GEO answer engine (marketing_geo_search), 28 Sep 2026. Web-search answers with citations. USD 1/1 per Mtok plus a per-request search fee, OpenRouter list price as last known; NOT measured on this estate.',
        false, false, false)
on conflict (model_id) do nothing;
insert into public.model_registry (model_id, provider, tier, in_per_mtok_usd, out_per_mtok_usd, cache_read_per_mtok_usd, cache_write_per_mtok_usd,
                                   supports_cache, supports_streaming, context_len, approved, active, quality_score, note, supports_vision, supports_audio, supports_tools)
select 'google/gemini-3.8-flash:online', provider, tier, in_per_mtok_usd, out_per_mtok_usd, cache_read_per_mtok_usd, cache_write_per_mtok_usd,
       supports_cache, supports_streaming, context_len, true, true, quality_score,
       'GEO answer engine (marketing_geo_online), 28 Sep 2026: the web-grounded :online variant of google/gemini-3.8-flash. Token prices copied from the base row; OpenRouter adds a web-search fee per request (list price, NOT measured on this estate).',
       supports_vision, supports_audio, supports_tools
  from public.model_registry where model_id = 'google/gemini-3.8-flash'
on conflict (model_id) do nothing;

-- held exactly like every other route (the same open_until and the founder's own words)
insert into public.llm_route_health (model_id, open_until, opened_reason, updated_at)
select m, h.open_until, h.opened_reason, now()
  from (values ('perplexity/sonar'), ('google/gemini-3.8-flash:online')) v(m)
 cross join lateral (select open_until, opened_reason from public.llm_route_health order by open_until desc nulls last limit 1) h
on conflict (model_id) do nothing;

insert into public.model_policy (task_class, tier, model_primary, model_fallback, max_tokens, rationale, deterministic_alternative, active, cache_ttl_min) values
 ('marketing_geo_search', 'small', 'perplexity/sonar', null, 500,
  'GEO: ask a web-search answer engine the month''s trade x city buyer question; code reads whether QuotesDone and which competitors are named. The engine IS the measurement, so there is no fallback: another model would measure something else.',
  'Citation and competitor matching are code (modelCitation, competitorsNamed)', true, 0),
 ('marketing_geo_online', 'small', 'google/gemini-3.8-flash:online', null, 500,
  'GEO: the same question to a routed model''s web-grounded (:online) variant. No fallback, for the same reason.',
  'Citation and competitor matching are code (modelCitation, competitorsNamed)', true, 0)
on conflict (task_class) do update set tier = excluded.tier, model_primary = excluded.model_primary, model_fallback = excluded.model_fallback,
  max_tokens = excluded.max_tokens, rationale = excluded.rationale, deterministic_alternative = excluded.deterministic_alternative,
  active = excluded.active, cache_ttl_min = excluded.cache_ttl_min;

-- The duty's clock: while the founder's hold stands, no answer engine may be called, so owed checks are "held", not a
-- stall. Once open, from the 10th, checks owed with none recorded in two days is a failure.
create or replace function public.fn_marketing_geo_check_duty()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  v_today date := (now() at time zone 'Asia/Dubai')::date;
  v_month date := date_trunc('month', v_today)::date;
  v_owed int; v_last timestamptz; v_held boolean;
begin
  v_held := not coalesce((public.fn_kernel_paid_provider_gate('perplexity/sonar')->>'allowed')::boolean, false);
  select count(*) into v_owed from public.fn_marketing_geo_due(1000, true);
  select max(checked_at) into v_last from public.marketing_geo_check where engine like 'answer_%';
  if not v_held and v_owed > 0 and extract(day from v_today) >= 10 and (v_last is null or v_last < now() - interval '2 days') then
    raise exception 'GEO: % answer-engine check(s) owed for % and none recorded since %', v_owed, to_char(v_month, 'YYYY-MM'),
      coalesce(to_char(v_last, 'YYYY-MM-DD HH24:MI'), 'ever');
  end if;
  return jsonb_build_object('month', v_month, 'owed', v_owed, 'held_by_founder', v_held, 'last_check', v_last,
    'summary', public.fn_marketing_geo_summary(v_month) - 'rows');
end $fn$;
revoke execute on function public.fn_marketing_geo_check_duty() from public, anon, authenticated;

-- ── 10. verdict (no probe rows: every duty above reads, and the mail it could send is gated by date or state) ──
select case
  when 'marketing_plan_doc' <> all (select table_name from public.fn_table_export_list()) then 'PROBE FAILED: marketing_plan_doc is not exported'
  when (select count(*) from public.seat_duty where owner_seat = 'marketing') < 8 then 'PROBE FAILED: marketing seat duties not registered'
  when exists (select 1 from public.blog_posts where body_html like '%quotesdone.com%') then 'PROBE FAILED: a blog page still links to quotesdone.com'
  when (select blog_total from public.marketing_kpis) <> (select count(*) from public.marketing_article where status <> 'withdrawn' and not is_demo)
    then 'PROBE FAILED: the studio blog count is not the article table'
  else 'PROBE OK' end as verdict;
