-- THE INVITATION POOL IS READ ONCE, AS A SET, SO THE DAILY LIST FITS ITS TIMEOUT
-- marketing, 28 Sep 2026 (found by it_engineer's end-to-end sweep, ledger 760; campaign go-live, ledger 993).
--
-- MEASURED on production, 28 Sep 2026 18:40 UTC:
--   fn_customer_support_campaign_list_tick has never produced a list: public.supplier_campaign_daily_list
--   has 0 rows, and heartbeat step supportCampaignList has failed every run after 18:00 Dubai with
--   "canceling statement due to statement timeout" (last ok 13:31 UTC, when it was still "before 18:00").
--   PostgREST runs as authenticator with statement_timeout = 8s. Inside the tick:
--     fn_supplier_campaign_next_list        13.3 s
--       count(*) where fn_supplier_invite_eligible(l)   4.1 s (EXPLAIN ANALYZE; 17,401 of 19,907 leads)
--       fn_supplier_invite_candidates(30)               6.5 s (the same per-row call on every lead)
--     fn_supplier_campaign_day_counts        0.01 s
--   The per-row predicate is SECURITY DEFINER with a pinned search_path, so Postgres never inlines it:
--   each of ~20k leads pays a function call, six sub-plans and a plpgsql fn_email_sendable call.
--   The same candidates call sits under enqueue_supplier_invites, the 10:00 Dubai send.
--
-- THE FIX: fn_supplier_invite_eligible_ids() states the SAME rule once over the whole table (anti-joins
-- the planner can hash), and the two set callers read it. fn_supplier_invite_eligible(leads) stays,
-- unchanged, for every single-row caller.
--
-- THIS FILE IS THE ONE DEFINITION OF fn_supplier_invite_candidates FOR BOTH OPEN CHANGES (review of #1051
-- and #1012, 29 Sep 2026). Both PRs had copied the body of
-- the_daily_supplier_list_goes_only_before_a_sending_day_and_a_company_is_invited_once.sql (MANIFEST 1757),
-- which chose the Arabic copy and an /ar/portal link for an Arabic-locale lead, instead of the canonical
-- the_supplier_invitation_ends_with_one_question_and_is_always_english.sql (MANIFEST 1824, #964). Applying
-- either would have brought Arabic invitations back, and each would have overwritten the other. So:
--   * fn_supplier_invite_candidates is the 1824 body, byte for byte, with exactly two lines changed:
--       - the eligibility filter reads fn_supplier_invite_eligible_ids() (#1051, the speed-up);
--       - {{link}} is built by fn_supplier_invite_link (#1012, the ref), which is always /en/portal and carries
--         utm_source=invite&utm_medium=email&utm_campaign=supplier_invite&utm_content=lead-<id>, so a supplier
--         who registers from an invitation can be attributed (src/lib/firstTouch.ts keeps only utm-tagged links).
--     lang is still always 'en' and the Arabic subject/body are still never read.
--   * fn_supplier_invite_link takes no language: there is no argument through which /ar/ could come back.
--   * #1012 (the funnel diagnosis and first touch) no longer defines either routine; it depends on this file.
--   * fn_supplier_campaign_next_list is the canonical body of
--     the_invitations_leave_on_their_own_subdomain_so_a_campaign_cannot_cost_the_sign_up_codes.sql (MANIFEST 1822)
--     with the pool count reading the set.
--
-- MEASURED BEFORE APPLY, inside a transaction that rolled back (28 Sep 2026): the set and row rules agree
-- on 17,401 eligible leads; fn_supplier_campaign_next_list 13.3 s -> 3.0 s; fn_supplier_invite_candidates(30)
-- 6.5 s -> 2.3 s; the set query alone 0.7 s.
--
-- THE PROBE at the foot RAISES on any failure (review of #1051), so a failed apply takes this file's DDL back
-- with it: set rule = row rule lead for lead, every candidate English, every candidate link /en/portal with its
-- ref, and every candidate body ending with the invitation's one question.
-- prevented by: scripts/checks/the_invitation_pool_set_states_the_row_rule.test.mjs

create or replace function public.fn_supplier_invite_eligible_ids()
returns setof bigint
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $fn$
  -- The small reference tables (sanctions 46 rows, screening hits, 37 suppressions, block patterns,
  -- 47 platform domains) are read ONCE into arrays: with the leads estimate at 1 row the planner
  -- chose nested loops and re-read each of them 19,444 times (EXPLAIN ANALYZE, 4.8 s). NULLs are
  -- filtered out of each array, because `x <> all(array[..., null])` is null and would drop every lead.
  select p.id
    from public.leads p
   where coalesce(btrim(p.email), '') <> ''
     and p.invite_status is null
     and coalesce(p.source, '') <> 'self_registered'
     and coalesce(p.claimed, false) = false
     and coalesce(p.banned, false) = false
     and coalesce(p.permanently_closed, false) = false
     and coalesce(p.is_demo, false) = false
     and coalesce(p.company_name, '') !~* '^\s*zz\s*demo'
     and not public.fn_is_demo_email(p.email)
     and p.id <> all (array(select b.lead_id from public.sanctions_ban b where b.lead_id is not null))
     and p.id <> all (array(select h.lead_id from public.supplier_screening_hit h
                             where h.lead_id is not null and h.status in ('open', 'confirmed')))
     and not exists (select 1 from public.notifications n
                      where n.type = 'supplier_invite' and lower(btrim(n.to_email)) = lower(btrim(p.email)))
     -- fn_email_sendable(p.email)->>'ok', clause for clause
     and lower(btrim(p.email)) ~ '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+[.][A-Za-z]{2,}$'
     and lower(btrim(p.email)) <> all (array(select lower(s.email) from public.email_suppressions s where s.email is not null))
     and not exists (select 1 from public.email_domain_mx m0
                      where m0.domain = split_part(lower(btrim(p.email)), '@', 2) and m0.has_mx = false
                        and m0.kind in ('nxdomain', 'no_records'))
     and not coalesce(lower(btrim(p.email)) ~ any (array(select bp.pattern from public.email_block_pattern bp
                                                         where bp.active and bp.pattern is not null)), false)
     -- a measured MX
     and exists (select 1 from public.email_domain_mx m
                  where m.domain = split_part(lower(btrim(p.email)), '@', 2) and m.kind = 'mx')
     and split_part(lower(btrim(p.email)), '@', 1) !~
         '^(careers?|jobs?|hr|recruit(ment|ing)?|cv|webmaster|hostmaster|mailer-daemon|privacy|legal|newsletters?|unsubscribe|donotreply)$'
     and not (split_part(lower(btrim(p.email)), '@', 2) = any (array(select d.domain from public.email_platform_domain d where d.domain is not null))
              and split_part(lower(btrim(p.email)), '@', 2) is distinct from
                  lower(regexp_replace(regexp_replace(btrim(coalesce(nullif(btrim(p.website), ''), p.maps_website, '')),
                                       '^[A-Za-z]+://', ''), '^www\.|[/:?#].*$', '', 'gi')))
$fn$;

revoke execute on function public.fn_supplier_invite_eligible_ids() from public, anon, authenticated;
grant execute on function public.fn_supplier_invite_eligible_ids() to service_role;

-- The invitation link: always English, and it carries its ref (from #1012). No language argument on purpose.
create or replace function public.fn_supplier_invite_link(p_site text, p_token uuid, p_lead_id bigint)
returns text
language sql immutable
set search_path to 'public', 'pg_temp'
as $fn$
  select coalesce(nullif(btrim(p_site), ''), 'https://quotesdone.com') || '/en/portal?t=' || p_token::text
         || '&utm_source=invite&utm_medium=email&utm_campaign=supplier_invite&utm_content=lead-' || p_lead_id::text
$fn$;
revoke execute on function public.fn_supplier_invite_link(text, uuid, bigint) from public, anon, authenticated;

create or replace function public.fn_supplier_invite_candidates(p_limit integer)
 RETURNS TABLE(lead_id bigint, to_email text, company_name text, lang text, subject text, body text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_site text; v_target int;
  v_subj text; v_body text;
begin
  select coalesce(nullif(btrim(value), ''), 'https://quotesdone.com') into v_site from app_secrets where key = 'public_site_url';
  v_site := coalesce(v_site, 'https://quotesdone.com');
  select value into v_subj    from app_secrets where key = 'invite_subject';
  select value into v_body    from app_secrets where key = 'invite_body';
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
  -- ONE COMPANY, ONE INVITATION (24 Sep 2026, marketing). A company is its email domain, unless the domain is
  -- a shared mailbox provider (gmail, emirates.net.ae ...: measured as a domain carrying 3+ different company
  -- names), where it is the address itself; and, independently, its normalised company name.
  shared as materialized (
    select split_part(lower(btrim(l.email)), '@', 2) as dom from leads l where coalesce(btrim(l.email), '') <> ''
    group by 1 having count(distinct lower(regexp_replace(coalesce(l.company_name, ''), '[^[:alnum:]]', '', 'g'))) >= 3
  ),
  keyed as materialized (
    select l.id,
           case when s.dom is null then split_part(lower(btrim(l.email)), '@', 2) else lower(btrim(l.email)) end as dkey,
           nullif(lower(regexp_replace(coalesce(l.company_name, ''), '[^[:alnum:]]', '', 'g')), '') as nkey,
           (l.invite_status is not null or l.invited_at is not null or coalesce(l.claimed, false)) as touched
    from leads l left join shared s on s.dom = split_part(lower(btrim(l.email)), '@', 2)
    where coalesce(btrim(l.email), '') <> ''
  ),
  touched_d as materialized (select distinct dkey from keyed where touched),
  touched_n as materialized (select distinct nkey from keyed where touched and nkey is not null),
  cand as (
    select distinct on (lower(l.email)) l.id, l.email, l.company_name, l.claim_token, l.email_domain, l.email_verified,
           l.invite_trades, l.emirate, k.dkey, k.nkey,
           -- ALWAYS ENGLISH (24 Sep 2026, ledger 993 item 4: "invitations always in English"). Until this file
           -- a lead with an Arabic locale or an Arabic company name was given invite_body_ar: 116 of 6,863
           -- eligible leads on 24 Sep 2026.
           'en'::text as lang
    from leads l join keyed k on k.id = l.id
    where l.id in (select e.id from public.fn_supplier_invite_eligible_ids() e(id))   -- the set, read once (see header)
      -- a company already invited (bounced, unsubscribed or registered included) is not invited again at another address
      and not exists (select 1 from touched_d t where t.dkey = k.dkey)
      and (k.nkey is null or not exists (select 1 from touched_n t where t.nkey = k.nkey))
    order by lower(l.email), l.id
  ),
  prio as (
    select c.id, c.email, c.company_name, c.claim_token, c.email_domain, c.lang, c.dkey, c.nkey,
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
        row_number() over (partition by coalesce(p.email_domain, split_part(p.email,'@',2)) order by p.unverified_rank, p.role_rank, p.id) as domain_rk,
        -- the best contact per company: a verified, named mailbox before info@/sales@ (a role address goes only
        -- when it is the company's only one). ponytail: a lead that wins one key and loses the other waits a day.
        row_number() over (partition by p.dkey order by p.unverified_rank, p.role_rank, p.id) as company_rk,
        row_number() over (partition by coalesce(p.nkey, p.email) order by p.unverified_rank, p.role_rank, p.id) as name_rk
      from prio p
    ) r
    where r.domain_rk <= 5 and r.company_rk = 1 and r.name_rk = 1
    order by r.target_rank, r.is_none, r.rk, r.unverified_rank, r.role_rank, r.pdomain
    limit greatest(coalesce(p_limit, 0), 0)
  )
  select e.id, btrim(e.email), e.company_name, e.lang, v_subj,
         replace(replace(v_body, '{{company}}', coalesce(nullif(btrim(e.company_name),''), 'there')),
                 '{{link}}', public.fn_supplier_invite_link(v_site, e.claim_token, e.id))   -- English, with its ref (see header)
  from elig e;
end
$function$;
revoke execute on function public.fn_supplier_invite_candidates(integer) from public, anon, authenticated;

CREATE OR REPLACE FUNCTION public.fn_supplier_campaign_next_list(p_after date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_after date := coalesce(p_after, (now() at time zone 'Asia/Dubai')::date);
  v_day date := v_after + 1; v_skipped jsonb := '[]'::jsonb; v_why text; i int := 0;
  v_cap int; v_pool int; v_n int; v_switch boolean; v_held text; v_rows jsonb;
begin
  loop
    v_why := public.fn_supplier_invites_hold_reason(v_day);
    exit when v_why is null;
    v_skipped := v_skipped || jsonb_build_object('day', v_day, 'why', v_why);
    v_day := v_day + 1; i := i + 1;
    if i > 20 then raise exception 'no supplier sending day within 20 days of %', v_after; end if;
  end loop;
  v_switch := coalesce((select lower(btrim(value)) = 'true' from public.app_secrets where key = 'invite_enabled'), false)
              and public.fn_supplier_outreach_golive();
  v_held := case when not public.fn_supplier_outreach_golive() then 'supplier_outreach_golive is false'
                 when not v_switch then 'invite_enabled is false' end;
  -- the sender's own numbers (enqueue_supplier_invites): cap, eligible pool, planned = least of the two
  v_cap := coalesce((select nullif(value, '')::int from public.app_secrets where key = 'invite_daily_cap'), 10);
  -- fn_invite_ramp runs before the batch on the sending day; with nothing sent in the 3 days before it, it resets
  -- the cap to invite_warmup.base_cap (a cold domain restarts). Show that number, not the stale stored cap.
  -- Scoped to the invitation lane exactly as the ramp is (fn_invite_lane_since; '-infinity' while it is off).
  if coalesce((select max(l.invited_at) from public.leads l where l.invited_at >= public.fn_invite_lane_since() and (public.fn_invite_lane_since() = '-infinity'::timestamptz or public.fn_invite_lane_sent(l.id)) and not coalesce(l.is_demo, false) and not public.fn_is_demo_email(l.email)), '-infinity'::timestamptz) < (v_day::timestamp at time zone 'Asia/Dubai') - interval '3 days' then
    v_cap := coalesce((select (nullif(value, '')::jsonb->>'base_cap')::int from public.app_secrets where key = 'invite_warmup'), 30);
  end if;
  select count(*) into v_pool from public.fn_supplier_invite_eligible_ids();   -- the set, read once (see header)
  v_n := greatest(least(v_cap, v_pool), 0);
  select coalesce(jsonb_agg(jsonb_build_object('n', c.rn, 'lead_id', c.lead_id,
            'company', coalesce(nullif(btrim(c.company_name), ''), '(no company name)'),
            'emirate', coalesce(nullif(btrim(l.emirate), ''), '-'), 'language', c.lang,
            'email', public.fn_mask_email(c.to_email)) order by c.rn), '[]'::jsonb)
    into v_rows
    from (select x.*, row_number() over () rn from public.fn_supplier_invite_candidates(v_n) x) c
    join public.leads l on l.id = c.lead_id;
  return jsonb_build_object('send_day', v_day, 'skipped', v_skipped, 'switch_on', v_switch, 'held_because', v_held,
                            'cap', v_cap, 'pool', v_pool, 'planned', v_n, 'rows', v_rows);
end $function$;
revoke execute on function public.fn_supplier_campaign_next_list(date) from public, anon, authenticated;

-- PROBE. Reads only. It RAISES on any failure, which rolls back this whole file: a set rule that disagrees with
-- the row rule, or an invitation that is not English or has lost its ref, is never left live.
do $probe$
declare v_row int; v_set int; v_diff int; v_n int; v_not_en int; v_bad_link int; v_no_q int;
begin
  select count(*) into v_row from public.leads l where public.fn_supplier_invite_eligible(l);
  select count(*) into v_set from public.fn_supplier_invite_eligible_ids();
  select count(*) into v_diff from (
    (select l.id from public.leads l where public.fn_supplier_invite_eligible(l)
     except select e.id from public.fn_supplier_invite_eligible_ids() e(id))
    union all
    (select e.id from public.fn_supplier_invite_eligible_ids() e(id)
     except select l.id from public.leads l where public.fn_supplier_invite_eligible(l))) d;
  if v_diff <> 0 or v_set = 0 then
    raise exception 'PROBE FAILED: the set rule and the row rule disagree on % lead(s) (row %, set %)', v_diff, v_row, v_set;
  end if;

  select count(*),
         count(*) filter (where c.lang is distinct from 'en'),
         count(*) filter (where coalesce(c.body, '') !~ ('/en/portal[?]t=[0-9a-f-]{36}&utm_source=invite&utm_medium=email'
                                                         || '&utm_campaign=supplier_invite&utm_content=lead-' || c.lead_id || '(\s|$)')
                             or coalesce(c.body, '') ~ '/ar/portal'),
         count(*) filter (where rtrim(coalesce(c.body, '')) not like '%which trades does your company cover?')
    into v_n, v_not_en, v_bad_link, v_no_q
    from public.fn_supplier_invite_candidates(50) c;
  if v_not_en > 0 then raise exception 'PROBE FAILED: % of % candidate(s) are not English', v_not_en, v_n; end if;
  if v_bad_link > 0 then raise exception 'PROBE FAILED: % of % candidate link(s) are not /en/portal with their ref', v_bad_link, v_n; end if;
  if v_no_q > 0 then raise exception 'PROBE FAILED: % of % candidate body(ies) do not end with the question', v_no_q, v_n; end if;
end
$probe$;

select 'PROBE OK: set rule = row rule on ' || (select count(*) from public.fn_supplier_invite_eligible_ids())
       || ' lead(s); every candidate English, /en/portal with its ref, ending with the question' as verdict;
