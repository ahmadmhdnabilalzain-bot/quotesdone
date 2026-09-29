-- A BLOG ARTICLE IS A MARKET TOPIC THE CEO REVIEWS UNTIL IT IS USEFUL; THE FOUNDER HEARS ONLY THAT IT WENT LIVE.
-- Seat: marketing (the CEO seat reviews). 29 Sep 2026. Founder rulings 1058 and 1059 (they supersede the blog part of
-- 726). Follows the_marketing_seat_puts_its_plan_geo_articles_launch_and_competitor_work_on_a_clock.sql (#1039), whose
-- article routines this file redefines, and the_marketing_seat_writes_articles_and_drafts_linkedin_outreach.sql.
--
-- WHAT WAS MEASURED (29 Sep 2026, production):
--   * marketing_article held 4 drafts (ids 3-6), every one about QuotesDone itself (kinds how_it_works, buyer_guide).
--     Article 3 was mailed to the founder for approval (notification 76044, reply-to approve+1071de91...).
--   * fn_marketing_article_approve accepted only the founder; fn_marketing_article_release_due released at most
--     marketing_articles_per_week (2) a Dubai week.
--   * Nothing in the article flow writes to a customer, supplier or lead: fn_marketing_article_release_due and
--     fn_marketing_article_mark_live only update marketing_article and schedule the company-page LinkedIn post; there is
--     no trigger on marketing_article or blog_posts; the only notifications insert is fn_marketing_mail_founder.
--   * app_secrets holds no search, trend or keyword API key (only google_oauth_* for inbox placement). The seat's
--     keyless trend feeds (marketing_trend_source: 4 Google News queries) held 80 items, none judged relevant yet
--     (the model hold).
--
-- THE RULINGS
--   1058: the founder never approves a blog. The CEO seat reviews each article and decides. The founder gets an FYI
--         when one goes live: no token, nothing to answer. Publishing emails no customer, supplier or lead. Blogs are
--         market topics (UAE construction, fit-out, MEP and the procurement trades: what people search for, seasonal
--         and regulatory news), never about QuotesDone, never naming a supplier, citing their market sources. At most
--         ONE a week, enforced at release. The monthly social calendar approval is unchanged (not touched here).
--   1059: a rejection never ends the cycle. The CEO's review is structured: every decision gives, per rubric
--         criterion, a verdict and its reason, and the DATABASE refuses a decision without them. The marketing seat
--         answers every failed reason in a new version and resubmits, until approved; every round is kept. After 4
--         revise rounds on a topic the CEO must approve or replace the topic; marketing then picks a new topic carrying
--         the lessons. Nothing goes to the founder but the live FYI.
--
-- THE PIPE
--   1. TOPICS (code). fn_marketing_blog_topic_candidates(): trends the seat judged relevant in 21 days (Google Trends
--      UAE daily searches, the regulation feed, the news feeds; a search interest scores highest) and the trades buyers
--      asked for in 90 days (inquiries.trades, never a demo customer), each grounded in its verified knowledge
--      (sales_knowledge, trade:<code>). fn_marketing_blog_topic_pick() opens ONE topic at a time, the best candidate
--      not used in 90 days, with the runners-up it beat and the lessons of every replaced topic.
--   2. DRAFT (model, marketing_article_draft), supabase/functions/marketing/duties.ts duty 'blog_article', step article_draft: the topic, its
--      evidence and sources, the lessons. The article gate is code (checkArticle: style lint both languages, same
--      structure EN/AR, no number that is not in the cited market sources) and fn_marketing_blog_submit (no supplier
--      named, not about QuotesDone). Round 1 is stored.
--   3. CEO REVIEW (model, ceo_article_review, routed to a family other than the draft's), step article_review:
--      approve / revise / replace_topic with a verdict and a reason for each of the six criteria.
--      marketing_article_round refuses a decision without them (CHECK fn_marketing_review_reasons_ok), and its trigger
--      refuses a fifth revise on a topic and any rewrite of a decided round.
--   4. REVISION (model, marketing_article_revise), step article_revise: a new version that says, for EVERY
--      failed criterion, what changed; the trigger refuses a round that leaves one unanswered. Back to 3.
--   5. RELEASE: approved by the CEO, a market topic, a UAE working day, at most ONE a Dubai week and one a day.
--      LIVE: the founder's FYI (founder_mail_policy 'marketing_article_live', no reply-to); the topic is published and
--      the next one is picked.
--   A refused or failed model step is recorded before it is raised (marketing_model_run), is tried at most once a
--   Dubai day, and each retry carries the refusal; after 3 refusals of a draft or a revision the topic is replaced
--   with that lesson (fn_marketing_blog_topic_replace). Under the model hold nothing is called and the topic waits.
--
-- CLEAN-UP: articles 3-6 are withdrawn with their reason (rows kept); every article approval token is cleared; a reply
-- to any article approval email ever sent is answered "article approval is retired" and changes nothing;
-- founder_mail_policy 'marketing_article_approval' is closed, so no path can mail him an article to approve.
--
-- Prevented by: scripts/checks/marketing_duties_are_on_a_clock.test.mjs (the CEO decides, one a week, the FYI is the
-- only mail, the old token does nothing), supabase/functions/marketing/duties.test.ts (a refused step: one failed row,
-- zero calls the next beat) and supabase/functions/_shared/marketing_articles.test.ts (the draft and review gates).

-- ── 0. rows ──────────────────────────────────────────────────────────────────────────────────────────────────────
alter table public.marketing_trend_source add column if not exists kind text not null default 'news';
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'marketing_trend_source_kind_check') then
    alter table public.marketing_trend_source add constraint marketing_trend_source_kind_check check (kind in ('news', 'search', 'regulation'));
  end if;
end $$;
update public.marketing_trend_source set kind = 'regulation' where name = 'UAE building regulation' and kind <> 'regulation';
-- What people in the UAE search for, keyless: Google Trends' daily trending searches for the UAE. Each search is
-- judged for relevance by the seat like any news item (trend_watch); parseRss gives each search its own explore URL.
insert into public.marketing_trend_source (name, feed_url, kind)
select 'Google Trends UAE daily searches', 'https://trends.google.com/trending/rss?geo=AE', 'search'
 where not exists (select 1 from public.marketing_trend_source where feed_url = 'https://trends.google.com/trending/rss?geo=AE');

create table if not exists public.marketing_blog_topic (
  id              bigint generated always as identity primary key,
  topic_key       text not null,                 -- 'trend:<marketing_trend.id>' or 'demand:<trade code>'
  kind            text not null check (kind in ('search', 'regulation', 'news', 'demand')),
  title           text not null check (btrim(title) <> ''),
  trade           text,
  score           numeric not null,
  evidence        jsonb not null check (jsonb_typeof(evidence) = 'array' and jsonb_array_length(evidence) > 0),
  sources         jsonb not null check (jsonb_typeof(sources) = 'array' and jsonb_array_length(sources) > 0),
  considered      jsonb not null default '[]'::jsonb,   -- the candidates it beat, with their scores
  lessons         jsonb not null default '[]'::jsonb,   -- carried in from replaced topics
  learned         jsonb not null default '[]'::jsonb,   -- what this topic's rounds taught, written when it is replaced
  status          text not null default 'picked' check (status in ('picked', 'replaced', 'published')),
  replaced_reason text,
  picked_at       timestamptz not null default now(),
  closed_at       timestamptz,
  check ((status = 'replaced') = (replaced_reason is not null)),
  check ((status = 'picked') = (closed_at is null))
);
create unique index if not exists marketing_blog_topic_one_open on public.marketing_blog_topic ((true)) where status = 'picked';
create index if not exists marketing_blog_topic_key on public.marketing_blog_topic (topic_key, picked_at desc);

alter table public.marketing_article add column if not exists topic_id bigint references public.marketing_blog_topic(id);
alter table public.marketing_article add column if not exists withdrawn_reason text;
alter table public.marketing_article add column if not exists withdrawn_at timestamptz;
alter table public.marketing_article drop constraint if exists marketing_article_kind_check;
alter table public.marketing_article add constraint marketing_article_kind_check
  check (kind in ('how_it_works', 'buyer_guide', 'trade_explainer', 'market_topic'));
alter table public.marketing_article drop constraint if exists marketing_article_approved_by_check;
alter table public.marketing_article add constraint marketing_article_approved_by_check check (approved_by in ('founder', 'claude', 'ceo'));

-- The article's content, every field in both languages: what a round stores and reviews.
create or replace function public.fn_marketing_article_fingerprint(p_id bigint)
returns text language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  select md5(concat_ws(E'\x1f', title_en, excerpt_en, meta_desc_en, category_en, body_html_en,
                                 title_ar, excerpt_ar, meta_desc_ar, category_ar, body_html_ar))
    from public.marketing_article where id = p_id
$fn$;
revoke execute on function public.fn_marketing_article_fingerprint(bigint) from public, anon, authenticated;

-- THE RUBRIC (1059). A decision is valid only with all six criteria, each a verdict and a reason of 15+ characters;
-- approve only when all six pass ("good for the company -> approve"); revise and replace_topic name at least one fail.
create or replace function public.fn_marketing_review_reasons_ok(p_decision text, p_reasons jsonb)
returns boolean language sql immutable set search_path to 'public', 'pg_temp' as $fn$
  select jsonb_typeof(p_reasons) = 'object'
     and (select count(*) from jsonb_object_keys(p_reasons)) = 6
     and coalesce((select bool_and(coalesce(r.value->>'verdict', '') in ('pass', 'fail')
                                   and length(btrim(coalesce(r.value->>'reason', ''))) >= 15)
                     from jsonb_each(p_reasons) r
                    where r.key in ('useful', 'market_topic_not_quotesdone', 'accurate_grounded', 'no_supplier_named',
                                    'language_quality', 'seo_geo')
                   having count(*) = 6), false)
     and case p_decision
           when 'approve' then not exists (select 1 from jsonb_each(p_reasons) r where r.value->>'verdict' <> 'pass')
           when 'revise' then exists (select 1 from jsonb_each(p_reasons) r where r.value->>'verdict' = 'fail')
           when 'replace_topic' then exists (select 1 from jsonb_each(p_reasons) r where r.value->>'verdict' = 'fail')
           else false end
$fn$;
revoke execute on function public.fn_marketing_review_reasons_ok(text, jsonb) from public, anon, authenticated;

-- Every round is kept: the version the CEO reviewed, what marketing changed for each earlier reason, the decision
-- and its reasons. A decided round is never rewritten or deleted.
create table if not exists public.marketing_article_round (
  id                bigint generated always as identity primary key,
  article_id        bigint not null references public.marketing_article(id),
  topic_id          bigint not null references public.marketing_blog_topic(id),
  round             int not null check (round >= 1),
  version           jsonb not null check (jsonb_typeof(version->'en') = 'object' and jsonb_typeof(version->'ar') = 'object'),
  fingerprint       text not null,
  drafted_by_model  text,
  changes           jsonb check (changes is null or jsonb_typeof(changes) = 'array'),
  decision          text check (decision in ('approve', 'revise', 'replace_topic')),
  reasons           jsonb,
  reviewed_by_model text,
  reviewed_at       timestamptz,
  created_at        timestamptz not null default now(),
  unique (article_id, round),
  check ((round = 1) = (changes is null)),
  check ((decision is null) = (reviewed_at is null)),
  constraint marketing_article_round_decision_has_its_reasons
    check (decision is null or public.fn_marketing_review_reasons_ok(decision, reasons))
);
create unique index if not exists marketing_article_round_one_waiting on public.marketing_article_round (article_id) where decision is null;
alter table public.marketing_blog_topic enable row level security;
alter table public.marketing_article_round enable row level security;
drop policy if exists marketing_blog_topic_service_role_only on public.marketing_blog_topic;
create policy marketing_blog_topic_service_role_only on public.marketing_blog_topic as permissive for all to public using (false) with check (false);
drop policy if exists marketing_article_round_service_role_only on public.marketing_article_round;
create policy marketing_article_round_service_role_only on public.marketing_article_round as permissive for all to public using (false) with check (false);
revoke all on public.marketing_blog_topic from anon, authenticated;
revoke all on public.marketing_article_round from anon, authenticated;

create or replace function public.fn_marketing_article_round_guard()
returns trigger language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_prev public.marketing_article_round; v_missing text;
begin
  if tg_op = 'DELETE' then
    raise exception 'round % of article % is history: a review round is never deleted', old.round, old.article_id;
  end if;
  if tg_op = 'UPDATE' then
    if old.decision is not null then
      raise exception 'round % of article % is decided (%): its history is never overwritten', old.round, old.article_id, old.decision;
    end if;
    if (new.article_id, new.topic_id, new.round, new.version, new.fingerprint, new.drafted_by_model, new.changes, new.created_at)
       is distinct from (old.article_id, old.topic_id, old.round, old.version, old.fingerprint, old.drafted_by_model, old.changes, old.created_at) then
      raise exception 'only the CEO''s decision is written to a submitted round';
    end if;
    if new.decision = 'revise' and (select count(*) from public.marketing_article_round r
                                     where r.topic_id = new.topic_id and r.decision = 'revise') >= 4 then
      raise exception 'after 4 revise rounds on topic % the CEO approves or replaces the topic', new.topic_id;
    end if;
    return new;
  end if;
  if new.decision is not null then raise exception 'a round is submitted undecided'; end if;
  if new.round > 1 then
    select * into v_prev from public.marketing_article_round where article_id = new.article_id and round = new.round - 1;
    if v_prev.decision is distinct from 'revise' then
      raise exception 'round % of article % follows only a revise decision', new.round, new.article_id;
    end if;
    select string_agg(k.key, ', ' order by k.key) into v_missing
      from jsonb_each(v_prev.reasons) k
     where k.value->>'verdict' = 'fail'
       and not exists (select 1 from jsonb_array_elements(coalesce(new.changes, '[]'::jsonb)) c
                        where c->>'criterion' = k.key and length(btrim(coalesce(c->>'change', ''))) >= 10);
    if v_missing is not null then
      raise exception 'the revision does not say what changed for the CEO''s reason(s): %', v_missing;
    end if;
  end if;
  return new;
end $fn$;
revoke execute on function public.fn_marketing_article_round_guard() from public, anon, authenticated;
drop trigger if exists a10_marketing_article_round_guard on public.marketing_article_round;
create trigger a10_marketing_article_round_guard before insert or update or delete on public.marketing_article_round
  for each row execute function public.fn_marketing_article_round_guard();

-- ── 1. topics ────────────────────────────────────────────────────────────────────────────────────────────────────
create or replace function public.fn_marketing_blog_topic_candidates()
returns table (topic_key text, kind text, title text, trade text, score numeric, evidence jsonb, sources jsonb)
language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  with used as (
    select t.topic_key from public.marketing_blog_topic t where t.status = 'published' or t.picked_at > now() - interval '90 days'
  ), c as (
    -- what the seat judged relevant among the searches and news of the last 21 days (a search interest first)
    select 'trend:' || m.id as topic_key, s.kind, m.title, null::text as trade,
           (case s.kind when 'search' then 10 when 'regulation' then 8 else 6 end)
             + round((greatest(0, 21 - extract(epoch from now() - coalesce(m.published_at, m.seen_at)) / 86400) / 7)::numeric, 2) as score,
           jsonb_build_array(jsonb_build_object('kind', s.kind, 'source', s.name, 'title', m.title, 'url', m.url,
             'published_at', m.published_at, 'why_it_matters', m.why_it_matters)) as evidence,
           jsonb_build_array(jsonb_build_object('ref', 'trend:' || m.id, 'url', m.url, 'title', m.title,
             'text', m.title || '. ' || coalesce(m.why_it_matters, ''))) as sources
      from public.marketing_trend m join public.marketing_trend_source s on s.id = m.source_id
     where m.relevant and coalesce(m.published_at, m.seen_at) > now() - interval '21 days'
    union all
    -- the trades buyers asked for in 90 days (never a demo customer), grounded in the trade's verified knowledge
    select 'demand:' || d.trade, 'demand', coalesce(tt.label, d.trade), d.trade, (4 + 2 * d.asked)::numeric,
           jsonb_build_array(jsonb_build_object('kind', 'demand', 'trade', d.trade, 'inquiries_90d', d.asked)),
           k.sources
      from (select x.trade, count(*) as asked
              from public.inquiries i
              left join public.customers cu on cu.id = i.customer_id
              cross join lateral unnest(i.trades) x(trade)
             where i.created_at > now() - interval '90 days'
               and not coalesce(cu.is_demo, false) and coalesce(cu.email, '') !~* '@example\.invalid$'
             group by x.trade) d
      left join public.taxonomy_trade tt on tt.code = d.trade
      cross join lateral (
        select jsonb_agg(jsonb_build_object('ref', sk.record_id, 'url', sk.source_ids[1], 'title', sk.title,
                                            'text', left(sk.content, 3000))) as sources, count(*) as n
          from (select * from public.sales_knowledge k2
                 where ('trade:' || d.trade) = any(k2.tags) and 'verified_pack' = any(k2.tags) and 'lang:en' = any(k2.tags)
                   and coalesce(array_length(k2.source_ids, 1), 0) > 0
                 order by k2.record_id limit 6) sk) k
     where k.n >= 3
  )
  select c.* from c where c.topic_key not in (select u.topic_key from used u)
$fn$;
revoke execute on function public.fn_marketing_blog_topic_candidates() from public, anon, authenticated;

-- ONE topic open at a time, and none while an approved article waits for its release week.
create or replace function public.fn_marketing_blog_topic_pick()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare c record; v_considered jsonb; v_lessons jsonb; v_id bigint;
begin
  if exists (select 1 from public.marketing_blog_topic where status = 'picked') then
    return jsonb_build_object('picked', null, 'reason', 'a topic is open');
  end if;
  if exists (select 1 from public.marketing_article where kind = 'market_topic' and status in ('approved', 'released') and not is_demo) then
    return jsonb_build_object('picked', null, 'reason', 'an approved article waits for its release');
  end if;
  select * into c from public.fn_marketing_blog_topic_candidates() order by score desc, topic_key limit 1;
  if c.topic_key is null then
    return jsonb_build_object('picked', null, 'reason', 'no candidate: no relevant search or news in 21 days and no trade asked for in 90 days');
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('topic_key', x.topic_key, 'title', x.title, 'score', x.score) order by x.score desc), '[]'::jsonb)
    into v_considered
    from (select * from public.fn_marketing_blog_topic_candidates() where topic_key <> c.topic_key order by score desc, topic_key limit 5) x;
  select coalesce(jsonb_agg(l.v order by l.at desc), '[]'::jsonb) into v_lessons
    from (select e.v, t.closed_at as at from public.marketing_blog_topic t, jsonb_array_elements(t.learned) e(v)
           where t.status = 'replaced' order by t.closed_at desc limit 20) l;
  insert into public.marketing_blog_topic (topic_key, kind, title, trade, score, evidence, sources, considered, lessons)
  values (c.topic_key, c.kind, c.title, c.trade, c.score, c.evidence, c.sources, v_considered, v_lessons)
  returning id into v_id;
  return jsonb_build_object('picked', v_id, 'topic_key', c.topic_key, 'title', c.title, 'score', c.score);
