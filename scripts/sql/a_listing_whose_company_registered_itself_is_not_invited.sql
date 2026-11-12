-- A LISTING WHOSE COMPANY REGISTERED ITSELF IS NOT INVITED (12 Nov 2026, sales_engineer; founder ruling 1645, browser perfection walk
-- of supplier registration, finding H10, and its review).
-- supplier_api create_company never takes a directory listing by its name (the review proved a name, an emirate and any mailbox
-- would hand a real company's listing to whoever typed them): a registration of a listed company is its own new row, and the
-- listing is flagged to it_engineer to merge by hand. Until a person merges it the listing would stay in the daily invitation
-- pool, and the campaign would invite a company that has already registered. fn_supplier_invite_candidates now skips a listing
-- whose fn_company_registration_name_key equals that of a claimed, non-demo company.
-- ONLY REMOVES CANDIDATES: no switch, cap, schedule, template or order changes. The body below is the LIVE definition read from
-- production on 12 Nov 2026 (pg_get_functiondef), with one added line in the cand CTE.
-- MEASURED on production 12 Nov 2026 before this file: 2,607 candidates (limit 100000, every provider); 1 claimed non-demo company;
-- 0 candidates share its name key, so today it removes 0. It matters from Monday, when every listed company that registers leaves a
-- listing behind.
-- COST, measured by the review on production 12 Nov 2026 (rolled-back rehearsals): the live routine already takes 9.3 to 11.2 s; with
-- the rule 13.2 s (the helper 0.60 ms per listing: leads_claimed_company_name_uidx serves the inner probe, the name key is computed per
-- listing). Its callers are 60 s pg_cron jobs that read it once per run, so it fits; it is not optimised here.
-- One overload of fn_supplier_invite_candidates exists, (integer, text[]); CREATE OR REPLACE keeps its grants (postgres, service_role).
-- The helper is new: CREATE grants EXECUTE to PUBLIC, so it is revoked; it is called only from the SECURITY DEFINER candidates
-- routine (owner postgres). Read through leads_claimed_company_name_uidx (on the key, WHERE claimed).
-- Probe: a_listing_whose_company_registered_itself_is_not_invited_probe.sql.

CREATE OR REPLACE FUNCTION public.fn_supplier_listing_has_registered_twin(p_lead_id bigint, p_company_name text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select public.fn_company_registration_name_key(p_company_name) is not null
     and exists (select 1 from public.leads o
                  where o.claimed and o.id is distinct from p_lead_id and not coalesce(o.is_demo, false)
                    and public.fn_company_registration_name_key(o.company_name) = public.fn_company_registration_name_key(p_company_name))
$function$;
revoke execute on function public.fn_supplier_listing_has_registered_twin(bigint, text) from public, anon, authenticated;

CREATE OR REPLACE FUNCTION public.fn_supplier_invite_candidates(p_limit integer, p_providers text[])
 RETURNS TABLE(lead_id bigint, to_email text, company_name text, lang text, subject text, body text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_site text; v_target int;
  v_reach boolean := coalesce((select value from app_secrets where key = 'invite_reachable_only'), '') = 'true';
  v_subj text; v_body text;
begin
  select coalesce(nullif(btrim(value), ''), 'https://quotesdone.com') into v_site from app_secrets where key = 'public_site_url';
  v_site := coalesce(v_site, 'https://quotesdone.com');
  select value into v_subj    from app_secrets where key = 'invite_subject';
  select value into v_body    from app_secrets where key = 'invite_body';
  -- 27 Oct 2026: the founder's invitation carries no link ("safer to not send links"); a supplier registers at
  -- quotesdone.com or replies. Only an EMPTY template is refused now. A template that still has {{link}} is filled.
  if coalesce(v_body, '') ~ '^[[:space:]]*$' then
    raise exception 'app_secrets.invite_body is empty: no invitation is built from nothing';
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
  -- instr 1013: marketing's ranking of the trades below ten suppliers (the ranking orders the queue; since 27 Oct 2026
  -- every row stores the one approved text, not a per-trade variant)
  plans as materialized (select p.trade, p.emirate, p.rank from public.marketing_gap_recruitment_plan p),
  -- 29 Sep 2026 (ledger 1018): the trades and areas of the open, real stalled-request rescues (public.stalled_inquiry_rescue).
  -- A fixture rescue never moves the real queue.
  rescue as materialized (select x.trades, x.emirate from public.stalled_inquiry_rescue x where x.cleared_at is null and not x.fixture and cardinality(x.trades) > 0),
  cand as (
    select distinct on (lower(l.email)) l.id, l.email, l.company_name, l.claim_token, l.email_domain, l.email_verified,
           l.invite_trades, l.emirate, k.dkey, k.nkey, ec.mailbox,
           -- ALWAYS ENGLISH (24 Sep 2026, ledger 993 item 4; #1065): suppliers are always written in English.
           'en'::text as lang
    from leads l join keyed k on k.id = l.id left join public.lead_email_check ec on ec.lead_id = l.id
    where l.id in (select e.id from public.fn_supplier_invite_eligible_ids() e(id))   -- the set, read once (see header)
      -- 27 Oct 2026 (it_engineer): only recipients whose mailbox class passed the GlockApps verdict; null = every class
      and (p_providers is null or public.fn_mail_provider_of_email(l.email) = any(p_providers))
      -- 2 Nov 2026 (ceo, ledger 1438, 1449): the CEO's reachability lever; unchecked addresses wait while it is on
      and (not v_reach or l.email_verified in ('verified', 'true', 'maps', 'social'))
      -- a company already invited (bounced, unsubscribed or registered included) is not invited again at another address
      and not exists (select 1 from touched_d t where t.dkey = k.dkey)
      and (k.nkey is null or not exists (select 1 from touched_n t where t.nkey = k.nkey))
      -- 12 Nov 2026 (customer_support, ruling 1645, walk finding H10): a listing whose company registered itself under the same
      -- legal name key (fn_company_registration_name_key, the key leads_claimed_company_name_uidx uses) is not invited. The alnum
      -- key above misses "&"/"and", "Establishment"/"Est" and Arabic letter variants. Only ever removes candidates.
      and not public.fn_supplier_listing_has_registered_twin(l.id, l.company_name)
    order by lower(l.email), l.id
  ),
  prio as (
    select c.id, c.email, c.company_name, c.claim_token, c.email_domain, c.lang, c.dkey, c.nkey,
      -- 29 Sep 2026 (ledger 1018): ahead of every tier below, a lead in the trade and area of a stalled request a customer waits on.
      -- 23 Sep 2026: a lead in a trade the sales engineer marked for recruitment (supply_gap 'recruit') goes first;
      -- 29 Sep 2026 (instr 1013): then a lead in any trade marketing planned, by the plan's rank.
      case when exists (select 1 from rescue x where x.trades && coalesce(c.invite_trades, '{}'::text[])
                          and (x.emirate is null or x.emirate = 'UAE' or x.emirate = c.emirate)) then -1
           when exists (select 1 from public.supply_gap g where g.status = 'recruit' and g.trade = any(coalesce(c.invite_trades, '{}'::text[]))
                          and (g.emirate = 'UAE' or g.emirate = c.emirate)) then 0
           when pl.rank is not null then 1 else 2 end as target_rank,
      -- 2 Nov 2026 (ceo): a trade the CEO put first leads inside its tier; a stalled request's rescue still comes before it
      case when exists (select 1 from public.ceo_invite_trade_priority t where t.cleared_at is null and t.trade = any(coalesce(c.invite_trades, '{}'::text[])))
           then -1 else coalesce(pl.rank, 2147483647) end as plan_rank,
      coalesce((select u.domain_slug from lead_subcategory ls join under u on u.domain_slug = ls.domain_slug
                 where ls.lead_id = c.id order by u.have asc, ls.score desc limit 1), '~none') as pdomain,
      -- THE LIKELIEST MAILBOX FIRST (2 Nov 2026, ledger 1449). Measured on the 52 real sends: proven 'verified' 1 bounce of 22,
      -- proven 'true' 1 of 9, unproven role address 0 of 2, unproven named address 5 of 16. So an unproven info@ goes before
      -- an unproven named address (this used to be the other way round), and free mail last. ponytail: small sample, re-read at 200.
      case when c.email_verified in ('verified','true') then 0 when c.mailbox = 'free' then 3 when c.mailbox = 'role' then 1 else 2 end as mailbox_rank
    from cand c
    left join lateral (select p.rank from plans p
                        where p.trade = any(coalesce(c.invite_trades, '{}'::text[])) and (p.emirate = 'UAE' or p.emirate = c.emirate)
                        order by p.rank limit 1) pl on true
  ),
  elig as (
    select r.id, r.email, r.company_name, r.claim_token, r.lang from (
      select p.*,
        case when p.pdomain='~none' then 1 else 0 end as is_none,
        row_number() over (partition by p.pdomain order by p.mailbox_rank, p.id) as rk,
        row_number() over (partition by coalesce(p.email_domain, split_part(p.email,'@',2)) order by p.mailbox_rank, p.id) as domain_rk,
        -- the best contact per company, by mailbox_rank. ponytail: a lead that wins one key and loses the other waits a day.
        row_number() over (partition by p.dkey order by p.mailbox_rank, p.id) as company_rk,
        row_number() over (partition by coalesce(p.nkey, p.email) order by p.mailbox_rank, p.id) as name_rk
      from prio p
    ) r
    where r.domain_rk <= 5 and r.company_rk = 1 and r.name_rk = 1
    order by r.target_rank, r.plan_rank, r.mailbox_rank, r.is_none, r.rk, r.pdomain
    limit greatest(coalesce(p_limit, 0), 0)
  )
  select e.id, btrim(e.email), e.company_name, e.lang, v_subj,
         -- an Arabic-script company name is not written into an English letter (the 29 Sep probe found 11 of 200);
         -- with no usable name the greeting is the neutral "Hello," the Microsoft 365 lane also sends
         -- (a template that still carries {{link}} is filled as before; the approved one has none)
         replace(replace(case when n.nm = '' then replace(v_body, 'Hi {{company}} team,', 'Hello,') else v_body end,
                         '{{company}}', case when n.nm = '' then 'there' else n.nm end),
                 '{{link}}', public.fn_supplier_invite_link(v_site, e.claim_token, e.id))
  from elig e
  cross join lateral (select coalesce(nullif(btrim(case when e.company_name ~ '[؀-ۿ]' then '' else e.company_name end), ''), '') as nm) n;
end
$function$;
