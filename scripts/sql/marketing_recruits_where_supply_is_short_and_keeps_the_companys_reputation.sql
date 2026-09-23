-- MARKETING RECRUITS SUPPLIERS WHERE SUPPLY IS SHORT, AND KEEPS THE COMPANY'S REPUTATION.
-- Seat: marketing. 23 Sep 2026, founder_instruction 898 (no new agents) and the seat-duties plan (886-898):
-- "TRADE-TARGETED SUPPLIER RECRUITMENT FUNNEL (from sales supply gaps); REPUTATION (Google/directory reviews, feeds GEO)".
-- Needs every_seat_duty_has_an_owner_a_clock_and_a_check.sql and the_sales_engineer_owns_onboarding_performance_and_supply_gaps.sql
-- (public.supply_gap — the sales engineer's gaps, the recruit decisions this funnel works from).
--
-- WHAT WAS MEASURED (production, 23 Sep 2026)
--   * Invitations are ranked by under-activated catalogue domain (fn_supplier_invite_candidates). No trade the sales
--     engineer needs could move a lead up that list, and no funnel — invited, clicked, registered, approved, quoting —
--     existed per trade, so nobody could say whether recruiting for a trade was working. 18,767 leads carry
--     invite_trades, all 40 distinct values taxonomy codes, so a trade can target them by equality.
--   * Reputation: 1 platform review exists; nothing asks a satisfied customer for a PUBLIC review, and app_secrets holds
--     no public review link (Google Business Profile or a directory) — searched for google / review / gbp / maps keys.
--
-- WHAT THIS ADDS — two duties (owner marketing, a clock each, checked by
-- scripts/checks/sales_engineer_and_marketing_duties_act.test.mjs and fn_seat_duty_health):
--   marketing.recruitment_funnel (1 day): every gap the sales engineer marked 'recruit' gets a daily funnel row
--     (public.supplier_recruitment_funnel: uninvited pool, invited, clicked, registered, approved, quoting), and its
--     leads go FIRST in the invitation queue (fn_supplier_invite_candidates, below: one ordering key added, nothing
--     else changed — the go, the cap, the window and every eligibility rule are the invitation machine's). A gap whose
--     pool is empty is a marketing finding (the lead source is the constraint, not the invitation).
--   marketing.reputation (1 day): a customer who rated his job 4 or 5 in the last 30 days is asked ONCE, through
--     customer_support (the only seat that addresses customers), to review QuotesDone publicly, with the link in
--     app_secrets 'public_review_url'. With no link configured the ask is recorded as waiting and the missing link is
--     a marketing finding — the ask goes the day the link exists. A daily snapshot (public.company_reputation_snapshot:
--     reviews, average rating, low ratings, asks) is the one place GEO and site copy may cite the company's standing.
--
-- WHAT THIS DOES NOT DO: it sends no invitation (enqueue_supplier_invites does, under its own gates), reads no review
-- text to decide anything (the rating is a number the customer chose), and does not scrape directories (lead sourcing
-- is paused until 2027).

-- ── 1. the recruitment funnel ────────────────────────────────────────────────────────────────────────────
create table if not exists public.supplier_recruitment_funnel (
  trade       text not null,
  emirate     text not null,
  day         date not null,
  pool        integer not null default 0,
  invited     integer not null default 0,
  clicked     integer not null default 0,
  registered  integer not null default 0,
  approved    integer not null default 0,
  quoting     integer not null default 0,
  primary key (trade, emirate, day)
);
alter table public.supplier_recruitment_funnel enable row level security;
drop policy if exists supplier_recruitment_funnel_service_role_only on public.supplier_recruitment_funnel;
create policy supplier_recruitment_funnel_service_role_only on public.supplier_recruitment_funnel as permissive for all to public using (false) with check (false);
revoke all on public.supplier_recruitment_funnel from anon, authenticated;

create or replace function public.fn_marketing_recruitment_funnel()
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare v_day date := (now() at time zone 'Asia/Dubai')::date; v_rows int; gp record; v_empty int := 0;
begin
  insert into public.supplier_recruitment_funnel as f (trade, emirate, day, pool, invited, clicked, registered, approved, quoting)
  select g.trade, g.emirate, v_day,
         count(*) filter (where l.invite_status is null and not coalesce(l.banned, false) and not coalesce(l.permanently_closed, false)),
         count(*) filter (where l.invited_at is not null),
         count(*) filter (where l.invite_clicked_at is not null),
         count(*) filter (where l.registration_submitted_at is not null or coalesce(l.claimed, false)),
         count(*) filter (where l.approval_status = 'approved'),
         count(*) filter (where exists (select 1 from public.quotes q where q.supplier_id = l.id))
    from public.supply_gap g
    left join public.leads l on g.trade = any(coalesce(l.invite_trades, '{}'::text[]))
                            and (g.emirate = 'UAE' or l.emirate = g.emirate) and coalesce(l.is_demo, false) = false
   where g.status = 'recruit'
   group by g.trade, g.emirate
  on conflict (trade, emirate, day) do update set pool = excluded.pool, invited = excluded.invited, clicked = excluded.clicked,
    registered = excluded.registered, approved = excluded.approved, quoting = excluded.quoting;
  get diagnostics v_rows = row_count;

  -- An empty pool is the lead source, not the invitation: marketing's finding, one per gap, closed when it refills.
  for gp in select f.trade, f.emirate, f.pool from public.supplier_recruitment_funnel f
            join public.supply_gap s on s.trade = f.trade and s.emirate = f.emirate and s.status = 'recruit'
           where f.day = v_day loop
    if gp.pool = 0 then
      v_empty := v_empty + 1;
      perform public.fn_it_engineer_finding_upsert('recruitment:pool_empty:' || gp.trade || ':' || gp.emirate,
        'No uninvited lead is left to recruit for ' || gp.trade || ' (' || gp.emirate || ')',
        'public.supplier_recruitment_funnel', 'monitor', 1,
        jsonb_build_object('trade', gp.trade, 'emirate', gp.emirate, 'owner_seat', 'marketing'), '{}'::text[],
        array['which source can supply leads for this trade while lead scraping is paused'], 'marketing');
    else
      update public.it_engineer_finding set closed_at = now(), close_note = 'the pool has leads again'
       where issue_key = 'recruitment:pool_empty:' || gp.trade || ':' || gp.emirate and closed_at is null;
    end if;
  end loop;
  update public.it_engineer_finding fi set closed_at = now(), close_note = 'the gap is no longer being recruited for'
   where fi.issue_key like 'recruitment:pool_empty:%' and fi.closed_at is null
     and not exists (select 1 from public.supply_gap s where s.status = 'recruit' and 'recruitment:pool_empty:' || s.trade || ':' || s.emirate = fi.issue_key);

  return jsonb_build_object('gaps_recruiting', v_rows, 'empty_pools', v_empty,
    'totals', (select jsonb_build_object('pool', sum(pool), 'invited', sum(invited), 'registered', sum(registered), 'approved', sum(approved), 'quoting', sum(quoting))
                 from public.supplier_recruitment_funnel where day = v_day));
end $fn$;
revoke execute on function public.fn_marketing_recruitment_funnel() from public, anon, authenticated;
grant execute on function public.fn_marketing_recruitment_funnel() to service_role;

-- ── 2. reputation ────────────────────────────────────────────────────────────────────────────────────────
create table if not exists public.company_review_ask (
  customer_id   uuid primary key references public.customers (id) on delete cascade,
  review_id     bigint,
  rating        integer,
  status        text not null check (status in ('asked', 'waiting_link')),
  asked_at      timestamptz,
  created_at    timestamptz not null default now()
);
alter table public.company_review_ask enable row level security;
drop policy if exists company_review_ask_service_role_only on public.company_review_ask;
create policy company_review_ask_service_role_only on public.company_review_ask as permissive for all to public using (false) with check (false);
revoke all on public.company_review_ask from anon, authenticated;

create table if not exists public.company_reputation_snapshot (
  day             date primary key,
  reviews         integer not null,
  avg_rating      numeric,
  low_ratings_30d integer not null,
  asks_sent       integer not null,
  asks_waiting    integer not null
);
alter table public.company_reputation_snapshot enable row level security;
drop policy if exists company_reputation_snapshot_service_role_only on public.company_reputation_snapshot;
create policy company_reputation_snapshot_service_role_only on public.company_reputation_snapshot as permissive for all to public using (false) with check (false);
revoke all on public.company_reputation_snapshot from anon, authenticated;

create or replace function public.fn_marketing_reputation()
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare v_link text := nullif(btrim((select value from public.app_secrets where key = 'public_review_url')), '');
  r record; v_asked int := 0; v_waiting int := 0; v_ar boolean;
begin
  -- The customers owed an ask: a 4 or 5 in the last 30 days, never asked, reachable, not a fixture, not banned.
  insert into public.company_review_ask (customer_id, review_id, rating, status)
  select distinct on (rv.customer_id) rv.customer_id, rv.id, rv.rating, 'waiting_link'
    from public.reviews rv join public.customers c on c.id = rv.customer_id
   where rv.rating >= 4 and rv.created_at > now() - interval '30 days'
     and coalesce(c.banned, false) = false and coalesce(c.is_demo, false) = false and coalesce(btrim(c.email), '') <> ''
   order by rv.customer_id, rv.created_at desc
  on conflict (customer_id) do nothing;

  if v_link is null then
    select count(*) into v_waiting from public.company_review_ask where status = 'waiting_link';
    if v_waiting > 0 then
      perform public.fn_it_engineer_finding_upsert('reputation:no_public_review_link',
        v_waiting || ' satisfied customer(s) are waiting to be asked for a public review, and no review link is configured',
        'app_secrets public_review_url', 'monitor', v_waiting, jsonb_build_object('owner_seat', 'marketing'),
        '{}'::text[], array['the Google Business Profile or directory review link to use'], 'marketing');
    end if;
  else
    update public.it_engineer_finding set closed_at = now(), close_note = 'a public review link is configured'
     where issue_key = 'reputation:no_public_review_link' and closed_at is null;
    for r in select a.customer_id, c.full_name, lower(btrim(c.email)) as email, c.locale
               from public.company_review_ask a join public.customers c on c.id = a.customer_id
              where a.status = 'waiting_link' and a.created_at > now() - interval '60 days' limit 50 loop
      v_ar := r.locale = 'ar';
      -- customer_support is the only seat that addresses a customer; the ask is marketing's, the send is support's.
      perform public.fn_customer_support_takes_delivery(jsonb_build_array(jsonb_build_object(
        'type', 'public_review_ask', 'requested_by', 'customer_support', 'channel', 'email', 'to_email', r.email,
        'to_role', 'customer', 'lang', case when v_ar then 'ar' else 'en' end, 'dedupe_key', 'public_review_ask:' || r.customer_id,
        'subject', case when v_ar then 'شكرًا لتقييمكم، هل تشاركون تجربتكم؟' else 'Thank you for your rating — would you share it?' end,
        'body', case when v_ar then
            'عزيزنا ' || coalesce(nullif(btrim(r.full_name), ''), 'العميل') || '،' || chr(10) || chr(10)
            || 'شكرًا لتقييمكم الإيجابي لتجربتكم معنا. يسعدنا أن تشاركوا رأيكم علنًا، فذلك يساعد غيركم على اختيار موردين موثوقين: '
            || v_link || chr(10) || chr(10) || 'مع خالص الشكر والتقدير،'
          else
            'Dear ' || coalesce(nullif(btrim(r.full_name), ''), 'customer') || ',' || chr(10) || chr(10)
            || 'Thank you for rating your experience so well. If you have a minute, a public review helps other '
            || 'companies find reliable suppliers: ' || v_link || chr(10) || chr(10) || 'QuotesDone' end)));
      update public.company_review_ask set status = 'asked', asked_at = now() where customer_id = r.customer_id;
      v_asked := v_asked + 1;
    end loop;
  end if;

  insert into public.company_reputation_snapshot as s (day, reviews, avg_rating, low_ratings_30d, asks_sent, asks_waiting)
  select (now() at time zone 'Asia/Dubai')::date, count(*), round(avg(rating)::numeric, 2),
         count(*) filter (where rating <= 2 and created_at > now() - interval '30 days'),
         (select count(*) from public.company_review_ask where status = 'asked'),
         (select count(*) from public.company_review_ask where status = 'waiting_link')
    from public.reviews
  on conflict (day) do update set reviews = excluded.reviews, avg_rating = excluded.avg_rating, low_ratings_30d = excluded.low_ratings_30d,
    asks_sent = excluded.asks_sent, asks_waiting = excluded.asks_waiting;
  return jsonb_build_object('asked', v_asked, 'waiting_for_link', v_link is null,
    'snapshot', (select to_jsonb(s) from public.company_reputation_snapshot s where day = (now() at time zone 'Asia/Dubai')::date));
end $fn$;
revoke execute on function public.fn_marketing_reputation() from public, anon, authenticated;
grant execute on function public.fn_marketing_reputation() to service_role;

insert into public.seat_duty (duty, owner_seat, every, routine, what, owner_file) values
  ('marketing.recruitment_funnel', 'marketing', interval '1 day', 'fn_marketing_recruitment_funnel',
   'A daily funnel per gap the sales engineer marked recruit; its leads go first in the invitation queue; an empty pool is a finding.',
   'scripts/sql/marketing_recruits_where_supply_is_short_and_keeps_the_companys_reputation.sql'),
  ('marketing.reputation', 'marketing', interval '1 day', 'fn_marketing_reputation',
   'A satisfied customer is asked once, through customer_support, for a public review; a daily reputation snapshot.',
   'scripts/sql/marketing_recruits_where_supply_is_short_and_keeps_the_companys_reputation.sql')
on conflict (duty) do update set every = excluded.every, routine = excluded.routine, what = excluded.what, owner_file = excluded.owner_file;

-- ── the invitation queue reads the targets (fn_supplier_invite_candidates, otherwise unchanged from
--    the_supplier_invitation_goes_once_in_the_suppliers_language_and_never_to_a_demo_or_sanctioned_lead.sql) ──
create or replace function public.fn_supplier_invite_candidates(p_limit integer)
returns table (lead_id bigint, to_email text, company_name text, lang text, subject text, body text)
language plpgsql
stable
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare v_site text; v_target int;
  v_subj text; v_body text; v_subj_ar text; v_body_ar text;
begin
  select coalesce(nullif(btrim(value), ''), 'https://quotesdone.com') into v_site from app_secrets where key = 'public_site_url';
  v_site := coalesce(v_site, 'https://quotesdone.com');
  select value into v_subj    from app_secrets where key = 'invite_subject';
  select value into v_body    from app_secrets where key = 'invite_body';
  select value into v_subj_ar from app_secrets where key = 'invite_subject_ar';
  select value into v_body_ar from app_secrets where key = 'invite_body_ar';
  -- A template without the link placeholder is the 62-invitations-with-no-way-in failure. Refuse.
  if coalesce(v_body, '') not like '%{{link}}%' then
    raise exception 'app_secrets.invite_body has no {{link}} placeholder: an invitation with no way in is refused';
  end if;
  v_target := coalesce((select nullif(value,'')::int from app_secrets where key='invite_target_per_category'),
                       (select nullif(value,'')::int from app_secrets where key='invite_target_per_trade'), 10);

  -- MATERIALIZED, 4 Aug 2026, and it is load-bearing (see enqueue_supplier_invites' history): both
  -- CTEs are read from a correlated subquery and would otherwise be recomputed per candidate.
  return query
  with activated as materialized (
    select ls.domain_slug, count(distinct l.id) ct
    from leads l join lead_subcategory ls on ls.lead_id = l.id
    where coalesce(l.claimed,false) = true
    group by ls.domain_slug
  ),
  under as materialized (
    select d.slug as domain_slug, coalesce(a.ct,0) as have
    from catalog_domains d left join activated a on a.domain_slug = d.slug
    where coalesce(a.ct,0) < v_target
  ),
  cand as (
    select distinct on (lower(l.email)) l.id, l.email, l.company_name, l.claim_token, l.email_domain, l.email_verified,
           l.invite_trades, l.emirate,
           -- Arabic only where the lead's own locale says so AND the Arabic copy exists; otherwise
           -- English, which is also what a04 assumes for an unregistered recipient.
           case when lower(coalesce(l.locale, '')) like 'ar%' and coalesce(v_body_ar, '') like '%{{link}}%'
                     and coalesce(v_subj_ar, '') <> '' then 'ar' else 'en' end as lang
    from leads l
    where public.fn_supplier_invite_eligible(l)
    order by lower(l.email), l.id
  ),
  prio as (
    select c.id, c.email, c.company_name, c.claim_token, c.email_domain, c.lang,
      -- 23 Sep 2026 (marketing.recruitment_funnel): a lead in a trade the sales engineer marked for recruitment
      -- (public.supply_gap, status 'recruit') goes first. Trade codes compared for equality; no word is read.
      case when exists (select 1 from public.supply_gap g where g.status = 'recruit' and g.trade = any(coalesce(c.invite_trades, '{}'::text[]))
                          and (g.emirate = 'UAE' or g.emirate = c.emirate)) then 0 else 1 end as target_rank,
      coalesce((select u.domain_slug from lead_subcategory ls join under u on u.domain_slug = ls.domain_slug
                 where ls.lead_id = c.id order by u.have asc, ls.score desc limit 1), '~none') as pdomain,
      case when c.email_verified in ('verified','true') then 0 else 1 end as unverified_rank,
      case when split_part(lower(c.email),'@',1) in
             ('info','sales','admin','contact','enquiry','enquiries','inquiry','office','mail',
              'support','hello','marketing','general','accounts','reception','careers','hr')
           then 1 else 0 end as role_rank
    from cand c
  ),
  elig as (
    select r.id, r.email, r.company_name, r.claim_token, r.lang from (
      select p.*,
        case when p.pdomain='~none' then 1 else 0 end as is_none,
        row_number() over (partition by p.pdomain order by p.unverified_rank, p.role_rank, p.id) as rk,
        row_number() over (partition by coalesce(p.email_domain, split_part(p.email,'@',2)) order by p.unverified_rank, p.role_rank, p.id) as domain_rk
      from prio p
    ) r
    where r.domain_rk <= 5
    order by r.target_rank, r.is_none, r.rk, r.unverified_rank, r.role_rank, r.pdomain
    limit greatest(coalesce(p_limit, 0), 0)
  )
  select e.id, btrim(e.email), e.company_name, e.lang,
         case when e.lang = 'ar' then v_subj_ar else v_subj end,
         replace(
           replace(case when e.lang = 'ar'
                        then case when coalesce(btrim(e.company_name), '') = ''
                                  then replace(v_body_ar, 'السادة/ {{company}} المحترمين،', 'السادة الكرام،')
                                  else v_body_ar end
                        else v_body end,
                   '{{company}}', coalesce(nullif(btrim(e.company_name),''), case when e.lang = 'ar' then 'الكرام' else 'there' end)),
           '{{link}}', v_site || '/' || e.lang || '/portal?t=' || e.claim_token::text)
  from elig e;
end
$fn$;
revoke execute on function public.fn_supplier_invite_candidates(integer) from public, anon, authenticated;