end $fn$;
revoke execute on function public.fn_marketing_blog_topic_pick() from public, anon, authenticated;

-- A topic that could not be made useful: its draft is withdrawn, what its rounds taught is kept for the next topic,
-- and the next topic is picked at once. The cycle never ends and never goes to the founder.
create or replace function public.fn_marketing_blog_topic_replace(p_topic_id bigint, p_reason text)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_learned jsonb;
begin
  if btrim(coalesce(p_reason, '')) = '' then raise exception 'a topic is replaced with its reason'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('round', r.round, 'criterion', k.key, 'reason', k.value->>'reason')
                            order by r.round, k.key), '[]'::jsonb)
    into v_learned
    from public.marketing_article_round r cross join lateral jsonb_each(r.reasons) k
   where r.topic_id = p_topic_id and k.value->>'verdict' = 'fail';
  update public.marketing_blog_topic
     set status = 'replaced', replaced_reason = left(p_reason, 2000), closed_at = now(),
         learned = v_learned || jsonb_build_array(jsonb_build_object('criterion', 'topic', 'reason', left(p_reason, 1000)))
   where id = p_topic_id and status = 'picked';
  if not found then return jsonb_build_object('replaced', false, 'reason', 'not an open topic'); end if;
  update public.marketing_article set status = 'withdrawn', withdrawn_reason = left('topic replaced: ' || p_reason, 2000),
         withdrawn_at = now(), updated_at = now()
   where topic_id = p_topic_id and status = 'draft';
  return jsonb_build_object('replaced', true, 'next', public.fn_marketing_blog_topic_pick());
