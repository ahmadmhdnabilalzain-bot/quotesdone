-- A COMPANY REGISTERED BY A COLLEAGUE IS NOT NUDGED AT ITS INVITED ADDRESS, AND NO DOMAIN IS NUDGED TWICE.
-- Seat: customer_support (supplier registration and its outreach; the nudge duty is the sales_engineer's, its delivery is
-- customer_support's). First written 28 Oct 2026 (sales_engineer; founder ledger 1401, the supplier-journey audit, browser half,
-- scenario S7) and never applied; REWRITTEN 10 Nov 2026 (customer_support) as item 8 of #1901's report, founder ruling 1608.
--
-- MEASURED on production, 28 Oct 2026, run b4e8a7fe, ZZ DEMO only, 390 px: an invited lead (unclaimed, never clicked) and a
-- colleague of the same company who signs up on quotesdone.com with HIS OWN address. create_company inserted a second lead,
-- claimed by the colleague (lead 151797 beside the invited 151781). Linking by name alone is not safe (anyone could type a
-- competitor's name), so the second row stays. What is wrong is what happens next: the invited row stays unclaimed and
-- unclicked, so fn_supplier_invite_nudges_due nudges the company on day 3, 7 and 14 to register, after it has registered.
-- Read again 10 Nov 2026 (read-only): 20,300 leads, 2 claimed; of the unclaimed, 25 carry a licence number, 19,438 an emirate.
--
-- WHAT THIS CHANGES (the 28 Oct draft matched the registration name key ALONE; the founder's brief of 10 Nov asks for the
-- licence number first, then the name in the same emirate, and to be conservative):
--   * fn_supplier_company_registered_by_another(lead, address): true when ANOTHER, CLAIMED lead is the same company by
--       1. the trade licence number, by the key leads_claimed_trade_licence_uidx enforces (fn_trade_licence_key), or
--       2. the registration name key leads_claimed_company_name_uidx enforces AND the same emirate, both known, or
--       3. the same corporate mail domain (fn_email_domain_class 'company'; a free or disposable domain never matches).
--     A name match in another or an unknown emirate is NOT enough: that may be a different company, so it keeps its nudge.
--   * fn_supplier_outreach_reachable (the gate of the nudges, the registration reminders and their send) refuses such a lead.
--   * fn_supplier_invite_nudges_due: a corporate domain is nudged once per run, and not while another lead at that domain was
--     nudged in the last 21 days ("when unsure keep nudging, but never twice to the same domain"). The live body read on
--     10 Nov (md5 89ab54f8...), only the last select wrapped. fn_supplier_outreach_reachable: live body md5 f50a25dc..., one test added.
-- A claimed lead is never its own twin (t.id <> p.id). WHAT IT DOES NOT CHANGE: the FIRST invitation
-- (fn_supplier_invite_eligible: the set form reads ~20,000 uninvited leads and the name key over them cost ~2.5 s on 28 Oct);
-- create_company (the colleague's row stays; a merge belongs to a person); and a name-only twin in another emirate, whose own
-- claim the unique name index still refuses (reported, not fixed here).
-- Prevented by scripts/checks/a_company_registered_by_a_colleague_is_not_nudged_at_its_invited_address.test.mjs and the probe
-- file of the same name (rolled back on production).

create or replace function public.fn_supplier_company_registered_by_another(p public.leads, p_to text default null)
returns boolean
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $fn$
  -- 1. the licence number (leads_claimed_trade_licence_uidx answers the lookup)
  select (public.fn_trade_licence_key(p.trade_license_no) is not null
          and exists (select 1 from public.leads t
                       where t.claimed and t.id <> p.id
                         and public.fn_trade_licence_key(t.trade_license_no) = public.fn_trade_licence_key(p.trade_license_no)))
  -- 2. the registration name key in the same, known emirate (leads_claimed_company_name_uidx answers the lookup)
      or (public.fn_company_registration_name_key(p.company_name) is not null
          and nullif(lower(btrim(coalesce(p.emirate, ''))), '') is not null
          and exists (select 1 from public.leads t
                       where t.claimed and t.id <> p.id
                         and public.fn_company_registration_name_key(t.company_name) = public.fn_company_registration_name_key(p.company_name)
                         and lower(btrim(coalesce(t.emirate, ''))) = lower(btrim(p.emirate))))
  -- 3. the same corporate mail domain as a registered company's account or listing address
      or (public.fn_email_domain_class(coalesce(nullif(btrim(p_to), ''), p.email)) = 'company'
          and exists (select 1 from public.leads t
                       where t.claimed and t.id <> p.id
                         and lower(split_part(coalesce(nullif(btrim(t.claimed_by), ''), t.email, ''), '@', 2))
                             = lower(split_part(coalesce(nullif(btrim(p_to), ''), p.email), '@', 2))))
$fn$;
revoke execute on function public.fn_supplier_company_registered_by_another(public.leads, text) from public, anon, authenticated;

CREATE OR REPLACE FUNCTION public.fn_supplier_outreach_reachable(p leads, p_to text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select coalesce(btrim(p_to), '') <> ''
     and coalesce(p.is_demo, false) = false
     and coalesce(p.company_name, '') !~* '^\s*zz\s*demo'
     and not public.fn_is_demo_email(p_to)
     and not public.fn_is_demo_email(p.email)
     and coalesce(p.banned, false) = false
     and coalesce(p.permanently_closed, false) = false
     and coalesce(p.invite_status, '') <> 'bounced'
     and not exists (select 1 from public.sanctions_ban b where b.lead_id = p.id)
     and not exists (select 1 from public.supplier_screening_hit h where h.lead_id = p.id and h.status in ('open', 'confirmed'))
     and coalesce((public.fn_email_sendable(p_to)->>'ok')::boolean, false)
     -- 10 Nov 2026: the company is already registered under another account (by its licence number, its name in the same
     -- emirate, or its corporate mail domain): asking it to register again is asking twice
     and not public.fn_supplier_company_registered_by_another(p, p_to)
$function$;


CREATE OR REPLACE FUNCTION public.fn_supplier_invite_nudges_due(p_now timestamp with time zone DEFAULT now(), p_include_fixtures boolean DEFAULT false)
 RETURNS TABLE(lead_id bigint, step integer, to_email text, lang text, dedupe_key text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  with inv as (   -- the invitation as the OUTBOX recorded it, one per lead
    select n.lead_id, min(coalesce(n.sent_at, n.created_at)) as sent_at
      from public.notifications n
     where n.type = 'supplier_invite' and n.lead_id is not null
       and (n.status = 'sent' or n.sent_at is not null)
     group by n.lead_id
  ), c as (
    -- ALWAYS ENGLISH (review, 29 Sep 2026; founder rule: suppliers are always English, ledger 993). The column
    -- stays so the signature does not change; send_outbox would hold an Arabic row of this type anyway.
    select l.id, lower(btrim(l.email)) as to_email, 'en'::text as lang,
           l as lead, i.sent_at,
           case when p_now >= i.sent_at + interval '14 days' then 3
                when p_now >= i.sent_at + interval '7 days'  then 2
                when p_now >= i.sent_at + interval '3 days'  then 1 end as step
      from inv i join public.leads l on l.id = i.lead_id
     where l.invite_clicked_at is null and not coalesce(l.claimed, false) and l.approval_status is null
       and l.registration_submitted_at is null
       and p_now < i.sent_at + interval '21 days'
  )
  , due as (
  select c.id, c.step, c.to_email, c.lang, 'supplier_invite_nudge:' || c.id || ':' || c.step as dedupe_key,
         -- NEVER TWICE TO THE SAME DOMAIN (10 Nov 2026): a corporate domain is one company. One nudge per domain per run,
         -- and none while another lead at that domain was nudged in the last 21 days (the length of the series).
         -- (example.invalid is the shared fixture domain: many ZZ DEMO companies, never one)
         case when public.fn_email_domain_class(c.to_email) = 'company' and split_part(c.to_email, '@', 2) <> 'example.invalid'
              then split_part(c.to_email, '@', 2) end as company_domain
    from c
   where c.step is not null
     and coalesce((c.lead).invite_status, '') not in ('bounced', 'complained', 'unsubscribed')
     and not exists (select 1 from public.email_suppressions s where lower(s.email) = c.to_email)
     and case when p_include_fixtures
              -- the test path can only ever see a fixture: both marks, asserted, never assumed
              then (c.lead).company_name like 'ZZ DEMO%' and c.to_email like '%@example.invalid'
              else public.fn_supplier_outreach_reachable(c.lead, c.to_email) end
     -- A SUPPLIER WHO ANSWERED IS NOT ASKED AGAIN (28 Oct 2026): any message of its own since the invitation was sent,
     -- an automatic reply excepted. The address is read out of a "Name <address>" From exactly as
     -- fn_marketing_files_invite_reply reads it.
     and not exists (select 1 from public.inbound_messages m
                      where (m.lead_id = c.id
                             or lower(substring(coalesce(m.from_email, '') from '([^<>[:space:]"]+@[^<>[:space:]"]+)')) = c.to_email)
                        and m.created_at >= c.sent_at
                        and not public.fn_inbound_is_auto_reply(m.subject, m.body, m.raw))
     and not exists (select 1 from public.agent_actions a
                      where a.kind = 'handoff' and a.agent = 'customer_support'
                        and a.target_id = 'delivery.request:supplier_invite_nudge:' || c.id || ':' || c.step)
  ), ranked as (
  select d.*, row_number() over (partition by coalesce(d.company_domain, d.to_email) order by d.id) as nth
    from due d
   where d.company_domain is null
      or not exists (select 1 from public.notifications n
                      where n.type = 'supplier_invite_nudge' and n.lead_id is distinct from d.id
                        and n.created_at >= p_now - interval '21 days'
                        and coalesce(n.status, '') not in ('failed', 'cancelled')
                        and lower(split_part(coalesce(n.to_email, ''), '@', 2)) = d.company_domain)
  )
  select x.id, x.step, x.to_email, x.lang, x.dedupe_key from ranked x where x.nth = 1
   order by x.id
$function$;

