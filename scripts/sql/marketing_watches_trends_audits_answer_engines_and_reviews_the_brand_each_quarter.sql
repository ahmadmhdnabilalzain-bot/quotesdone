-- MARKETING WATCHES TRENDS, AUDITS THE ANSWER ENGINES AND REVIEWS THE BRAND EACH QUARTER
-- Assigned: marketing. 24 Sep 2026, founder ledger 983 ("every gap fixed") against the approved job description.
--
-- WHAT WAS MEASURED (seats_v3/GAPS.md, "## Marketing", 24 Sep 2026):
--   gap 3  no source watch, no log of trends with a "why it matters" line, nothing feeding the month plan
--          (seat map, 24 Sep: marketing owns "trend-spotting related to the business");
--   gap 5  the blog exists (32 blog_posts) but nothing measures whether search or an answer engine names
--          QuotesDone, and there is no monthly GEO report (instr 894);
--   gap 7  seat_duty 'marketing.recruitment_funnel' said its leads "go first in the invitation queue", against
--          instr 625 ("NOT responsible for the supplier invitation"). Measured: the ordering in
--          fn_supplier_invite_candidates reads public.supply_gap (the SALES ENGINEER's 'recruit' marks), never
--          marketing's funnel table. The code was already right; the ownership sentence was wrong. Fixed here.
--   gap 8  no quarterly brand and positioning review, and no plan for the January 2027 customer launch.
--
-- WHAT THIS CHANGES
--   marketing_trend_source / marketing_trend  public news feeds, read once a Dubai day (code: an RSS parse); each
--       new item is judged relevant-or-not with a one-line reason by think() (surface marketing.trend_relevance,
--       supabase/functions/marketing/duties.ts), at most one per beat. No keyword decides relevance.
--       fn_marketing_trends_for_plan(month) feeds the relevant ones into the plan step's input (marketing_judgement.ts).
--   marketing_geo_question / marketing_geo_check  a fixed set of buyer and supplier questions, asked once a month
--       of a web search (engine 'web': is quotesdone.ae/.com among the results, and at what rank) and of a model
--       asked cold with no company context (engine 'model': does its answer name QuotesDone). Checking whether our
--       own brand name or domain appears in a result is parsing a fact, not deciding a meaning.
--   marketing_review  'geo_monthly' (last month's audit) and 'brand_quarterly' (positioning facts, reach, GEO,
--       competitors, trends, reputation and the January 2027 customer-launch plan), composed by code
--       (fn_marketing_reviews_tick) and handed to the CEO as 'marketing.review' (read by fn_ceo_reads_marketing_review).
--
-- WHAT THIS DOES NOT DO: it posts nothing, emails no one, spends nothing, and reaches no person. The launch plan is
-- a proposal for the CEO's decision (seat map: no customer campaign before January 2027); it launches nothing.
-- It does not touch fn_supplier_invite_candidates or the funnel routine; only the ownership sentence moves.

-- ── 1. TRENDS ────────────────────────────────────────────────────────────────────────────────────────
create table if not exists public.marketing_trend_source (
  id bigint generated always as identity primary key,
  name text not null unique,
  feed_url text not null unique check (feed_url ~ '^https://'),
  active boolean not null default true,
  last_read_at timestamptz,
  last_error text
);
alter table public.marketing_trend_source enable row level security;
drop policy if exists marketing_trend_source_service_role_only on public.marketing_trend_source;
create policy marketing_trend_source_service_role_only on public.marketing_trend_source as permissive for all to public using (false) with check (false);
revoke all on public.marketing_trend_source from anon, authenticated;

create table if not exists public.marketing_trend (
  id bigint generated always as identity primary key,
  source_id bigint not null references public.marketing_trend_source(id) on delete cascade,
  url text not null unique,
  title text not null,
  published_at timestamptz,
  seen_at timestamptz not null default now(),
  relevant boolean,                 -- null: not judged yet (or held); true/false: think() decided
  why_it_matters text,              -- the reason, in one line; required when relevant
  judged_at timestamptz,
  judged_by text,
  check (relevant is distinct from true or coalesce(btrim(why_it_matters), '') <> '')
);
create index if not exists marketing_trend_unjudged on public.marketing_trend (seen_at) where relevant is null;
alter table public.marketing_trend enable row level security;
drop policy if exists marketing_trend_service_role_only on public.marketing_trend;
create policy marketing_trend_service_role_only on public.marketing_trend as permissive for all to public using (false) with check (false);
revoke all on public.marketing_trend from anon, authenticated;

-- Public news searches about what the business lives on. Google News RSS is public and free.
insert into public.marketing_trend_source (name, feed_url) values
  ('UAE construction news',         'https://news.google.com/rss/search?q=UAE+construction+when:7d&hl=en-AE&gl=AE&ceid=AE:en'),
  ('UAE fit-out and MEP',           'https://news.google.com/rss/search?q=Dubai+fit-out+OR+MEP+contractor+when:7d&hl=en-AE&gl=AE&ceid=AE:en'),
  ('UAE procurement and tenders',   'https://news.google.com/rss/search?q=UAE+procurement+tender+construction+when:7d&hl=en-AE&gl=AE&ceid=AE:en'),
  ('UAE building regulation',       'https://news.google.com/rss/search?q=Dubai+Municipality+building+regulation+when:7d&hl=en-AE&gl=AE&ceid=AE:en')
on conflict (name) do nothing;

create or replace function public.fn_marketing_trend_sources_due(p_limit integer default 2)
returns table (id bigint, name text, feed_url text)
language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  select s.id, s.name, s.feed_url from public.marketing_trend_source s
   where s.active and (s.last_read_at is null or s.last_read_at < now() - interval '20 hours')
   order by s.last_read_at nulls first, s.id limit greatest(p_limit, 0)
$fn$;
revoke execute on function public.fn_marketing_trend_sources_due(integer) from public, anon, authenticated;

-- p_items: [{url, title, published_at}] as parsed by marketing_trends.ts parseRss. Returns how many were new.
create or replace function public.fn_marketing_trend_seen(p_source_id bigint, p_items jsonb, p_error text default null)
returns integer language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_new integer := 0;
begin
  update public.marketing_trend_source set last_read_at = now(), last_error = left(p_error, 500) where id = p_source_id;
  if p_error is not null then return 0; end if;
  with ins as (
    insert into public.marketing_trend (source_id, url, title, published_at)
    select p_source_id, left(i->>'url', 2000), left(i->>'title', 500), nullif(i->>'published_at', '')::timestamptz
      from jsonb_array_elements(coalesce(p_items, '[]'::jsonb)) i
     where coalesce(i->>'url', '') ~ '^https?://' and coalesce(btrim(i->>'title'), '') <> ''
    on conflict (url) do nothing returning 1)
  select count(*) into v_new from ins;
  return v_new;
end $fn$;
revoke execute on function public.fn_marketing_trend_seen(bigint, jsonb, text) from public, anon, authenticated;

create or replace function public.fn_marketing_trend_next_to_judge()
returns table (id bigint, title text, url text, source text)
language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  select t.id, t.title, t.url, s.name from public.marketing_trend t join public.marketing_trend_source s on s.id = t.source_id
   where t.relevant is null and t.seen_at > now() - interval '14 days'
   order by t.seen_at desc, t.id desc limit 1
$fn$;
revoke execute on function public.fn_marketing_trend_next_to_judge() from public, anon, authenticated;

create or replace function public.fn_marketing_trend_judged(p_id bigint, p_relevant boolean, p_why text, p_by text)
returns boolean language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
begin
  if p_relevant is null then raise exception 'a trend is judged relevant or not; null is not a judgement'; end if;
  update public.marketing_trend set relevant = p_relevant, why_it_matters = nullif(btrim(p_why), ''),
         judged_at = now(), judged_by = left(p_by, 120)
   where id = p_id and relevant is null;
  return found;
end $fn$;
revoke execute on function public.fn_marketing_trend_judged(bigint, boolean, text, text) from public, anon, authenticated;

-- What the month plan reads (marketing_judgement.ts adds it to the 'plan' step's input).
create or replace function public.fn_marketing_trends_for_plan(p_month date)
returns jsonb language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  select coalesce(jsonb_agg(jsonb_build_object('id', t.id, 'title', t.title, 'url', t.url, 'why_it_matters', t.why_it_matters,
                                               'published_at', t.published_at) order by t.published_at desc nulls last), '[]'::jsonb)
    from (select * from public.marketing_trend
           where relevant and coalesce(published_at, seen_at) >= (p_month - interval '45 days')
           order by coalesce(published_at, seen_at) desc limit 20) t
$fn$;
revoke execute on function public.fn_marketing_trends_for_plan(date) from public, anon, authenticated;

-- ── 2. GEO: DO SEARCH AND THE ANSWER ENGINES NAME US ────────────────────────────────────────────────
create table if not exists public.marketing_geo_question (
  id bigint generated always as identity primary key,
  question text not null unique,
  audience text not null check (audience in ('customer', 'supplier')),
  active boolean not null default true
);
alter table public.marketing_geo_question enable row level security;
drop policy if exists marketing_geo_question_service_role_only on public.marketing_geo_question;
create policy marketing_geo_question_service_role_only on public.marketing_geo_question as permissive for all to public using (false) with check (false);
revoke all on public.marketing_geo_question from anon, authenticated;

insert into public.marketing_geo_question (question, audience) values
  ('How can I get quotes from several contractors for a fit-out in Dubai?', 'customer'),
  ('What is the best platform to compare construction quotes in the UAE?', 'customer'),
  ('Where can I find verified MEP suppliers in Dubai?', 'customer'),
  ('How do I get quotations for building materials in the UAE?', 'customer'),
  ('How can a UAE contractor receive more project enquiries online?', 'supplier'),
  ('Which UAE platforms send construction RFQs to suppliers?', 'supplier')
on conflict (question) do nothing;

create table if not exists public.marketing_geo_check (
  id bigint generated always as identity primary key,
  month date not null check (extract(day from month) = 1),
  question_id bigint not null references public.marketing_geo_question(id) on delete cascade,
  engine text not null check (engine in ('web', 'model')),
  cited boolean not null,
  rank integer,                       -- web: 1-based position of our domain; null when absent or for 'model'
  evidence text,                      -- the matching result URL, or the start of the model's answer
  model text,
  checked_at timestamptz not null default now(),
  unique (month, question_id, engine)
);
alter table public.marketing_geo_check enable row level security;
drop policy if exists marketing_geo_check_service_role_only on public.marketing_geo_check;
create policy marketing_geo_check_service_role_only on public.marketing_geo_check as permissive for all to public using (false) with check (false);
revoke all on public.marketing_geo_check from anon, authenticated;

-- The checks still owed for the current Dubai month. Under the founder's model hold the duty asks for web checks only,
-- so a held model check never blocks the web checks behind it.
create or replace function public.fn_marketing_geo_due(p_limit integer default 2, p_include_model boolean default true)
returns table (question_id bigint, question text, engine text, month date)
language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  with m as (select date_trunc('month', now() at time zone 'Asia/Dubai')::date as month)
  select q.id, q.question, e.engine, m.month
    from public.marketing_geo_question q cross join (values ('web'), ('model')) e(engine) cross join m
   where q.active and (p_include_model or e.engine = 'web') and not exists (select 1 from public.marketing_geo_check c
                                   where c.month = m.month and c.question_id = q.id and c.engine = e.engine)
   order by q.id, e.engine limit greatest(p_limit, 0)
$fn$;
revoke execute on function public.fn_marketing_geo_due(integer, boolean) from public, anon, authenticated;

create or replace function public.fn_marketing_geo_record(p_month date, p_question_id bigint, p_engine text, p_cited boolean,
                                                          p_rank integer, p_evidence text, p_model text default null)
returns bigint language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_id bigint;
begin
  insert into public.marketing_geo_check (month, question_id, engine, cited, rank, evidence, model)
  values (p_month, p_question_id, p_engine, p_cited, p_rank, left(p_evidence, 1000), p_model)
  on conflict (month, question_id, engine) do nothing returning id into v_id;
  return v_id;
end $fn$;
revoke execute on function public.fn_marketing_geo_record(date, bigint, text, boolean, integer, text, text) from public, anon, authenticated;

-- ── 3. THE REVIEWS THE CEO READS ─────────────────────────────────────────────────────────────────────
create table if not exists public.marketing_review (
  id bigint generated always as identity primary key,
  kind text not null check (kind in ('geo_monthly', 'brand_quarterly')),
  period date not null,               -- geo_monthly: the month audited; brand_quarterly: the quarter's first day
  body jsonb not null,
  created_at timestamptz not null default now(),
  handoff_id bigint,
  read_by_ceo_at timestamptz,
  unique (kind, period)
);
alter table public.marketing_review enable row level security;
drop policy if exists marketing_review_service_role_only on public.marketing_review;
create policy marketing_review_service_role_only on public.marketing_review as permissive for all to public using (false) with check (false);
revoke all on public.marketing_review from anon, authenticated;

create or replace function public.fn_marketing_geo_summary(p_month date)
returns jsonb language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  select jsonb_build_object('month', p_month,
    'questions', (select count(distinct question_id) from public.marketing_geo_check where month = p_month),
    'web_cited', (select count(*) from public.marketing_geo_check where month = p_month and engine = 'web' and cited),
    'web_checked', (select count(*) from public.marketing_geo_check where month = p_month and engine = 'web'),
    'model_cited', (select count(*) from public.marketing_geo_check where month = p_month and engine = 'model' and cited),
    'model_checked', (select count(*) from public.marketing_geo_check where month = p_month and engine = 'model'),
    'blog_posts_published', (select count(*) from public.blog_posts where published),
    'rows', (select coalesce(jsonb_agg(jsonb_build_object('question', q.question, 'engine', c.engine, 'cited', c.cited, 'rank', c.rank,
                                                         'evidence', left(c.evidence, 200)) order by q.id, c.engine), '[]'::jsonb)
               from public.marketing_geo_check c join public.marketing_geo_question q on q.id = c.question_id where c.month = p_month))
$fn$;
revoke execute on function public.fn_marketing_geo_summary(date) from public, anon, authenticated;

-- Composes whatever review is due, once, and hands it to the CEO. Code only: every figure is a count of a table.
--   geo_monthly     for LAST month, from the 2nd of this month (its checks are done or it says how many were not).
--   brand_quarterly for THIS quarter, once, in its first 14 days.
create or replace function public.fn_marketing_reviews_tick(p_at timestamptz default now())
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  v_local date := (p_at at time zone 'Asia/Dubai')::date;
  v_last_month date := (date_trunc('month', v_local) - interval '1 month')::date;
  v_quarter date := date_trunc('quarter', v_local)::date;
  v_body jsonb; v_id bigint; v_out jsonb := '{}'::jsonb;
begin
  if extract(day from v_local) >= 2 and not exists (select 1 from public.marketing_review where kind = 'geo_monthly' and period = v_last_month)
     and exists (select 1 from public.marketing_geo_check where month = v_last_month) then
    v_body := public.fn_marketing_geo_summary(v_last_month);
    insert into public.marketing_review (kind, period, body) values ('geo_monthly', v_last_month, v_body)
      on conflict (kind, period) do nothing returning id into v_id;
    if v_id is not null then
      update public.marketing_review set handoff_id = public.fn_seat_handoff('marketing', 'ceo', 'marketing.review', 'marketing_review', v_id::text,
        jsonb_build_object('kind', 'geo_monthly', 'period', v_last_month)) where id = v_id;
      v_out := v_out || jsonb_build_object('geo_monthly', v_id);
    end if;
  end if;

  -- Only in the first 14 days of a quarter, so the file applied mid-quarter does not compose a review of an empty one.
  if v_local < v_quarter + 14 and not exists (select 1 from public.marketing_review where kind = 'brand_quarterly' and period = v_quarter) then
    v_body := jsonb_build_object(
      'quarter', v_quarter,
      'positioning', jsonb_build_object(
        'rule_source', 'profile_text.json (one description everywhere; "smart", never "AI"; no licence number)',
        'social_profiles_checked', (select count(*) from public.marketing_connection_check),
        'social_profiles_failing', (select count(*) from public.marketing_connection_check where not ok)),
      'reach_last_quarter', (select coalesce(jsonb_object_agg(platform, total), '{}'::jsonb) from (
          select platform, sum(value) total from public.marketing_insight_day
           where day >= (v_quarter - interval '3 months') and day < v_quarter group by platform) r),
      'posts_published_last_quarter', (select count(*) from public.marketing_post where status = 'published'
           and published_at >= (v_quarter - interval '3 months') and published_at < v_quarter),
      'geo_last_three_months', (select coalesce(jsonb_agg(public.fn_marketing_geo_summary(m::date) - 'rows' order by m), '[]'::jsonb)
           from generate_series((v_quarter - interval '3 months')::date, (v_quarter - interval '1 month')::date, interval '1 month') g(m)),
      'competitor_posts_seen', (select count(*) from public.market_intel where platform is not null and created_at >= v_quarter - interval '3 months'),
      'relevant_trends', (select count(*) from public.marketing_trend where relevant and seen_at >= v_quarter - interval '3 months'),
      'reputation', (select to_jsonb(s) from public.company_reputation_snapshot s order by day desc limit 1),
      -- THE JANUARY 2027 CUSTOMER LAUNCH (seat map, 24 Sep 2026): no customer campaign before January 2027, and
      -- customers launch only once suppliers can quote every inquiry. This is the proposal the CEO decides on.
      'customer_launch_2027', jsonb_build_object(
        'decision_owner', 'ceo',
        'rule', 'Oct-Dec 2026 supplier registration only; customers from January 2027 once the supplier base can quote every inquiry',
        'supply_gaps_open', (select count(*) from public.supply_gap where status in ('open', 'recruit')),
        'supply_gaps_recruiting', (select count(*) from public.supply_gap where status = 'recruit'),
        'suppliers_registered', (select coalesce(sum(registered), 0) from public.supplier_recruitment_funnel
                                  where day = (select max(day) from public.supplier_recruitment_funnel)),
        'suppliers_approved', (select coalesce(sum(approved), 0) from public.supplier_recruitment_funnel
                                  where day = (select max(day) from public.supplier_recruitment_funnel)),
        'plan', jsonb_build_array(
          'December 2026: the CEO decides the launch against supply_gaps_open = 0 for the launch trades',
          'December 2026: customer landing pages and the blog answer the buyer questions in marketing_geo_question',
          'January 2027: the first customer calendar (organic only) goes to the founder for one-shot approval',
          'January 2027 onward: the monthly GEO audit tracks whether answer engines name QuotesDone to buyers')));
    insert into public.marketing_review (kind, period, body) values ('brand_quarterly', v_quarter, v_body)
      on conflict (kind, period) do nothing returning id into v_id;
    if v_id is not null then
      update public.marketing_review set handoff_id = public.fn_seat_handoff('marketing', 'ceo', 'marketing.review', 'marketing_review', v_id::text,
        jsonb_build_object('kind', 'brand_quarterly', 'period', v_quarter)) where id = v_id;
      v_out := v_out || jsonb_build_object('brand_quarterly', v_id);
    end if;
  end if;
  return v_out;
end $fn$;
revoke execute on function public.fn_marketing_reviews_tick(timestamptz) from public, anon, authenticated;

create or replace function public.fn_ceo_reads_marketing_review(p_id bigint)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare a public.agent_actions; r public.marketing_review;
begin
  select * into a from public.agent_actions where id = p_id and kind = 'handoff';
  if not found or a.detail->>'type' is distinct from 'marketing.review' then
    raise exception 'fn_ceo_reads_marketing_review: % is not a marketing.review handoff', p_id;
  end if;
  update public.marketing_review set read_by_ceo_at = coalesce(read_by_ceo_at, now())
   where id = (a.detail->>'subject_id')::bigint returning * into r;
  if r.id is null then raise exception 'marketing.review % names review %, which does not exist', p_id, a.detail->>'subject_id'; end if;
  return jsonb_build_object('read', true, 'read_at', r.read_by_ceo_at, 'kind', r.kind, 'period', r.period,
                            'note', 'Read by the CEO. The quarterly review carries the January 2027 launch proposal for the CEO''s decision.');
end $fn$;
revoke execute on function public.fn_ceo_reads_marketing_review(bigint) from public, anon, authenticated;

insert into public.seat_handoff_kind (type, from_seat, to_seat, meaning, handler, reply_within, originator_closes, owner_file) values
  ('marketing.review', 'marketing', 'ceo',
   'The marketing seat''s monthly GEO report or quarterly brand and positioning review (with the January 2027 customer-launch proposal), for the CEO to read and decide on.',
   'fn_ceo_reads_marketing_review', interval '3 days', false,
   'scripts/sql/marketing_watches_trends_audits_answer_engines_and_reviews_the_brand_each_quarter.sql')
on conflict do nothing;

-- ── 4. GAP 7: THE INVITATION IS NOT MARKETING'S (instr 625) ─────────────────────────────────────────
update public.seat_duty
   set what = 'Funnel analytics only: a daily funnel per gap the sales engineer marked recruit, and an empty pool is a marketing finding (the lead source). The invitation, and its order, belong to sales_engineer and customer_support (instr 625).'
 where duty = 'marketing.recruitment_funnel';

-- ── 5. PROBE: a verdict ROW (a raise here would roll back the DDL above), nothing left behind, no person reachable ─
create temp table if not exists _marketing_trend_probe (verdict text) on commit drop;
do $probe$
declare v_src bigint; v_n int; v_t bigint; v_bad text := null;
begin
  insert into public.marketing_trend_source (name, feed_url, active) values ('ZZ DEMO probe', 'https://example.invalid/rss', false) returning id into v_src;
  v_n := public.fn_marketing_trend_seen(v_src, '[{"url":"https://example.invalid/a","title":"ZZ DEMO trend"},{"url":"nope","title":"x"}]'::jsonb);
  if v_n <> 1 then v_bad := 'expected 1 new trend, got ' || v_n; end if;
  select id into v_t from public.marketing_trend where source_id = v_src;
  begin
    perform public.fn_marketing_trend_judged(v_t, true, '', 'probe');
    v_bad := coalesce(v_bad, 'a relevant trend without a reason was accepted');
  exception when check_violation then null;
  end;
  if not public.fn_marketing_trend_judged(v_t, false, null, 'probe') then v_bad := coalesce(v_bad, 'judgement not recorded'); end if;
  delete from public.marketing_trend_source where id = v_src;
  if exists (select 1 from public.marketing_trend where url = 'https://example.invalid/a') then v_bad := coalesce(v_bad, 'left a row'); end if;
  insert into _marketing_trend_probe values (case when v_bad is null then 'PROBE OK' else 'PROBE FAILED: ' || v_bad end);
end $probe$;
select verdict from _marketing_trend_probe;
