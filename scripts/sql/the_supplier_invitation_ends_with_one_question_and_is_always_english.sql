-- THE SUPPLIER INVITATION ENDS WITH ONE QUESTION A SUPPLIER CAN ANSWER BY REPLYING, AND IS ALWAYS ENGLISH
-- (24 Sep 2026, marketing seat - it owns the invitation. Ledger 993.)
--
-- MEASURED, 24 Sep 2026, production, read-only:
--   1. app_secrets.invite_body ends "... use the unsubscribe link at the foot of this email and we will not
--      write again.\n\nWe look forward to welcoming you." Nothing in it asks the supplier anything, so the
--      only answer was a click or silence. A one-line reply is the smallest step a supplier can take.
--   2. The reply reaches a mailbox the company reads. Reply-To = app_secrets.email_reply_supplier =
--      suppliers@mail.quotesdone.com; mail.quotesdone.com is Resend inbound and resend_inbound received 34
--      messages there in the last 30 days (expenses@, info@, calendar+). A plain reply takes resend_inbound's
--      general path into inbound_messages (lead matched by sender), and trg_inbound_supplier_reply (enabled)
--      sets needs_review, so it shows in the OS inbox (fn_inbox_list). No real invitation has gone out since
--      that Reply-To was set (22 Sep), so no supplier reply has arrived there yet: 0 rows.
--   3. Ledger 993 item 4 says "invitations always in English", and the 24 Sep header of
--      the_supplier_mail_names_al_furjan_and_no_licence_number.sql says "no Arabic invitation is sent". The
--      live fn_supplier_invite_candidates still chose invite_body_ar for a lead with an Arabic locale or an
--      Arabic company name: 116 of the 6,863 leads it would return today were 'ar'.
--
-- WHAT THIS CHANGES
--   * app_secrets.invite_body: after the closing line, a last paragraph that is one question - the same
--     sentence as INVITE_REPLY_QUESTION in supabase/functions/send_outbox/invitation_copy.ts, which also
--     appends it at send time to any English invitation whose stored body does not end with a question.
--     It follows the portal link and precedes the signature and the footer; the unsubscribe line stays last.
--   * fn_supplier_invite_candidates: lang is always 'en', the subject is invite_subject, the body is
--     invite_body and the link is /en/portal. Everything else is the live definition byte for byte
--     (pg_get_functiondef md5 081b241ed8067f3ce4b494f736d03c4e, equal to supabase/schema/full_schema.sql).
--     CREATE OR REPLACE keeps the existing ACL (postgres, service_role); the revoke is restated anyway.
--
-- WHAT IT DOES NOT CHANGE: invite_subject, invite_preheader, the frame (templates.email_supplier), the From or
-- the Reply-To, invite_enabled / supplier_outreach_golive, resend_inbound. invite_subject_ar / invite_body_ar
-- stay stored (nothing reads them for the campaign after this; fn_supplier_invite_test_send('ar') still renders
-- them to an @example.invalid fixture, which is suppressed and never reaches Resend). The Arabic copy is not
-- given the question: it is no longer sent.
--
-- ORDER: either half alone is safe. send_outbox deployed first appends the question to the old stored body;
-- this applied first ends the stored body with the question and send_outbox leaves it as it is.
--
-- Prevented by: scripts/checks/the_supplier_invitation_ends_with_one_question_and_is_always_english.test.mjs,
--               supabase/functions/send_outbox/invitation_copy.test.ts, and the verdict row at the end of this file.

do $copy$
declare v_body text; v_q constant text :=
  'Before you register, one quick question you can answer by simply replying to this email: which trades does your company cover?';
begin
  select value into v_body from public.app_secrets where key = 'invite_body';
  if v_body is null then raise exception 'app_secrets.invite_body is missing'; end if;
  if rtrim(v_body) like '%' || v_q then
    null;                                   -- already applied
  elsif rtrim(v_body) like '%We look forward to welcoming you.' then
    update public.app_secrets set value = rtrim(v_body) || chr(10) || chr(10) || v_q where key = 'invite_body';
  else
    raise exception 'invite_body no longer ends with the measured closing line; read it and edit this file rather than guess';
  end if;
end $copy$;

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
    where public.fn_supplier_invite_eligible(l)
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
                 '{{link}}', v_site || '/en/portal?t=' || e.claim_token::text)
  from elig e;
end
$function$;

revoke execute on function public.fn_supplier_invite_candidates(integer) from public, anon, authenticated;

-- VERDICT (a row, never a notice: apply_sql.mjs exits 3 on PROBE FAILED). Reads only; writes nothing.
with s as (
  select (select value from public.app_secrets where key = 'invite_body') as body,
         (select value from public.app_secrets where key = 'invite_subject') as subj,
         (select coalesce(value, '') from public.app_secrets where key = 'invite_preheader') as pre
), last as (
  select s.*, btrim(regexp_replace(rtrim(s.body), '^.*\n[ \t]*\n', '')) as lastp from s
), c as (
  select count(*) filter (where lang <> 'en') as not_en,
         count(*) filter (where position('/en/portal?t=' in body) = 0
                             or rtrim(body) not like '%which trades does your company cover?') as bad_body,
         count(*) as n
    from public.fn_supplier_invite_candidates(50)
)
select case
  when last.lastp not like '%?' or length(last.lastp) - length(replace(last.lastp, '?', '')) <> 1
    then 'PROBE FAILED: invite_body does not end with one question'
  when (last.subj || ' ' || last.body || ' ' || last.pre) ~* '\mAI\M'
    then 'PROBE FAILED: the invitation copy says AI'
  when (last.subj || last.body || last.pre) ~ '[؀-ۿ]'
    then 'PROBE FAILED: Arabic script in the English invitation copy'
  when c.not_en > 0 then 'PROBE FAILED: fn_supplier_invite_candidates still returns a non-English invitation'
  when c.bad_body > 0 then 'PROBE FAILED: a candidate body has no /en/ link or does not end with the question'
  else 'PROBE OK' end as verdict
from last, c;
