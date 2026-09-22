-- THE MARKETING SEAT WRITES ARTICLES AND DRAFTS THE FOUNDER'S LINKEDIN OUTREACH (22 Sep 2026; seat: marketing).
--
-- Founder, instruction 722: "the marketing agent is also business development: on LinkedIn every day he texts
-- two or three connections, and writes blogs about our company, soft invitations; no one should feel he is an
-- agent -- replies extremely professional." Supplier invitations are NOT this (instruction 625: a separate
-- campaign with its own gate).
--
-- WHAT WAS MEASURED (22 Sep 2026, read-only):
--   * The website already has the blog: /blog and /blog/[slug] render src/content/blog.json (32 posts, EN + AR),
--     with BlogPosting + BreadcrumbList structured data (src/app/[locale]/blog/[slug]/page.tsx) and every post
--     in the sitemap (src/app/sitemap.xml/route.ts). It is BAKED at build: a post reaches the site through a
--     commit to blog.json, not at request time. Nothing is added to the site; the seat's articles are baked
--     in by scripts/marketing/business_development.mjs bake.
--   * LinkedIn: no LinkedIn credential exists; the company page is reached through Postiz's linkedin-page
--     channel (#834). LinkedIn's API gives an ordinary app no member messaging and no connection list, and
--     its User Agreement 8.2 forbids bots, automated messaging and scraping. Every GitHub tool found that
--     sends or reads member messages drives a logged-in browser session or the private Voyager API (PR body:
--     the assessment). So the seat never touches LinkedIn for outreach: it drafts, the founder sends.
--   * app_secrets.marketing_golive = 'false'. org_role has no 'marketing' role yet (ceo/the-marketing-seat-exists).
--
-- WHAT THIS BUILDS:
--   marketing_article               the seat's articles: EN + AR, sources cited, the lint and grounding result
--                                   recorded; draft -> approved (founder or Claude) -> released by the weekly
--                                   cadence -> live once its page answers; its LinkedIn post is a
--                                   marketing_post draft (#834's store) scheduled only when the page is live
--   marketing_prospect              people researched from PUBLIC sources only, each with its source URLs
--   marketing_outreach_message      the 2-3 daily drafts and the follow-ups, each with a one-tap mark token
--   marketing_bd_figures            the counts fn_marketing_report_figures can read (view)
--   fn_marketing_publishing_live    the ONE switch read: app_secrets.marketing_golive
--   fn_marketing_article_*          ingest / approve / release_due / mark_live
--   fn_marketing_prospect_upsert, fn_marketing_outreach_due / _record / _deliver / _page / _mark
--   founder_mail_policy             + marketing_outreach_list (the morning list, email only)
--   fn_table_export_list            + the three tables (copied from #834's definition)
--   the credential fn.marketing_outreach, its function_owner row and the resilience step marketingOutreach
--
-- WHAT IT DELIBERATELY DOES NOT DO:
--   * Nothing is sent or published while app_secrets.marketing_golive is not 'true': the morning list is
--     composed as DRAFT messages (prospects are not used up), no email reaches the founder, no article is
--     released, no LinkedIn post is scheduled. ZZ DEMO rows are never released, listed or emailed.
--   * No automated LinkedIn action exists or can be wired from here: the tables hold drafts and marks.
--   * The seat does not write article prose by model (the model hold); articles are written by the founder
--     and Claude and INGESTED, and the gate refuses any number the cited sources do not contain.
--   * fn_marketing_report_figures (#834) is not edited: it should add
--     'business_development', (select to_jsonb(f) from public.marketing_bd_figures f) -- listed in the PR.
--   * DEPENDS ON: the_marketing_seat_publishes_measures_and_reports_spend.sql (#834: marketing_post,
--     fn_marketing_post_ingest, and the fn_table_export_list this file extends) and the seat build
--     (function_owner.owner 'marketing'). Apply those first.
--
-- Prevented by: supabase/functions/_shared/marketing_style.test.ts, marketing_outreach.test.ts,
-- scripts/checks/linkedin_is_never_automated.test.mjs and the _probe file.
--
--   node scripts/apply_sql.mjs scripts/sql/the_marketing_seat_writes_articles_and_drafts_linkedin_outreach.sql --apply --ddl

begin;

-- ── 1. THE ARTICLES ──────────────────────────────────────────────────────────────────────────────
create table if not exists public.marketing_article (
  id                bigint generated always as identity primary key,
  -- 70 characters so 'article-' || slug stays inside marketing_post.ingest_key's 81
  slug              text not null unique check (slug ~ '^[a-z0-9]+(-[a-z0-9]+)+$' and length(slug) <= 70),
  kind              text not null check (kind in ('how_it_works', 'buyer_guide', 'trade_explainer')),
  title_en          text not null check (btrim(title_en) <> ''),
  excerpt_en        text not null check (btrim(excerpt_en) <> ''),
  meta_desc_en      text not null check (btrim(meta_desc_en) <> ''),
  category_en       text not null check (btrim(category_en) <> ''),
  body_html_en      text not null check (btrim(body_html_en) <> ''),
  title_ar          text not null check (title_ar ~ '[؀-ۿ]'),
  excerpt_ar        text not null check (excerpt_ar ~ '[؀-ۿ]'),
  meta_desc_ar      text not null check (meta_desc_ar ~ '[؀-ۿ]'),
  category_ar       text not null check (category_ar ~ '[؀-ۿ]'),
  body_html_ar      text not null check (body_html_ar ~ '[؀-ۿ]'),
  -- [{ref: 'src/content/marketing.json#faq.en.html', sha: '<12 hex>'}]: what the text is grounded in
  sources           jsonb not null check (jsonb_typeof(sources) = 'array' and jsonb_array_length(sources) > 0),
  checks            jsonb not null,
  ingested_by       text not null check (ingested_by in ('founder', 'claude')),
  status            text not null default 'draft' check (status in ('draft', 'approved', 'released', 'live', 'withdrawn')),
  approved_by       text check (approved_by in ('founder', 'claude')),
  approved_at       timestamptz,
  released_at       timestamptz,
  live_at           timestamptz,
  linkedin_post_key text not null,
  is_demo           boolean not null default false,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  constraint marketing_article_checks_are_clean check (checks->'lint' = '[]'::jsonb and checks->'ungrounded' = '[]'::jsonb),
  constraint marketing_article_demo_is_marked check (not is_demo or title_en like 'ZZ DEMO%'),
  constraint marketing_article_approved_says_who check (status in ('draft', 'withdrawn') or (approved_by is not null and approved_at is not null)),
  constraint marketing_article_released_says_when check (status not in ('released', 'live') or released_at is not null),
  constraint marketing_article_live_says_when check (status <> 'live' or live_at is not null)
);
comment on table public.marketing_article is
  'The marketing seat''s website articles (EN + AR), written by the founder and Claude and ingested through marketing_outreach action ingest_article, which refuses AI tells and any number the cited sources do not contain. Released by the weekly cadence only while marketing_golive is true; baked into src/content/blog.json by scripts/marketing/business_development.mjs bake.';
alter table public.marketing_article enable row level security;
drop policy if exists marketing_article_service_role_only on public.marketing_article;
create policy marketing_article_service_role_only on public.marketing_article as permissive for all to public using (false) with check (false);
revoke all on public.marketing_article from anon, authenticated;

-- ── 2. THE PEOPLE (public sources only) ──────────────────────────────────────────────────────────
create table if not exists public.marketing_prospect (
  id               bigint generated always as identity primary key,
  full_name        text not null check (btrim(full_name) <> ''),
  role_title       text not null check (btrim(role_title) <> ''),
  company          text not null check (btrim(company) <> ''),
  segment          text not null check (segment in ('developer', 'contractor_procurement', 'consultant', 'facility_manager')),
  emirate          text check (emirate in ('abu_dhabi', 'dubai', 'sharjah', 'ajman', 'umm_al_quwain', 'ras_al_khaimah', 'fujairah')),
  language         text not null default 'en' check (language in ('en', 'ar')),
  linkedin_url     text check (linkedin_url ~ '^https://([a-z]{2,3}\.)?linkedin\.com/in/[A-Za-z0-9_%-]+/?$'),
  -- the only personal hook a message may carry: one sentence about the COMPANY, from a public page, cited
  opening_line     text check (opening_line is null or length(opening_line) <= 200),
  opening_line_url text,
  source_urls      text[] not null check (cardinality(source_urls) > 0),
  researched_by    text not null check (researched_by in ('founder', 'claude', 'marketing')),
  status           text not null default 'new'
                   check (status in ('new', 'listed', 'sent', 'replied', 'converted', 'declined')),
  is_demo          boolean not null default false,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  constraint marketing_prospect_hook_is_cited check (opening_line is null or opening_line_url ~ '^https://'),
  constraint marketing_prospect_demo_is_marked check (not is_demo or full_name like 'ZZ DEMO%')
);
create unique index if not exists marketing_prospect_one_person_idx on public.marketing_prospect (lower(full_name), lower(company));
comment on table public.marketing_prospect is
  'People the founder may message on LinkedIn: developers, contractors'' procurement managers, consultants, facility managers in the UAE, researched from PUBLIC sources (company sites, public directories, press; never LinkedIn scraping, Apify paused). source_urls says where each came from. declined is final: never listed again.';
alter table public.marketing_prospect enable row level security;
drop policy if exists marketing_prospect_service_role_only on public.marketing_prospect;
create policy marketing_prospect_service_role_only on public.marketing_prospect as permissive for all to public using (false) with check (false);
revoke all on public.marketing_prospect from anon, authenticated;

-- ── 3. THE MESSAGES ──────────────────────────────────────────────────────────────────────────────
create table if not exists public.marketing_outreach_message (
  id           bigint generated always as identity primary key,
  prospect_id  bigint not null references public.marketing_prospect (id),
  kind         text not null check (kind in ('first', 'follow_up')),
  language     text not null check (language in ('en', 'ar')),
  body         text not null check (btrim(body) <> '' and length(body) <= 1900),
  note         text check (note is null or length(note) <= 300),
  lint         jsonb not null default '[]' check (lint = '[]'::jsonb),
  reply_class  text check (reply_class in ('decline', 'later', 'positive', 'question')),
  listed_on    date not null,
  status       text not null default 'draft' check (status in ('draft', 'listed', 'sent', 'replied', 'converted', 'declined')),
  mark_token   uuid not null unique default gen_random_uuid(),
  reply_text   text check (reply_text is null or length(reply_text) <= 4000),
  delivery     jsonb,
  sent_at      timestamptz,
  replied_at   timestamptz,
  converted_at timestamptz,
  is_demo      boolean not null default false,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  constraint marketing_outreach_message_first_has_a_note check (kind <> 'first' or note is not null),
  constraint marketing_outreach_message_reply_is_kept check (status not in ('replied') or reply_text is not null)
);
create unique index if not exists marketing_outreach_message_one_first_idx on public.marketing_outreach_message (prospect_id) where kind = 'first';
create index if not exists marketing_outreach_message_day_idx on public.marketing_outreach_message (listed_on);
comment on table public.marketing_outreach_message is
  'The founder''s LinkedIn drafts: first messages (2-3 a day, a message and a connection note) and follow-ups drafted from a reply he pasted. He sends each by hand; mark_token is the one-tap link (marketing_outreach) that records sent / replied / converted / declined. draft = composed while marketing_golive is false and not delivered.';
alter table public.marketing_outreach_message enable row level security;
drop policy if exists marketing_outreach_message_service_role_only on public.marketing_outreach_message;
create policy marketing_outreach_message_service_role_only on public.marketing_outreach_message as permissive for all to public using (false) with check (false);
revoke all on public.marketing_outreach_message from anon, authenticated;

-- ── 4. THE KNOBS ─────────────────────────────────────────────────────────────────────────────────
insert into public.decision_policy (key, value, description) values
  ('marketing_outreach_per_day', '3'::jsonb,
   'LinkedIn messages the marketing seat lists for the founder each Dubai morning (founder, instruction 722: two or three; the routine clamps it to 0-3).'),
  ('marketing_outreach_list_hour', '7'::jsonb,
   'Dubai hour from which the morning LinkedIn list is composed.'),
  ('marketing_articles_per_week', '2'::jsonb,
   'Approved articles the seat releases to the website per Dubai week (at most one a day).')
on conflict (key) do nothing;

insert into public.founder_mail_policy (kind, allowed_to_email, reason, owner_role) values
  ('marketing_outreach_list', true,
   'the morning LinkedIn list is his to send by hand from his own account (LinkedIn allows no automated messaging); email only, and only while marketing_golive is true',
   'marketing')
on conflict (kind) do update set allowed_to_email = excluded.allowed_to_email, reason = excluded.reason, owner_role = excluded.owner_role, updated_at = now();

-- ── 5. THE ONE SWITCH READ ───────────────────────────────────────────────────────────────────────
create or replace function public.fn_marketing_publishing_live()
returns boolean language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  select coalesce((select lower(btrim(value)) = 'true' from public.app_secrets where key = 'marketing_golive'), false)
$fn$;
revoke execute on function public.fn_marketing_publishing_live() from public, anon, authenticated;

create or replace function public.fn_marketing_policy_int(p_key text, p_default int)
returns int language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  select coalesce((select (value #>> '{}')::int from public.decision_policy where key = p_key), p_default)
$fn$;
revoke execute on function public.fn_marketing_policy_int(text, integer) from public, anon, authenticated;

-- ── 6. ARTICLES: INGEST, APPROVE, RELEASE, LIVE ──────────────────────────────────────────────────
-- p: {slug, kind, ingested_by, is_demo, sources:[{ref, sha}], checks:{lint:[], ungrounded:[]},
--     en:{title, excerpt, meta_desc, category, body_html}, ar:{...}, post:{text_en, text_ar}}
-- Called only by supabase/functions/marketing_outreach (action ingest_article), which ran the checks.
create or replace function public.fn_marketing_article_ingest(p jsonb)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  v_slug text := lower(btrim(coalesce(p->>'slug', '')));
  v_key text; v_cur public.marketing_article; v_id bigint; v_post jsonb; v_f text;
begin
  foreach v_f in array array['title', 'excerpt', 'meta_desc', 'category', 'body_html'] loop
    if public.fn_text_lost_its_script(p->'ar'->>v_f) then
      return jsonb_build_object('ok', false, 'error', 'text_lost_its_script', 'field', 'ar.' || v_f);
    end if;
  end loop;
  if coalesce(p->'checks'->'lint', '[]'::jsonb) <> '[]'::jsonb or coalesce(p->'checks'->'ungrounded', '[]'::jsonb) <> '[]'::jsonb then
    return jsonb_build_object('ok', false, 'error', 'checks_not_clean', 'checks', p->'checks');
  end if;
  v_key := 'article-' || v_slug;
  select * into v_cur from public.marketing_article where slug = v_slug for update;
  if found and v_cur.status <> 'draft' then
    return jsonb_build_object('ok', true, 'unchanged', true, 'status', v_cur.status,
      'message', 'Already ' || v_cur.status || '; an approved article is not edited in place. Withdraw it or ingest a new slug.');
  end if;
  insert into public.marketing_article (slug, kind, title_en, excerpt_en, meta_desc_en, category_en, body_html_en,
      title_ar, excerpt_ar, meta_desc_ar, category_ar, body_html_ar, sources, checks, ingested_by, linkedin_post_key, is_demo)
  values (v_slug, p->>'kind', p->'en'->>'title', p->'en'->>'excerpt', p->'en'->>'meta_desc', p->'en'->>'category', p->'en'->>'body_html',
          p->'ar'->>'title', p->'ar'->>'excerpt', p->'ar'->>'meta_desc', p->'ar'->>'category', p->'ar'->>'body_html',
          p->'sources', p->'checks', coalesce(p->>'ingested_by', 'claude'), v_key, coalesce((p->>'is_demo')::boolean, false))
  on conflict (slug) do update
     set kind = excluded.kind, title_en = excluded.title_en, excerpt_en = excluded.excerpt_en, meta_desc_en = excluded.meta_desc_en,
         category_en = excluded.category_en, body_html_en = excluded.body_html_en, title_ar = excluded.title_ar,
         excerpt_ar = excluded.excerpt_ar, meta_desc_ar = excluded.meta_desc_ar, category_ar = excluded.category_ar,
         body_html_ar = excluded.body_html_ar, sources = excluded.sources, checks = excluded.checks,
         ingested_by = excluded.ingested_by, is_demo = excluded.is_demo, updated_at = now()
  returning id into v_id;
  -- Its LinkedIn post, a DRAFT in #834's store: scheduled only by fn_marketing_article_mark_live.
  v_post := public.fn_marketing_post_ingest(jsonb_build_object('ingest_key', v_key, 'ingested_by', 'marketing',
              'title', p->'en'->>'title', 'text_en', p->'post'->>'text_en', 'text_ar', p->'post'->>'text_ar',
              'channels', jsonb_build_array('linkedin'), 'is_demo', coalesce((p->>'is_demo')::boolean, false)));
  if not coalesce((v_post->>'ok')::boolean, false) then
    raise exception 'the article''s LinkedIn post was refused: %', v_post;
  end if;
  return jsonb_build_object('ok', true, 'id', v_id, 'slug', v_slug, 'status', 'draft', 'linkedin_post', v_post);
end $fn$;
revoke execute on function public.fn_marketing_article_ingest(jsonb) from public, anon, authenticated;

create or replace function public.fn_marketing_article_approve(p_slug text, p_by text)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_id bigint;
begin
  if p_by not in ('founder', 'claude') then return jsonb_build_object('ok', false, 'error', 'approver_must_be_founder_or_claude'); end if;
  update public.marketing_article set status = 'approved', approved_by = p_by, approved_at = now(), updated_at = now()
   where slug = p_slug and status = 'draft' returning id into v_id;
  return jsonb_build_object('ok', v_id is not null, 'slug', p_slug,
    'error', case when v_id is null then 'not_a_draft' end);
end $fn$;
revoke execute on function public.fn_marketing_article_approve(text, text) from public, anon, authenticated;

-- The cadence: at most marketing_articles_per_week per Dubai week and one a Dubai day, oldest approved first.
create or replace function public.fn_marketing_article_release_due()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  v_now timestamp := now() at time zone 'Asia/Dubai';
  v_week int; v_today int; v_next public.marketing_article;
begin
  select count(*) filter (where released_at at time zone 'Asia/Dubai' >= date_trunc('week', v_now)),
         count(*) filter (where (released_at at time zone 'Asia/Dubai')::date = v_now::date)
    into v_week, v_today from public.marketing_article where released_at is not null and not is_demo;
  if v_week >= greatest(0, public.fn_marketing_policy_int('marketing_articles_per_week', 2)) or v_today > 0 then
    return jsonb_build_object('released', null, 'this_week', v_week, 'reason', 'cadence');
  end if;
  select * into v_next from public.marketing_article where status = 'approved' and not is_demo order by approved_at, id limit 1 for update skip locked;
  if not found then return jsonb_build_object('released', null, 'this_week', v_week, 'reason', 'nothing_approved'); end if;
  if not public.fn_marketing_publishing_live() then
    return jsonb_build_object('released', null, 'held', true, 'would_release', v_next.slug, 'reason', 'marketing_golive is not true');
  end if;
  update public.marketing_article set status = 'released', released_at = now(), updated_at = now() where id = v_next.id;
  return jsonb_build_object('released', v_next.slug, 'this_week', v_week + 1);
end $fn$;
revoke execute on function public.fn_marketing_article_release_due() from public, anon, authenticated;

-- Called when the article's page answered 200: the article is live and its LinkedIn post is scheduled
-- (#834's scheduler publishes it, as a dry run while the switch is off).
create or replace function public.fn_marketing_article_mark_live(p_slug text)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_a public.marketing_article; v_posts int;
begin
  update public.marketing_article set status = 'live', live_at = now(), updated_at = now()
   where slug = p_slug and status = 'released' returning * into v_a;
  if v_a.id is null then return jsonb_build_object('ok', false, 'error', 'not_released'); end if;
  update public.marketing_post set status = 'scheduled', scheduled_at = now() + interval '5 minutes', updated_at = now()
   where ingest_key = v_a.linkedin_post_key and status = 'draft';
  get diagnostics v_posts = row_count;
  return jsonb_build_object('ok', true, 'slug', p_slug, 'linkedin_post_scheduled', v_posts = 1);
end $fn$;
revoke execute on function public.fn_marketing_article_mark_live(text) from public, anon, authenticated;

-- ── 7. PROSPECTS ─────────────────────────────────────────────────────────────────────────────────
create or replace function public.fn_marketing_prospect_upsert(p jsonb)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  v_urls text[] := coalesce((select array_agg(btrim(x)) from jsonb_array_elements_text(coalesce(p->'source_urls', '[]'::jsonb)) x), '{}');
  v_id bigint; v_status text;
begin
  if cardinality(v_urls) = 0 or exists (select 1 from unnest(v_urls) u where u !~ '^https?://[^\s/]+\.[^\s]+$') then
    return jsonb_build_object('ok', false, 'error', 'source_urls_required', 'message', 'Every person needs the public page(s) they were found on.');
  end if;
  if exists (select 1 from unnest(v_urls) u where u ~* '^https?://([a-z]{2,3}\.)?linkedin\.com/') and cardinality(v_urls) = 1 then
    return jsonb_build_object('ok', false, 'error', 'linkedin_is_not_a_source',
      'message', 'A person must be found on a public page other than LinkedIn (company site, directory, press); the profile URL goes in linkedin_url.');
  end if;
  select id, status into v_id, v_status from public.marketing_prospect
   where lower(full_name) = lower(btrim(p->>'full_name')) and lower(company) = lower(btrim(p->>'company')) for update;
  if v_id is not null and v_status <> 'new' then
    return jsonb_build_object('ok', true, 'id', v_id, 'unchanged', true, 'status', v_status);
  end if;
  if v_id is null then
    insert into public.marketing_prospect (full_name, role_title, company, segment, emirate, language, linkedin_url,
        opening_line, opening_line_url, source_urls, researched_by, is_demo)
    values (btrim(p->>'full_name'), btrim(p->>'role_title'), btrim(p->>'company'), p->>'segment', nullif(p->>'emirate', ''),
            coalesce(nullif(p->>'language', ''), 'en'), nullif(btrim(p->>'linkedin_url'), ''), nullif(btrim(p->>'opening_line'), ''),
            nullif(btrim(p->>'opening_line_url'), ''), v_urls, coalesce(p->>'researched_by', 'claude'), coalesce((p->>'is_demo')::boolean, false))
    returning id into v_id;
  else
    update public.marketing_prospect
       set role_title = btrim(p->>'role_title'), segment = p->>'segment', emirate = nullif(p->>'emirate', ''),
           language = coalesce(nullif(p->>'language', ''), 'en'), linkedin_url = nullif(btrim(p->>'linkedin_url'), ''),
           opening_line = nullif(btrim(p->>'opening_line'), ''), opening_line_url = nullif(btrim(p->>'opening_line_url'), ''),
           source_urls = v_urls, updated_at = now()
     where id = v_id;
  end if;
  return jsonb_build_object('ok', true, 'id', v_id);
end $fn$;
revoke execute on function public.fn_marketing_prospect_upsert(jsonb) from public, anon, authenticated;

-- ── 8. THE MORNING LIST ──────────────────────────────────────────────────────────────────────────
-- Due once per Dubai day from marketing_outreach_list_hour. Returns the people to draft for, oldest first:
-- still 'new' (a declined, sent or replied person is never listed again). While the switch is off the same
-- people are re-drafted each day and none is used up.
create or replace function public.fn_marketing_outreach_due(p_include_demo boolean default false)
returns jsonb language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  with d as (select (now() at time zone 'Asia/Dubai')::date as day, extract(hour from now() at time zone 'Asia/Dubai')::int as hr),
       n as (select least(3, greatest(0, public.fn_marketing_policy_int('marketing_outreach_per_day', 3))) as want)
  select jsonb_build_object(
    'day', d.day, 'want', n.want, 'live', public.fn_marketing_publishing_live(),
    'due', d.hr >= public.fn_marketing_policy_int('marketing_outreach_list_hour', 7)
           and not exists (select 1 from public.marketing_outreach_message m
                            where m.kind = 'first' and m.listed_on = d.day and (p_include_demo or not m.is_demo)),
    'prospects', coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at, x.id) from (
        select p.id, p.full_name, p.role_title, p.company, p.segment, p.language, p.linkedin_url, p.opening_line, p.created_at
          from public.marketing_prospect p
         where p.status = 'new' and (p_include_demo or not p.is_demo)
         order by p.created_at, p.id limit n.want) x), '[]'::jsonb))
  from d, n
$fn$;
revoke execute on function public.fn_marketing_outreach_due(boolean) from public, anon, authenticated;

-- p_items: [{prospect_id, language, body, note, lint}] as composed by marketing_outreach.ts. Live: listed, and
-- the person is used up. Held: a draft (re-composed in place next day) and the person stays new.
create or replace function public.fn_marketing_outreach_record(p_day date, p_items jsonb)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_live boolean := public.fn_marketing_publishing_live(); v_out jsonb;
begin
  with ins as (
    insert into public.marketing_outreach_message (prospect_id, kind, language, body, note, lint, listed_on, status, is_demo)
    select (i->>'prospect_id')::bigint, 'first', i->>'language', i->>'body', i->>'note', coalesce(i->'lint', '[]'::jsonb), p_day,
           case when v_live and not p.is_demo then 'listed' else 'draft' end, p.is_demo
      from jsonb_array_elements(p_items) i
      join public.marketing_prospect p on p.id = (i->>'prospect_id')::bigint and p.status = 'new'
    on conflict (prospect_id) where kind = 'first' do update
       set language = excluded.language, body = excluded.body, note = excluded.note, lint = excluded.lint,
           listed_on = excluded.listed_on, status = excluded.status, updated_at = now()
     where marketing_outreach_message.status = 'draft'
    returning id, prospect_id, mark_token, status
  ), used as (
    update public.marketing_prospect p set status = 'listed', updated_at = now()
      from ins where ins.prospect_id = p.id and ins.status = 'listed'
    returning p.id
  )
  select jsonb_build_object('live', v_live, 'items',
           coalesce(jsonb_agg(jsonb_build_object('id', ins.id, 'prospect_id', ins.prospect_id, 'token', ins.mark_token, 'status', ins.status)), '[]'::jsonb),
           'used', (select count(*) from used))
    into v_out from ins;
  return v_out;
end $fn$;
revoke execute on function public.fn_marketing_outreach_record(date, jsonb) from public, anon, authenticated;

-- The morning email. Sent through fn_notify_founder (kind marketing_outreach_list, normal level: email only)
-- ONLY while the switch is on and the list holds listed, non-demo messages; otherwise recorded as a dry run.
create or replace function public.fn_marketing_outreach_deliver(p_day date, p_ids bigint[], p_subject text, p_body text)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_listed int; v_res jsonb; v_delivery jsonb;
begin
  select count(*) into v_listed from public.marketing_outreach_message where id = any (p_ids) and status = 'listed' and not is_demo;
  if public.fn_marketing_publishing_live() and v_listed > 0 then
    v_res := public.fn_notify_founder(p_subject, p_body, 'normal', 'marketing_outreach_list', 'marketing_outreach_list:' || p_day);
    v_delivery := jsonb_build_object('mode', 'emailed', 'at', now(), 'notify', v_res);
  else
    v_delivery := jsonb_build_object('mode', 'dry_run', 'at', now(),
      'why', case when v_listed = 0 then 'nothing listed (held or demo)' else 'marketing_golive is not true' end,
      'subject', p_subject, 'body', left(p_body, 6000));
  end if;
  update public.marketing_outreach_message set delivery = v_delivery, updated_at = now() where id = any (p_ids);
  return v_delivery - 'body';
end $fn$;
revoke execute on function public.fn_marketing_outreach_deliver(date, bigint[], text, text) from public, anon, authenticated;

-- ── 9. THE ONE-TAP PAGE ──────────────────────────────────────────────────────────────────────────
create or replace function public.fn_marketing_outreach_page(p_token uuid)
returns jsonb language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  select jsonb_build_object('id', m.id, 'kind', m.kind, 'status', m.status, 'language', m.language, 'body', m.body, 'note', m.note,
           'reply_text', m.reply_text,
           'prospect', jsonb_build_object('full_name', p.full_name, 'role_title', p.role_title, 'company', p.company,
                                          'linkedin_url', p.linkedin_url, 'status', p.status),
           'follow_ups', coalesce((select jsonb_agg(jsonb_build_object('body', f.body, 'token', f.mark_token, 'status', f.status) order by f.id)
                                     from public.marketing_outreach_message f where f.prospect_id = m.prospect_id and f.kind = 'follow_up' and f.id > m.id), '[]'::jsonb))
    from public.marketing_outreach_message m join public.marketing_prospect p on p.id = m.prospect_id
   where m.mark_token = p_token
$fn$;
revoke execute on function public.fn_marketing_outreach_page(uuid) from public, anon, authenticated;

-- p_status: sent | replied | converted | declined. A reply stores what he pasted and the follow-up the seat
-- drafted (p_follow_up, composed and linted by marketing_outreach.ts); a declining reply closes the person.
create or replace function public.fn_marketing_outreach_mark(p_token uuid, p_status text, p_reply text default null,
                                                             p_reply_class text default null, p_follow_up text default null)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_m public.marketing_outreach_message; v_follow uuid; v_person text;
begin
  select * into v_m from public.marketing_outreach_message where mark_token = p_token for update;
  if not found then return jsonb_build_object('ok', false, 'error', 'unknown_link'); end if;
  if p_status not in ('sent', 'replied', 'converted', 'declined') then return jsonb_build_object('ok', false, 'error', 'unknown_status'); end if;
  if p_status = 'replied' and btrim(coalesce(p_reply, '')) = '' then return jsonb_build_object('ok', false, 'error', 'paste_the_reply'); end if;

  update public.marketing_outreach_message
     set status = p_status,
         sent_at = coalesce(sent_at, case when p_status in ('sent', 'replied', 'converted') then now() end),
         replied_at = case when p_status = 'replied' then now() else replied_at end,
         converted_at = case when p_status = 'converted' then now() else converted_at end,
         reply_text = case when p_status = 'replied' then left(p_reply, 4000) else reply_text end,
         reply_class = case when p_status = 'replied' then p_reply_class else reply_class end,
         updated_at = now()
   where id = v_m.id;

  v_person := case when p_status = 'declined' or p_reply_class = 'decline' then 'declined' else p_status end;
  -- a person only moves forward: a late "sent" tap never undoes a reply or a conversion
  update public.marketing_prospect set status = v_person, updated_at = now()
   where id = v_m.prospect_id
     and array_position(array['new', 'listed', 'sent', 'replied', 'converted'], status) <= coalesce(array_position(array['new', 'listed', 'sent', 'replied', 'converted'], v_person), 99)
     and status <> 'declined';

  if p_status = 'replied' and btrim(coalesce(p_follow_up, '')) <> '' then
    insert into public.marketing_outreach_message (prospect_id, kind, language, body, lint, listed_on, status, is_demo)
    values (v_m.prospect_id, 'follow_up', v_m.language, p_follow_up, '[]'::jsonb, (now() at time zone 'Asia/Dubai')::date, 'listed', v_m.is_demo)
    returning mark_token into v_follow;
  end if;
  return jsonb_build_object('ok', true, 'status', p_status, 'person', v_person, 'follow_up_token', v_follow);
end $fn$;
revoke execute on function public.fn_marketing_outreach_mark(uuid, text, text, text, text) from public, anon, authenticated;

-- ── 10. THE FIGURES THE MARKETING REPORT READS ───────────────────────────────────────────────────
create or replace view public.marketing_bd_figures with (security_invoker = true) as
  select
    (select count(*) from public.marketing_prospect where status = 'new' and not is_demo)                          as prospects_waiting,
    (select count(*) from public.marketing_outreach_message where status = 'draft' and not is_demo)                as drafts_held,
    (select count(*) from public.marketing_outreach_message where kind = 'first' and status <> 'draft' and not is_demo
        and listed_on >= (now() at time zone 'Asia/Dubai')::date - 6)                                             as listed_7d,
    (select count(*) from public.marketing_outreach_message where sent_at >= now() - interval '7 days' and not is_demo) as sent_7d,
    (select count(*) from public.marketing_outreach_message where replied_at >= now() - interval '7 days' and not is_demo) as replied_7d,
    (select count(*) from public.marketing_outreach_message where converted_at >= now() - interval '7 days' and not is_demo) as converted_7d,
    (select count(*) from public.marketing_prospect where status in ('sent', 'replied', 'converted', 'declined') and not is_demo) as people_contacted,
    (select count(*) from public.marketing_prospect where status in ('replied', 'converted') and not is_demo)       as people_replied,
    (select count(*) from public.marketing_prospect where status = 'converted' and not is_demo)                     as people_converted,
    (select count(*) from public.marketing_article where status = 'draft' and not is_demo)                          as articles_draft,
    (select count(*) from public.marketing_article where status = 'approved' and not is_demo)                       as articles_approved,
    (select count(*) from public.marketing_article where status in ('released', 'live') and not is_demo)            as articles_released,
    (select count(*) from public.marketing_article where live_at >= now() - interval '30 days' and not is_demo)     as articles_live_30d;
comment on view public.marketing_bd_figures is
  'Business development counts for the marketing report (fn_marketing_report_figures should carry them under business_development). ZZ DEMO rows excluded.';
revoke all on public.marketing_bd_figures from anon, authenticated;

-- ── 11. THE RUNTIME: CREDENTIAL, OWNER, CLOCK ────────────────────────────────────────────────────
do $mint$
declare v_secret text;
begin
  if exists (select 1 from public.internal_credential where context = 'fn.marketing_outreach') then return; end if;
  v_secret := encode(extensions.gen_random_bytes(32), 'hex');
  insert into public.internal_credential (context, label, secret_hash, scope, is_legacy, active)
  values ('fn.marketing_outreach',
          'The marketing seat''s business development: article ingest and cadence, the morning LinkedIn list (behind marketing_golive), prospect ingest',
          public.fn_internal_credential_hash(v_secret), array['marketing_outreach'], false, true);
  insert into public.app_secrets (key, value) values ('cred_fn_marketing_outreach', v_secret)
  on conflict (key) do update set value = excluded.value;
end
$mint$;

insert into public.function_owner (function_slug, owner, note)
values ('marketing_outreach', 'marketing',
        'The marketing seat''s business development (founder, instruction 722): website articles on a weekly cadence and the founder''s morning LinkedIn list, which he sends by hand. Nothing is sent or released while marketing_golive is not true.')
on conflict (function_slug) do update set owner = excluded.owner, note = excluded.note;

insert into public.resilience_step (step, every, budget_ms, place, rank, note) values
  ('marketingOutreach', interval '30 min', 3000, 'plan', 0,
   'marketing: once a Dubai morning drafts the LinkedIn list (emailed to the founder only while marketing_golive is true); releases approved articles on the weekly cadence and marks a released article live when its page answers')
on conflict (step) do update
   set every = excluded.every, budget_ms = excluded.budget_ms, place = excluded.place, rank = excluded.rank, note = excluded.note;

-- ── 12. THE DAILY TABLE EXPORT: + the three business-development tables ─────────────────────────
-- Copied from #834's definition (the_marketing_seat_publishes_measures_and_reports_spend.sql) with
-- marketing_article, marketing_prospect and marketing_outreach_message added under subject 'marketing'.
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
    ('table_export_change','backup')
  ) v(t, s)
$fn$;
revoke execute on function public.fn_table_export_list() from public, anon, authenticated;

-- THE REPORT CARRIES BUSINESS DEVELOPMENT AND THE SOCIAL INBOX (22 Sep 2026). fn_marketing_report_figures is
-- redefined from its current definition (the_marketing_seat_publishes_measures_and_reports_spend.sql, PR #834)
-- with two additions under measured: business_development (marketing_bd_figures, above) and social_inbox
-- (v_marketing_social_volume, PR #835); the stale "no social inbox record is built yet" line is removed.
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
      'connections_measured_at', v_conn->'oldest_measurement',
      'business_development', (select to_jsonb(f) from public.marketing_bd_figures f),
      'social_inbox', coalesce((select jsonb_agg(to_jsonb(v)) from public.v_marketing_social_volume v), '[]'::jsonb)),
    'not_measured', to_jsonb(array_remove(array[
      case when v_ins_days = 0 then 'followers, reach and engagement per channel: no insight was pulled for the window yet' end,
      case when coalesce((v_conn->>'never_measured')::boolean, true) then 'channel access: the access check has not run yet' end,
      'search rankings and organic traffic: no SEO reader is built yet'], null)),
    'basis', 'Posts: marketing_post (published_at in the window; scheduled and held from its status and dry_run). Spend: ad_spend_reported by spend_date (Asia/Dubai), in AED at gl_settings usd_to_aed. Insights: marketing_insight_day, page and account metrics summed over the window. Connections: marketing_connection_check as last measured. Handed to the founder: notifications of kind social_human_request. Customer requests: fn_ceo_plan_measure(inquiries_posted), demo excluded. Business development: marketing_bd_figures (7-day counts, ZZ DEMO excluded). Social inbox: v_marketing_social_volume per platform. Window: the 24 hours before the report.');
end $fn$;
revoke execute on function public.fn_marketing_report_figures(timestamptz, timestamptz) from public, anon, authenticated;

commit;