end $fn$;
revoke execute on function public.fn_marketing_blog_topic_replace(bigint, text) from public, anon, authenticated;

-- ── 2. draft, review, revision ──────────────────────────────────────────────────────────────────────────────────
create or replace function public.fn_marketing_blog_draft_due()
returns table (topic_id bigint, kind text, title text, trade text, evidence jsonb, sources jsonb, lessons jsonb)
language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  select t.id, t.kind, t.title, t.trade, t.evidence, t.sources, t.lessons
    from public.marketing_blog_topic t
   where t.status = 'picked' and not exists (select 1 from public.marketing_article a where a.topic_id = t.id)
$fn$;
revoke execute on function public.fn_marketing_blog_draft_due() from public, anon, authenticated;

create or replace function public.fn_marketing_blog_review_due()
returns table (round_id bigint, article_id bigint, slug text, round int, version jsonb, drafted_by_model text,
               changes jsonb, topic jsonb, history jsonb, revise_rounds int)
language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  select r.id, r.article_id, a.slug, r.round, r.version, r.drafted_by_model, r.changes,
         jsonb_build_object('title', t.title, 'kind', t.kind, 'evidence', t.evidence, 'sources', t.sources),
         (select coalesce(jsonb_agg(jsonb_build_object('round', p.round, 'decision', p.decision, 'reasons', p.reasons,
                                                       'changes', p.changes) order by p.round), '[]'::jsonb)
            from public.marketing_article_round p where p.article_id = r.article_id and p.round < r.round),
         (select count(*) from public.marketing_article_round p where p.topic_id = r.topic_id and p.decision = 'revise')::int
    from public.marketing_article_round r
    join public.marketing_article a on a.id = r.article_id
    join public.marketing_blog_topic t on t.id = r.topic_id
   where r.decision is null and a.status = 'draft' and t.status = 'picked'
   order by r.created_at, r.id
