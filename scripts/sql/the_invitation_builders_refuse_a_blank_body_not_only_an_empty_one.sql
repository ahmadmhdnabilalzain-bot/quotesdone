-- THE INVITATION BUILDERS REFUSE A BLANK BODY, NOT ONLY AN EMPTY ONE (it_engineer, 28 Oct 2026; ledger 1407; rebuilt from the live bodies 2 Nov 2026).
-- Assigned: it_engineer (the guard of instruction 1301 on the routines marketing's supplier invitation is built by).
--
-- MEASURED 28 Oct 2026 ~08:10Z on production, in one rolled-back transaction, for ledger 1407 ("confirm the canonical
-- fn_supplier_invite_candidates ... still accepts a body with no {{link}} and still refuses an empty one"): the picker
-- takes the founder's link-less copy (3 of 3 rows carry it, no URL, no placeholder left) and refuses
-- app_secrets.invite_body = '', and so does fn_marketing_gap_recruitment_plans. A body of three spaces and a newline
-- was NOT refused. The test is btrim(coalesce(v_body, '')) = '', and btrim() given no characters strips only the space
-- character, so a template of newlines, tabs or carriage returns reads as non-empty: the picker builds an invitation
-- from it and the plan builder stores it in every plan row. Downstream, the a07 trigger on notifications
-- (fn_notifications_supplier_invite_is_whole, #1705) refuses each such row for its missing reply-"stop" line, so no
-- blank mail goes out; the batch stops instead, on an error that names the stop line rather than the blank template.
-- RE-MEASURED 2 Nov 2026 on production: both routines still carry the btrim() form (md5 of their bodies below).
--
-- THIS CHANGES ONE LINE IN EACH BUILDER. The emptiness test becomes coalesce(v_body, '') ~ '^[[:space:]]*$': nothing
-- but whitespace, newlines and tabs included, and NULL read as ''. [[:space:]] is the class the a07 guard already
-- reads its stop line with. The error text is unchanged.
-- NOT CHANGED: every other byte. Each body is the LIVE one of 2 Nov 2026, read with pg_proc.prosrc and equal to the
-- repository's canonical file, with that one line replaced:
--   fn_supplier_invite_candidates(integer, text[])  md5 8f80bdd8c5e1b665496328f84a68b5e2, 9108 bytes
--     (the_ceo_holds_the_supplier_target_and_acts_within_bounded_powers.sql: it carries #1743's reachability lever and the
--      CEO's priority trades, the checked-mailbox rank of an_invitation_goes_only_to_a_checked_mailbox..., and 95eb816f's
--      one-routine change. The first form of this file restated an older body and would have removed all of them.)
--   fn_marketing_gap_recruitment_plans()            md5 60d33345fd5e6080673875f4b9c52b0f, 3845 bytes
-- The one-argument picker is gone (fn_supplier_invite_candidates_is_one_routine.sql dropped it), so it is not restated.
-- CREATE OR REPLACE keeps each routine's closed ACL (no EXECUTE for anon or authenticated), so nothing is granted or revoked.
--
-- Prevented by: scripts/checks/the_supplier_invitation_carries_no_link.test.mjs, which requires every reader of
-- invite_body in the canonical builders to refuse a whitespace-only body by this class and fails on the btrim() form;
-- scripts/checks/the_invitation_pool_set_states_the_row_rule.test.mjs, which holds this file to the applied body plus that one line.

-- ── 1. the picker: the body every invitation is built by ──────────────────────────────────────────────────────────
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

-- ── 2. marketing's plan builder: every plan row stores the one approved text ─────────────────────────────────────
create or replace function public.fn_marketing_gap_recruitment_plans()
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare v_body text := (select value from public.app_secrets where key = 'invite_body');
  v_rows int; v_dropped int;
begin
  -- 27 Oct 2026: the founder approved ONE invitation with no link; each plan row stores it (the trade is filled at
  -- send time by the Microsoft 365 lane). Only an empty template is refused.
  if coalesce(v_body, '') ~ '^[[:space:]]*$' then
    raise exception 'app_secrets.invite_body is empty: no plan is built from nothing';
  end if;

  delete from public.marketing_gap_recruitment_plan p
   where not exists (select 1 from public.supply_gap g where g.trade = p.trade and g.emirate = p.emirate
                       and g.closed_at is null and g.status <> 'closed' and g.matchable < g.target);
  get diagnostics v_dropped = row_count;

  with gaps as (
    select g.*, coalesce(t.label, g.trade) as label, t.group_code,
           row_number() over (order by (g.target - g.matchable) desc, g.demand_90d desc, g.uninvited_pool desc, g.trade, g.emirate) as rk
      from public.supply_gap g left join public.taxonomy_trade t on t.code = g.trade
     where g.closed_at is null and g.status <> 'closed' and g.matchable < g.target
  )
  insert into public.marketing_gap_recruitment_plan as p
    (trade, emirate, rank, matchable, target, gap, demand_90d, uninvited_pool, gap_status, sources, invite_subject, invite_body, built_at)
  select x.trade, x.emirate, x.rk, x.matchable, x.target, x.target - x.matchable, x.demand_90d, x.uninvited_pool, x.status,
         coalesce((select jsonb_agg(jsonb_build_object('kind', s.kind, 'name', s.name, 'url', s.url, 'scope', s.scope,
                                                       'http_status', s.http_status, 'verified', s.verified, 'checked_at', s.checked_at)
                                    order by (s.scope = x.trade) desc, (s.scope = x.group_code) desc, s.verified desc, s.kind, s.name)
                     from public.marketing_recruitment_source s
                    where s.scope in ('all', x.trade, coalesce(x.group_code, '-'))), '[]'::jsonb),
         initcap(x.label) || ' quote requests',
         v_body,
         now()
    from gaps x
  on conflict (trade, emirate) do update set rank = excluded.rank, matchable = excluded.matchable, target = excluded.target,
    gap = excluded.gap, demand_90d = excluded.demand_90d, uninvited_pool = excluded.uninvited_pool, gap_status = excluded.gap_status,
    sources = excluded.sources, invite_subject = excluded.invite_subject, invite_body = excluded.invite_body, built_at = excluded.built_at;
  get diagnostics v_rows = row_count;

  -- a planned trade with no checked source is marketing's own finding (where to look is the gap, not the invitation)
  perform public.fn_it_engineer_finding_upsert('recruitment:no_source:' || p.trade,
      'No checked recruitment source is recorded for ' || p.trade, 'public.marketing_recruitment_source', 'monitor', 1,
      jsonb_build_object('trade', p.trade, 'owner_seat', 'marketing'), '{}'::text[],
      array['a directory, association, chamber, LinkedIn group or trade fair where this trade gathers'], 'marketing')
    from (select distinct trade from public.marketing_gap_recruitment_plan
           where not exists (select 1 from jsonb_array_elements(sources) e where (e->>'verified')::boolean)) p;
  update public.it_engineer_finding f set closed_at = now(), close_note = 'a checked source is recorded'
   where f.issue_key like 'recruitment:no_source:%' and f.closed_at is null
     and not exists (select 1 from public.marketing_gap_recruitment_plan p where 'recruitment:no_source:' || p.trade = f.issue_key
                       and not exists (select 1 from jsonb_array_elements(p.sources) e where (e->>'verified')::boolean));

  return public.fn_marketing_gap_recruitment_report() || jsonb_build_object('plans_written', v_rows, 'plans_dropped', v_dropped);
end $fn$;

-- ── PROBE (a verdict row; it reads definitions and writes nothing) ─────────────────────────────────────────────────
select case
  when pg_get_functiondef('public.fn_supplier_invite_candidates(integer,text[])'::regprocedure)
       not like '%if coalesce(v_body, '''') ~ ''^[[:space:]]*$'' then%'
    then 'PROBE FAILED: the picker does not refuse a whitespace-only body'
  when pg_get_functiondef('public.fn_marketing_gap_recruitment_plans()'::regprocedure)
       not like '%if coalesce(v_body, '''') ~ ''^[[:space:]]*$'' then%'
    then 'PROBE FAILED: the plan builder does not refuse a whitespace-only body'
  else 'PROBE OK' end as verdict;
