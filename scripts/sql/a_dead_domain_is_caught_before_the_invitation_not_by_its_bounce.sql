-- A DEAD DOMAIN IS CAUGHT BEFORE THE INVITATION, NOT BY ITS BOUNCE (2 Nov 2026, founder ledger 1449: check addresses before
-- sending, bounces under 3%; no paid checker).
-- Seat: sales_engineer
--
-- MEASURED on production and live DNS, 2 Nov 2026. The 7 bounced invitations of 29-30 Oct were all on domains whose cached
-- answer (email_domain_mx) was Google MX, checked 12 Aug. Today, live:
--   alifitc.ae (5.4.310)      no MX, no A: the domain is gone
--   multi-mech.com (5.4.311)  no MX, A = 127.0.0.1
--   unibetonrm.com (5.4.316)  MX = ghs.google.com only, Google's web-hosting front end, which takes no mail
--   the other four             real Google MX; three were 5.1.1 (no such mailbox) and one "address not found"
-- All 7 addresses are already in email_suppressions and their leads read 'bounced', so none is ever invited again
-- (fn_supplier_invite_eligible requires invite_status null). A DNS check cannot see a missing mailbox; it can see the first three.
-- The pre-send check (sales_engineer/lead_email_check.ts, lead_email_check, enforced at insert by
-- fn_notifications_supplier_invite_is_whole) already exists. Its gaps, closed here and in that file:
--   1. a verdict and the cached domain answer were trusted for 30 days, and these domains died inside 2.5 months: both are
--      asked again after 7 days (this file). The batch takes 200 leads and 40 domains every 5 minutes, about 11,500 lookups a
--      day, against 986 Google-class and some 12,000 other domains a week;
--   2. an MX naming only a host that takes no mail (ghs.google.com, localhost, a bare IP) verified: now rejected
--      (lead_email_check.ts judgeDns), using the hosts this routine now hands over with a cached answer.
-- A rejected verdict cancels a queued invitation for that lead (fn_sales_engineer_records_email_checks, unchanged).
-- Prevented by: supabase/functions/sales_engineer/lead_email_check.test.ts. Probe: this file's _probe.sql.

CREATE OR REPLACE FUNCTION public.fn_sales_engineer_email_check_batch(p_limit integer DEFAULT 200)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select coalesce(jsonb_agg(jsonb_build_object('lead_id', x.id, 'email', x.email, 'email_verified', x.email_verified, 'mx_kind', x.kind,
                                               'mx_hosts', to_jsonb(x.hosts))), '[]'::jsonb)
    from (
      select l.id, btrim(l.email) as email, l.email_verified, m.kind, m.hosts
        from public.leads l
        left join public.lead_email_check c on c.lead_id = l.id
        -- a cached answer younger than the recheck; a cached failure is asked again
        left join public.email_domain_mx m on m.domain = split_part(lower(btrim(l.email)), '@', 2)
                                          and m.checked_at > now() - interval '7 days' and m.kind <> 'error'
       where coalesce(btrim(l.email), '') <> ''
         and coalesce(l.invite_status, 'queued') = 'queued'
         and coalesce(l.source, '') <> 'self_registered'
         and not coalesce(l.claimed, false) and not coalesce(l.banned, false) and not coalesce(l.permanently_closed, false)
         and not coalesce(l.is_demo, false) and not public.fn_is_demo_email(l.email)
         and (c.lead_id is null
              or c.email_md5 <> md5(lower(btrim(l.email)))
              or c.checked_at < now() - interval '7 days'
              or (c.verdict = 'retry' and c.checked_at < now() - interval '1 hour'))
       -- an invitation already waiting in the outbox first, then never-checked, then the oldest verdict
       order by (l.invite_status = 'queued') desc nulls last, (c.lead_id is null) desc, c.checked_at nulls first, l.id
       limit greatest(coalesce(p_limit, 0), 0)
    ) x
$function$;