$fn$;
revoke execute on function public.fn_marketing_blog_review_due() from public, anon, authenticated;

create or replace function public.fn_marketing_blog_revise_due()
returns table (article_id bigint, topic_id bigint, slug text, round int, version jsonb, reasons jsonb, sources jsonb, history jsonb)
language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  select r.article_id, r.topic_id, a.slug, r.round, r.version, r.reasons, t.sources,
         (select coalesce(jsonb_agg(jsonb_build_object('round', p.round, 'reasons', p.reasons, 'changes', p.changes) order by p.round), '[]'::jsonb)
            from public.marketing_article_round p where p.article_id = r.article_id and p.round < r.round)
    from public.marketing_article_round r
    join public.marketing_article a on a.id = r.article_id
    join public.marketing_blog_topic t on t.id = r.topic_id
   where r.decision = 'revise' and a.status = 'draft' and t.status = 'picked'
     and r.round = (select max(q.round) from public.marketing_article_round q where q.article_id = r.article_id)
   order by r.reviewed_at, r.id
$fn$;
revoke execute on function public.fn_marketing_blog_revise_due() from public, anon, authenticated;

-- A draft or a revision the seat's code gate passed. p: {topic_id, slug, en, ar, post, changes, model, is_demo}.
-- Refused here: an open topic only; no supplier named; not about QuotesDone (a guard on our own outgoing text).
create or replace function public.fn_marketing_blog_submit(p jsonb)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  t public.marketing_blog_topic; a public.marketing_article; v_prev public.marketing_article_round;
  v_all text; v_head text; v_name text; v_slug text; v_round int; v_ing jsonb;
