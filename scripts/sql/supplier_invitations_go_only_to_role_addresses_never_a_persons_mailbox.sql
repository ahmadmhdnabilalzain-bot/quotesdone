-- SUPPLIER INVITATIONS GO ONLY TO ROLE ADDRESSES, NEVER A PERSON'S MAILBOX (19 Oct 2026; Assigned: ceo).
-- Founder decision on legal finding 3 (docs/legal/SUPPLIER_CAMPAIGN_LAWFUL_BASIS.md): the campaign relies on
-- UAE PDPL Art. 4, data the business has itself made publicly available. Contacting ONLY role mailboxes (info@,
-- sales@), never ahmed@ or j.smith@, is a cautious policy choice of the CEO seat (19 Oct 2026), NOT a PDPL
-- requirement: a named mailbox the business published could arguably fall under the same ground. Measured cost:
-- 12,577 of 17,401 invitable leads excluded (about 4,824 remain). The rule is ONE function, fn_is_role_address(text),
-- read by the three routines that choose who is mailed:
--   fn_supplier_invite_eligible(leads)   the row rule (canonical: MANIFEST 1757)
--   fn_supplier_invite_eligible_ids()    the set rule the daily list and the 10:00 send read (MANIFEST 1844)
--   fn_supplier_invite_nudges_due(...)   the day-3/7/14 reminders (MANIFEST 1933), so a reminder never reaches
--                                        a personal mailbox invited before this rule existed.
-- Each body below is the canonical one with exactly one added clause. CREATE OR REPLACE keeps each ACL; the
-- revokes are restated on the exact signatures anyway.

create or replace function public.fn_is_role_address(p_email text)
returns boolean
language sql
immutable
set search_path to 'public', 'pg_temp'
as $fn$
  -- the exact role word, then optional digits (sales1), then optional . - _ separated suffixes (info.dubai, sales-ae)
  select coalesce(position('@' in p_email) > 1 and split_part(lower(btrim(p_email)), '@', 1) ~
    '^(info|sales|enquiries|enquiry|inquiries|inquiry|contact|office|admin|hello|mail|support|service|services|projects|tender|tenders|estimation|estimating|procurement|quotes|quotation|quotations|accounts|marketing|business|bd|team|general|reception)[0-9]*([._-][a-z0-9]+)*$', false)
$fn$;
revoke execute on function public.fn_is_role_address(text) from public, anon, authenticated;

create or replace function public.fn_supplier_invite_eligible(p leads)
returns boolean
language sql
stable security definer
set search_path to 'public', 'pg_temp'
as $fn$
  select coalesce(btrim(p.email), '') <> ''
     and p.invite_status is null
     and coalesce(p.source, '') <> 'self_registered'
     and coalesce(p.claimed, false) = false
     and coalesce(p.banned, false) = false
     and coalesce(p.permanently_closed, false) = false
     -- a fixture is never a supplier: the flag, the naming convention, and the reserved domains
     and coalesce(p.is_demo, false) = false
     and coalesce(p.company_name, '') !~* '^\s*zz\s*demo'
     and not public.fn_is_demo_email(p.email)
     -- screened and matched but undecided is not cleared; a confirmed ban is total
     and not exists (select 1 from public.sanctions_ban b where b.lead_id = p.id)
     and not exists (select 1 from public.supplier_screening_hit h
                      where h.lead_id = p.id and h.status in ('open', 'confirmed'))
     -- never twice, read from the outbox rather than from a status column
     and not exists (select 1 from public.notifications n
                      where n.type = 'supplier_invite' and lower(btrim(n.to_email)) = lower(btrim(p.email)))
     -- 19 Oct 2026 (founder, legal finding 3): a ROLE address only (info@, sales@ ...), never a person's mailbox.
     and public.fn_is_role_address(p.email)
     and coalesce((public.fn_email_sendable(p.email)->>'ok')::boolean, false)
     -- 22 Sep 2026: a COLD invitation needs a measured MX. An A-record-only domain (361 leads), a lookup
     -- that errored (86) or a domain never asked is a bounce risk on a domain with no history to spend.
     and exists (select 1 from public.email_domain_mx m
                  where m.domain = split_part(lower(btrim(p.email)), '@', 2) and m.kind = 'mx')
     -- ... and never a mailbox whose reader is not the business (44 leads): a recruiter or a lawyer
     -- presses "spam", they do not register.
     and split_part(lower(btrim(p.email)), '@', 1) !~
         '^(careers?|jobs?|hr|recruit(ment|ing)?|cv|webmaster|hostmaster|mailer-daemon|privacy|legal|newsletters?|unsubscribe|donotreply)$'
     -- 24 Sep 2026 (marketing, ledger 993): never an address on a directory, marketplace, hosting, template or
     -- placeholder domain (public.email_platform_domain, exact domain equality, no word is read) -- the reader is not
     -- the company. The one exception is a platform that IS the lead: its own website host is that domain.
     and not exists (select 1 from public.email_platform_domain d
                      where d.domain = split_part(lower(btrim(p.email)), '@', 2)
                        and d.domain is distinct from lower(regexp_replace(regexp_replace(btrim(coalesce(nullif(btrim(p.website), ''), p.maps_website, '')),
                                                          '^[A-Za-z]+://', ''), '^www\.|[/:?#].*$', '', 'gi')))
