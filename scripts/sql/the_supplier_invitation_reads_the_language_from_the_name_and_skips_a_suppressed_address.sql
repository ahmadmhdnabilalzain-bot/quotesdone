-- THE SUPPLIER INVITATION READS THE LANGUAGE FROM THE NAME AND SKIPS A SUPPRESSED ADDRESS
-- (23 Sep 2026, marketing with it_engineer; founder instruction 584 — campaign readiness gate).
--
-- Measured on production before this file:
--   * leads.locale is 'en' on all 22,275 leads: it is the column DEFAULT, not a measurement. 252 leads
--     carry an Arabic-script company name, 150 of them eligible for an invitation, and every one would
--     have received the English copy. The founder's rule is one email per supplier in their own language.
--     A company that writes its own name in Arabic script is now written to in Arabic (the Arabic copy
--     exists and passes every inbox rule: scripts/invitation_inbox_check.mjs, mail-tester 10/10).
--   * fn_supplier_invite_eligible did not read email_suppressions. send_outbox holds a suppressed
--     address at send time, but the row had already been queued and had spent one place in the day's
--     cap. An address on the suppression list (any reason: unsubscribe, bounce, complaint, guardrail)
--     is now never a candidate.
-- Both bodies are the live definitions read back on 23 Sep 2026 with only those two changes.
-- prevented by: scripts/campaign_readiness.mjs (checks 2a/2b run the routine on production).

CREATE OR REPLACE FUNCTION public.fn_supplier_invite_candidates(p_limit integer)
 RETURNS TABLE(lead_id bigint, to_email text, company_name text, lang text, subject text, body text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
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
           -- Arabic only where the lead's own locale says so AND the Arabic copy exists; otherwise
           -- English, which is also what a04 assumes for an unregistered recipient.
           case when (lower(coalesce(l.locale, '')) like 'ar%' or coalesce(l.company_name, '') ~ '[؀-ۿ]') and coalesce(v_body_ar, '') like '%{{link}}%'
                     and coalesce(v_subj_ar, '') <> '' then 'ar' else 'en' end as lang
    from leads l
    where public.fn_supplier_invite_eligible(l)
    order by lower(l.email), l.id
  ),
  prio as (
    select c.id, c.email, c.company_name, c.claim_token, c.email_domain, c.lang,
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
    order by r.is_none, r.rk, r.unverified_rank, r.role_rank, r.pdomain
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
$function$

;

CREATE OR REPLACE FUNCTION public.fn_supplier_invite_eligible(p leads)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
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
     -- never an address on the suppression list, whatever the reason (23 Sep 2026)
     and not exists (select 1 from public.email_suppressions s where lower(btrim(s.email)) = lower(btrim(p.email)))
     and coalesce((public.fn_email_sendable(p.email)->>'ok')::boolean, false)
     -- 22 Sep 2026: a COLD invitation needs a measured MX. An A-record-only domain (361 leads), a lookup
     -- that errored (86) or a domain never asked is a bounce risk on a domain with no history to spend.
     and exists (select 1 from public.email_domain_mx m
                  where m.domain = split_part(lower(btrim(p.email)), '@', 2) and m.kind = 'mx')
     -- ... and never a mailbox whose reader is not the business (44 leads): a recruiter or a lawyer
     -- presses "spam", they do not register.
     and split_part(lower(btrim(p.email)), '@', 1) !~
         '^(careers?|jobs?|hr|recruit(ment|ing)?|cv|webmaster|hostmaster|mailer-daemon|privacy|legal|newsletters?|unsubscribe|donotreply)$'
$function$
;