begin
  select * into t from public.marketing_blog_topic where id = (p->>'topic_id')::bigint for update;
  if t.id is null or t.status <> 'picked' then return jsonb_build_object('ok', false, 'error', 'topic_not_open'); end if;
  v_head := lower(concat_ws(' ', p#>>'{en,title}', p#>>'{en,excerpt}', p#>>'{en,meta_desc}',
                                 p#>>'{ar,title}', p#>>'{ar,excerpt}', p#>>'{ar,meta_desc}'));
  -- the brand is written QuotesDone in Latin letters in both languages (docs/marketing/writing_style.md)
  if v_head ~ 'quotes ?done' then
    return jsonb_build_object('ok', false, 'error', 'about_quotesdone', 'detail', 'a blog is a market topic: its title, excerpt and description do not name QuotesDone');
  end if;
  v_all := lower(concat_ws(' ', p#>>'{en,title}', p#>>'{en,excerpt}', p#>>'{en,meta_desc}', p#>>'{en,body_html}',
                                p#>>'{ar,title}', p#>>'{ar,excerpt}', p#>>'{ar,meta_desc}', p#>>'{ar,body_html}'));
  -- a supplier is any company in the invited pool: a full name of two or more words (a single word is too common to be a name)
  select btrim(l.company_name) into v_name from public.leads l
   where length(btrim(l.company_name)) >= 8 and btrim(l.company_name) ~ '\s'
     and strpos(v_all, lower(btrim(l.company_name))) > 0
   limit 1;
  if v_name is not null then
    return jsonb_build_object('ok', false, 'error', 'names_a_supplier', 'detail', 'the article names "' || v_name || '"; a blog never names a supplier');
  end if;
  select * into a from public.marketing_article where topic_id = t.id and status = 'draft' for update;
  if a.id is null then
    if exists (select 1 from public.marketing_article where topic_id = t.id) then
      return jsonb_build_object('ok', false, 'error', 'topic_article_closed');
    end if;
    v_round := 1; v_slug := lower(btrim(coalesce(p->>'slug', '')));
    -- fn_marketing_article_ingest overwrites a DRAFT with the same slug: a new topic never takes another article over
    if exists (select 1 from public.marketing_article where slug = v_slug) then
      return jsonb_build_object('ok', false, 'error', 'slug_taken', 'detail', 'the slug ' || v_slug || ' belongs to another article; choose another title');
    end if;
  else
    select * into v_prev from public.marketing_article_round where article_id = a.id order by round desc limit 1;
    if v_prev.decision is distinct from 'revise' then
      return jsonb_build_object('ok', false, 'error', 'not_awaiting_a_revision', 'round', v_prev.round, 'decision', v_prev.decision);
    end if;
    v_round := v_prev.round + 1; v_slug := a.slug;
  end if;
  v_ing := public.fn_marketing_article_ingest(jsonb_build_object('slug', v_slug, 'kind', 'market_topic', 'ingested_by', 'claude',
             'is_demo', coalesce((p->>'is_demo')::boolean, false), 'en', p->'en', 'ar', p->'ar', 'sources', t.sources,
             'checks', jsonb_build_object('lint', '[]'::jsonb, 'ungrounded', '[]'::jsonb), 'post', p->'post'));
  if not coalesce((v_ing->>'ok')::boolean, false) or coalesce((v_ing->>'unchanged')::boolean, false) then
    return v_ing || jsonb_build_object('ok', false);
  end if;
  update public.marketing_article set topic_id = t.id where id = (v_ing->>'id')::bigint returning * into a;
  insert into public.marketing_article_round (article_id, topic_id, round, version, fingerprint, drafted_by_model, changes)
  values (a.id, t.id, v_round, jsonb_build_object('en', p->'en', 'ar', p->'ar'), public.fn_marketing_article_fingerprint(a.id),
          nullif(p->>'model', ''), case when v_round > 1 then coalesce(p->'changes', '[]'::jsonb) end);
  return jsonb_build_object('ok', true, 'article_id', a.id, 'slug', a.slug, 'round', v_round);
end $fn$;
revoke execute on function public.fn_marketing_blog_submit(jsonb) from public, anon, authenticated;

-- The CEO's decision on one round. The round's CHECK and trigger refuse a decision without its six reasons, a fifth
-- revise on the topic, and a second decision on the same round.
create or replace function public.fn_marketing_blog_review(p_round_id bigint, p_decision text, p_reasons jsonb, p_model text)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare r public.marketing_article_round; v_slug text; v_out jsonb;
begin
  select * into r from public.marketing_article_round where id = p_round_id for update;
  if r.id is null or r.decision is not null then return jsonb_build_object('ok', false, 'error', 'not_awaiting_review'); end if;
  update public.marketing_article_round
     set decision = p_decision, reasons = p_reasons, reviewed_by_model = nullif(p_model, ''), reviewed_at = now()
   where id = r.id;
  if p_decision = 'approve' then
    select slug into v_slug from public.marketing_article where id = r.article_id;
    v_out := public.fn_marketing_article_approve(v_slug, 'ceo');
    if not coalesce((v_out->>'ok')::boolean, false) then raise exception 'the CEO''s approval was refused: %', v_out; end if;
  elsif p_decision = 'replace_topic' then
    v_out := public.fn_marketing_blog_topic_replace(r.topic_id, 'the CEO replaced the topic at round ' || r.round || ': '
      || (select string_agg(k.key || ' - ' || (k.value->>'reason'), '; ' order by k.key) from jsonb_each(p_reasons) k where k.value->>'verdict' = 'fail'));
  end if;
  return jsonb_build_object('ok', true, 'round', r.round, 'article_id', r.article_id, 'decision', p_decision, 'then', v_out);
end $fn$;
revoke execute on function public.fn_marketing_blog_review(bigint, text, jsonb, text) from public, anon, authenticated;

-- ── 3. approve, release, live ───────────────────────────────────────────────────────────────────────────────────
-- Only the CEO seat approves an article, and only one whose latest round it decided "approve". The founder never does.
create or replace function public.fn_marketing_article_approve(p_slug text, p_by text)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_id bigint;
begin
  if p_by is distinct from 'ceo' then return jsonb_build_object('ok', false, 'error', 'only_the_ceo_seat_approves_an_article'); end if;
  update public.marketing_article a set status = 'approved', approved_by = 'ceo', approved_at = now(), updated_at = now()
   where a.slug = p_slug and a.status = 'draft' and a.kind = 'market_topic'
     and (select r.decision from public.marketing_article_round r where r.article_id = a.id order by r.round desc limit 1) = 'approve'
  returning a.id into v_id;
  return jsonb_build_object('ok', v_id is not null, 'slug', p_slug, 'error', case when v_id is null then 'no_approved_review_round' end);
end $fn$;
revoke execute on function public.fn_marketing_article_approve(text, text) from public, anon, authenticated;

-- The cadence: the CEO's approval, a market topic, a UAE working day, at most ONE a Dubai week (founder 1058: a hard
-- limit, not the policy value), one a day, and only while publishing is switched on.
create or replace function public.fn_marketing_article_release_due()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  v_now timestamp := now() at time zone 'Asia/Dubai';
  v_week int; v_today int; v_next public.marketing_article;
begin
  -- ONE CALLER AT A TIME (release review, 29 Sep 2026): two overlapping ticks each counted 0 releases this week and
  -- each skip-locked a DIFFERENT approved row, so the week got two blogs. The lock serialises the count and the release.
  perform pg_advisory_xact_lock(hashtext('fn_marketing_article_release_due'));
  if not public.fn_is_working_day(v_now::date) then
    return jsonb_build_object('released', null, 'reason', 'not a UAE working day');
  end if;
  select count(*) filter (where released_at at time zone 'Asia/Dubai' >= date_trunc('week', v_now)),
         count(*) filter (where (released_at at time zone 'Asia/Dubai')::date = v_now::date)
    into v_week, v_today from public.marketing_article where released_at is not null and not is_demo;
  if v_week >= 1 or v_today > 0 then
    return jsonb_build_object('released', null, 'this_week', v_week, 'reason', 'one blog a week');
  end if;
  select * into v_next from public.marketing_article
   where status = 'approved' and approved_by = 'ceo' and kind = 'market_topic' and not is_demo
   order by approved_at, id limit 1 for update skip locked;
  if not found then return jsonb_build_object('released', null, 'this_week', v_week, 'reason', 'nothing_approved_by_the_ceo'); end if;
  if not public.fn_marketing_publishing_live() then
    return jsonb_build_object('released', null, 'held', true, 'would_release', v_next.slug, 'reason', 'marketing_golive is not true');
  end if;
  update public.marketing_article set status = 'released', released_at = now(), updated_at = now() where id = v_next.id;
  return jsonb_build_object('released', v_next.slug, 'this_week', v_week + 1);
end $fn$;
revoke execute on function public.fn_marketing_article_release_due() from public, anon, authenticated;

-- Live: its LinkedIn company-page post is scheduled (as before), the topic is published and the next is picked, and
-- the founder is TOLD, once: an FYI with no reply-to and nothing to answer. No customer, supplier or lead is written to.
create or replace function public.fn_marketing_article_mark_live(p_slug text)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_a public.marketing_article; v_posts int; v_fyi bigint; v_rounds int;
begin
  update public.marketing_article set status = 'live', live_at = now(), updated_at = now()
   where slug = p_slug and status = 'released' returning * into v_a;
  if v_a.id is null then return jsonb_build_object('ok', false, 'error', 'not_released'); end if;
  update public.marketing_post set status = 'scheduled', scheduled_at = now() + interval '5 minutes', updated_at = now()
   where ingest_key = v_a.linkedin_post_key and status = 'draft';
  get diagnostics v_posts = row_count;
  if v_a.topic_id is not null then
    update public.marketing_blog_topic set status = 'published', closed_at = now() where id = v_a.topic_id and status = 'picked';
  end if;
  if not v_a.is_demo then
    select count(*) into v_rounds from public.marketing_article_round where article_id = v_a.id;
    v_fyi := public.fn_marketing_mail_founder('marketing_article_live',
      'FYI - published on the blog: ' || left(v_a.title_en, 140),
      'For your information: this week''s blog article is live, in English and Arabic.' || E'\n\n'
      || v_a.title_en || E'\n' || 'https://quotesdone.ae/blog/' || v_a.slug || E'\n\n'
      || v_a.title_ar || E'\n' || 'https://quotesdone.ae/ar/blog/' || v_a.slug || E'\n\n'
      || 'The CEO seat approved it after ' || v_rounds || ' review round(s). Nothing is needed from you.');
  end if;
  return jsonb_build_object('ok', true, 'slug', p_slug, 'linkedin_post_scheduled', v_posts = 1, 'founder_fyi', v_fyi,
                            'next_topic', public.fn_marketing_blog_topic_pick());
end $fn$;
revoke execute on function public.fn_marketing_article_mark_live(text) from public, anon, authenticated;

-- The seat duty (daily): a topic is always open when one can be, and an article the CEO approved never waits more
-- than 8 days on a live switch. It mails nobody.
create or replace function public.fn_marketing_article_release_duty()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_stuck text; v_pick jsonb;
begin
  select slug into v_stuck from public.marketing_article
   where status = 'approved' and approved_by = 'ceo' and not is_demo and approved_at < now() - interval '8 days' limit 1;
  if v_stuck is not null and public.fn_marketing_publishing_live() then
    raise exception 'article % was approved by the CEO seat more than 8 days ago and is not released', v_stuck;
  end if;
  v_pick := public.fn_marketing_blog_topic_pick();
  return jsonb_build_object('topic', v_pick,
    'open_topic', (select jsonb_build_object('id', id, 'title', title, 'kind', kind) from public.marketing_blog_topic where status = 'picked'),
    'in_review', (select count(*) from public.marketing_article_round r join public.marketing_article a on a.id = r.article_id
                   where r.decision is null and a.status = 'draft'),
    'approved', (select count(*) from public.marketing_article where status = 'approved' and not is_demo),
    'live', (select count(*) from public.marketing_article where status = 'live' and not is_demo));
end $fn$;
revoke execute on function public.fn_marketing_article_release_duty() from public, anon, authenticated;

-- ── 4. his reply: the launch plan only; article approval is retired ────────────────────────────────────────────
create or replace function public.fn_marketing_approval_reply(p jsonb)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  v_token text := lower(coalesce(p->>'token', '')); v_from text := lower(btrim(coalesce(p->>'from_email', '')));
  d public.marketing_plan_doc; v_out text; v_what text; v_msg text;
begin
  if v_from is distinct from public.fn_marketing_founder_email() then return jsonb_build_object('outcome', 'not_the_founder'); end if;
  -- ARTICLE APPROVAL IS RETIRED (founder 1058): a reply to any article approval email ever sent changes nothing.
  if v_token <> '' and (exists (select 1 from public.marketing_article where approval_token = v_token)
       or exists (select 1 from public.notifications where kind = 'marketing_article_approval'
                   and reply_to = 'approve+' || v_token || '@mail.quotesdone.com')) then
    perform public.fn_marketing_mail_founder('marketing_approval_reply', 'Not changed: article approval is retired',
      'Blog articles are no longer approved by you: the CEO seat reviews each one, and you are told only when one goes live. '
      || 'Your reply changed nothing and published nothing.');
    return jsonb_build_object('outcome', 'article_approval_retired');
  end if;
  select * into d from public.marketing_plan_doc where approval_token = v_token and v_token <> '' for update;
  v_what := case when d.id is not null then 'launch plan for ' || to_char(d.period, 'FMMonth YYYY') end;
  if v_what is null then
    v_out := 'unknown'; v_msg := 'Your reply did not match an approval email, so nothing was changed. Please reply to the latest one.';
  elsif not coalesce((p->>'authenticated')::boolean, false) then
    v_out := 'not_authenticated';
    v_msg := 'A reply about the ' || v_what || ' arrived with your address but could not be verified as coming from your mailbox, so nothing was changed.';
  elsif d.status <> 'sent_to_founder' then
    v_out := 'already_decided'; v_msg := 'The ' || v_what || ' was already decided; nothing was changed.';
  elsif p->>'intent' = 'approve' then
    update public.marketing_plan_doc set status = 'approved', decided_at = now(), updated_at = now() where id = d.id;
    v_out := 'approved'; v_msg := 'Approved: the ' || v_what || '. The marketing seat runs it from 1 January 2027.';
  elsif btrim(coalesce(p->>'text', '')) = '' then
    -- an empty reply is not a change: nothing is filed, the token stays valid, and the item is still his to approve
    v_out := 'empty_reply';
    v_msg := 'Your reply about the ' || v_what || ' was empty, so nothing was changed and it is still waiting for you. '
          || 'Reply "approve" to the same email, or write the change you want.';
  else
    -- his change joins the plan (founder_changes) and the next daily redraw is re-sent to him with it
    update public.marketing_plan_doc set status = 'change_requested', founder_note = left(btrim(p->>'text'), 4000),
           founder_changes = founder_changes || to_jsonb(left(btrim(p->>'text'), 4000)),
           approval_token = null, decided_at = now(), updated_at = now() where id = d.id;
    v_out := 'change_requested';
    v_msg := 'Your change to the ' || v_what || ' is written into the plan, which is sent back to you with it. '
          || 'Nothing is run until you approve the new version.';
  end if;
  perform public.fn_marketing_mail_founder('marketing_approval_reply',
    case when v_out = 'approved' then 'Approved: ' when v_out = 'change_requested' then 'Change noted: ' else 'Not changed: ' end || coalesce(v_what, 'approval'), v_msg);
  return jsonb_build_object('outcome', v_out, 'plan_doc', d.id);
end $fn$;
revoke execute on function public.fn_marketing_approval_reply(jsonb) from public, anon, authenticated;

insert into public.founder_mail_policy (kind, allowed_to_email, reason, owner_role) values
  ('marketing_article_live', true, 'Founder 1058, 29 Sep 2026: an FYI when a blog article goes live. Informational; it asks him for nothing and carries no reply token.', 'marketing'),
  ('marketing_article_approval', false, 'Retired 29 Sep 2026 (founder 1058): the founder never approves a blog; the CEO seat reviews each article.', 'marketing'),
  ('marketing_approval_reply', true, 'The answer to his reply to a launch-plan approval email, or to an old article approval email (article approval is retired).', 'marketing')
on conflict (kind) do update set allowed_to_email = excluded.allowed_to_email, reason = excluded.reason, owner_role = excluded.owner_role, updated_at = now();

-- ── 5. clean-up ─────────────────────────────────────────────────────────────────────────────────────────────────
-- The four drafts about QuotesDone leave the blog queue; the rows stay. Every article approval token is cleared.
update public.marketing_article
   set status = 'withdrawn', withdrawn_at = now(), updated_at = now(), approval_token = null,
       withdrawn_reason = 'About QuotesDone itself. Founder 1058 (29 Sep 2026): a blog covers a trending market topic tied to the business, never QuotesDone.'
 where status = 'draft' and not is_demo and kind in ('how_it_works', 'buyer_guide', 'trade_explainer');
update public.marketing_article set approval_token = null, updated_at = now() where approval_token is not null;
alter table public.marketing_article drop constraint if exists marketing_article_withdrawn_says_why;
alter table public.marketing_article add constraint marketing_article_withdrawn_says_why
  check (status <> 'withdrawn' or withdrawn_reason is not null);

-- ── 5b. the two new tables are in the daily export (every_marketing_table_is_in_the_daily_export) ─────────────
-- Rebuilt from main's CURRENT canonical body (#1039's file, the last definer in MANIFEST.txt on 29 Sep 2026) with ONLY
-- marketing_blog_topic and marketing_article_round added.
create or replace function public.fn_table_export_list()
returns table(table_name text, subject text, change_log text)
language sql stable set search_path to 'public', 'pg_temp' as $fn$
  select v.t, v.s,
         (select 'table_export_change' from public.table_export_change_tracked x where x.table_name = v.t)
  from (values
    ('founder_mail_policy','decision'), ('marketing_article_round','marketing'), ('marketing_blog_topic','marketing'),
    ('fraud_flags','risk'), ('free_email_domain','risk'), ('money_move_hold','risk'), ('seat_handoff_kind','decision'), ('supplier_availability','supplier'),
    ('quote_quality_hold','quote'),
    ('stalled_inquiry_rescue','inquiry'),
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
    ('marketing_post_platform','marketing'), ('marketing_post_channel_result','marketing'), ('marketing_calendar_resend_decision','marketing'), ('marketing_post_metric','marketing'), ('marketing_first_touch','marketing'),
    ('marketing_goal','marketing'), ('marketing_scorecard_report','marketing'),
    ('marketing_asset_feature','marketing'), ('marketing_asset_perception','marketing'), ('marketing_asset_review','marketing'),
    ('marketing_insight_note','marketing'), ('marketing_month_plan','marketing'), ('marketing_plan_review_turn','marketing'),
    ('marketing_model_run','marketing'), ('marketing_trend_source','marketing'), ('marketing_trend','marketing'),
    ('marketing_geo_question','marketing'), ('marketing_geo_check','marketing'), ('marketing_review','marketing'), ('market_intel','marketing'), ('competitor','marketing'), ('marketing_knowledge','knowledge'),
    ('marketing_recruitment_source','marketing'), ('marketing_gap_recruitment_plan','marketing'), ('marketing_plan_doc','marketing'),
    ('table_export_change','backup'),
    -- 1056: the model routing the founder rules on, and what every seat runs on
    ('model_policy','model_routing'), ('model_policy_by_identity','model_routing'), ('model_registry','model_routing'),
    ('fn_task_class','model_routing'), ('review_pool','model_routing'), ('paid_route_exception','model_routing'),
    ('it_model_consumer','model_routing')
  ) v(t, s)
  -- The sibling PRs' tables may not exist yet when this applies; backup/index.ts fails the whole day on a
  -- missing table, so ONLY those nine are skipped until their own file creates them. Every other table in the
  -- list still fails loudly if it disappears.
  where v.t not in ('marketing_platform_spec','marketing_platform_spec_source','marketing_campaign','marketing_post_variant',
                    'marketing_post_platform','marketing_post_metric','marketing_first_touch','marketing_goal','marketing_scorecard_report')
     or to_regclass('public.' || v.t) is not null
$fn$;

-- ── 6. the model classes ────────────────────────────────────────────────────────────────────────────────────────
-- Drafting and redrawing are judgements in two languages: the judgement/Arabic row (instruction 844), 8000 tokens for
-- a whole article in both languages; a truncated answer is refused by the duty. The CEO's review reads the article
-- and answers six short reasons; ai_gateway routes it through fn_ai_route_review to a family other than the draft's.
insert into public.model_policy (task_class, tier, model_primary, model_fallback, max_tokens, rationale, deterministic_alternative, active, cache_ttl_min) values
 ('marketing_article_draft', 'large', 'openai/gpt-5.6-sol', 'anthropic/claude-opus-5.5', 8000,
  'Write a blog article (English and Arabic) on a market topic the seat picked from search interest, news or buyer demand, grounded in its cited market sources. A JUDGEMENT in two languages -> the judgement/Arabic row. At most one topic open at a time.',
  'The gate after it is code: checkArticle (style lint both languages, same structure EN/AR, no ungrounded number) and fn_marketing_blog_submit (no supplier named, not about QuotesDone)', true, 0),
 ('marketing_article_revise', 'large', 'openai/gpt-5.6-sol', 'anthropic/claude-opus-5.5', 8000,
  'Redraw a draft article (English and Arabic) answering every reason the CEO seat failed it on, and say what changed for each. A JUDGEMENT in two languages -> the judgement/Arabic row.',
  'The same code gate, and marketing_article_round refuses a revision that leaves a failed reason unanswered', true, 0),
 ('ceo_article_review', 'large', 'anthropic/claude-opus-5.5', 'openai/gpt-5.6-sol', 1500,
  'The CEO seat reviews a blog article against six criteria (useful, a market topic not about QuotesDone, accurate and grounded, names no supplier, language quality, SEO/GEO value) and approves, asks for a revision or replaces the topic. Routed to a family other than the draft''s (counterpart_model).',
  'The decision is validated by code and by marketing_article_round''s CHECK: six verdicts with reasons, approve only when all pass', true, 0)
on conflict (task_class) do update set tier = excluded.tier, model_primary = excluded.model_primary, model_fallback = excluded.model_fallback,
  max_tokens = excluded.max_tokens, rationale = excluded.rationale, deterministic_alternative = excluded.deterministic_alternative,
  active = excluded.active, cache_ttl_min = excluded.cache_ttl_min;

select case
  when to_regprocedure('public.fn_marketing_blog_submit(jsonb)') is null then 'PROBE FAILED: fn_marketing_blog_submit is missing'
  when pg_get_functiondef('public.fn_marketing_article_release_due()'::regprocedure) not like '%pg_advisory_xact_lock%'
    then 'PROBE FAILED: two overlapping release ticks can each release a blog in the same week'
  when public.fn_marketing_review_reasons_ok('approve', '{}'::jsonb) then 'PROBE FAILED: a reasonless approval passes the rubric'
  when exists (select 1 from public.marketing_article where status = 'draft' and not is_demo and kind <> 'market_topic')
    then 'PROBE FAILED: a draft about QuotesDone is still in the blog queue'
  when exists (select 1 from public.marketing_article where approval_token is not null) then 'PROBE FAILED: an article approval token is live'
  when coalesce((select allowed_to_email from public.founder_mail_policy where kind = 'marketing_article_approval'), true)
    then 'PROBE FAILED: an article can still be mailed to the founder for approval'
  when not exists (select 1 from public.model_policy where task_class = 'ceo_article_review' and active) then 'PROBE FAILED: no ceo_article_review class'
  when (select count(*) from public.fn_table_export_list() where table_name in ('marketing_blog_topic', 'marketing_article_round',
          'marketing_plan_doc', 'marketing_recruitment_source', 'marketing_gap_recruitment_plan')) <> 5
    then 'PROBE FAILED: a marketing table is missing from the daily export'
  else 'PROBE OK' end as verdict;