$fn$;
revoke execute on function public.fn_supplier_invite_eligible(leads) from public, anon, authenticated;

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
     -- 19 Oct 2026 (founder, legal finding 3): a ROLE address only (info@, sales@ ...), never a person's mailbox.
     and public.fn_is_role_address(p.email)
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

create or replace function public.fn_supplier_invite_nudges_due(p_now timestamptz default now(), p_include_fixtures boolean default false)
returns table (lead_id bigint, step integer, to_email text, lang text, dedupe_key text)
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $fn$
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
           l as lead,
           case when p_now >= i.sent_at + interval '14 days' then 3
                when p_now >= i.sent_at + interval '7 days'  then 2
                when p_now >= i.sent_at + interval '3 days'  then 1 end as step
      from inv i join public.leads l on l.id = i.lead_id
     where l.invite_clicked_at is null and not coalesce(l.claimed, false) and l.approval_status is null
       and l.registration_submitted_at is null
       and p_now < i.sent_at + interval '21 days'
  )
  select c.id, c.step, c.to_email, c.lang, 'supplier_invite_nudge:' || c.id || ':' || c.step
    from c
   where c.step is not null
     and coalesce((c.lead).invite_status, '') not in ('bounced', 'complained', 'unsubscribed')
     and not exists (select 1 from public.email_suppressions s where lower(s.email) = c.to_email)
     and case when p_include_fixtures
              -- the test path can only ever see a fixture: both marks, asserted, never assumed
              then (c.lead).company_name like 'ZZ DEMO%' and c.to_email like '%@example.invalid'
              -- 19 Oct 2026: a reminder goes only to a role address (fn_is_role_address), like the invitation
              else public.fn_supplier_outreach_reachable(c.lead, c.to_email) and public.fn_is_role_address(c.to_email) end
     and not exists (select 1 from public.agent_actions a
                      where a.kind = 'handoff' and a.agent = 'customer_support'
                        and a.target_id = 'delivery.request:supplier_invite_nudge:' || c.id || ':' || c.step)
   order by c.id
$fn$;
revoke execute on function public.fn_supplier_invite_nudges_due(timestamptz, boolean) from public, anon, authenticated;

-- VERDICT (literals only; reads no table)
select case when bad is null then 'PROBE OK' else 'PROBE FAILED: ' || bad end as verdict
from (
  select string_agg(coalesce(e, '<null>') || case when want then ' should be a role address' else ' should be rejected' end, '; ') as bad
  from (values
    ('info@acme.ae', true), ('Sales@Acme.ae', true), ('enquiries@acme.ae', true), ('info.dubai@acme.ae', true),
    ('sales1@acme.ae', true), ('tenders_ae@acme.ae', true), ('bd@acme.ae', true), ('reception@acme.ae', true),
    ('ahmed@acme.ae', false), ('j.smith@acme.ae', false), ('ahmed.k@acme.ae', false), ('infoahmed@acme.ae', false),
    ('john.sales@acme.ae', false), ('careers@acme.ae', false), ('info', false), ('', false), (null, false)
  ) t(e, want)
  where public.fn_is_role_address(e) is distinct from want
) s;
