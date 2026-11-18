-- ONE-OFF BACKFILL: EVERY REAL LEAD'S STAGE FROM ITS OWN EVIDENCE (sales_engineer, 18 Nov 2026).
-- Run ONCE, after a_leads_stage_follows_its_own_evidence.sql. Real rows only (is_demo false, no demo address). Every value is read
-- from the lead's own row or from a mail he sent us (inbound_messages.lead_id); nothing is inferred.
--   registered     claimed, terms accepted or signed, registration submitted, or approved
--   replied        invited, not registered, and he wrote to us himself (not an automatic reply, a test, spam, a stop or a mail
--                  the reading declined)
--   undeliverable  the invitation bounced, nothing better known
--   contacted      the invitation was sent, nothing better known ('no_response' rows are left as they are)
-- DRY RUN (18 Nov 2026, production, read-only): registered 3 (among them leads 2936), replied 2, undeliverable 16, contacted 123,
-- contacted flag set on 314. The trigger of the file above recomputes 'registered', 'undeliverable', 'contacted' and the flag on the
-- same UPDATE, so the statements below only name what the trigger cannot see: the reply.

-- the applier runs the file as one transaction (no BEGIN/COMMIT of its own): the proof at the end rolls all of it back on failure
-- the replies first, so the trigger keeps them (it never moves 'replied' back)
update public.leads l set lifecycle_stage = 'replied'
 where not coalesce(l.is_demo, false) and not public.fn_is_demo_email(l.email)
   and not (coalesce(l.claimed, false) or l.accepted_terms_at is not null or l.signed_terms_at is not null
            or l.registration_submitted_at is not null or coalesce(l.approval_status, '') = 'approved')
   and (l.invited_at is not null or l.invite_status is not null)
   and coalesce(l.lifecycle_stage, 'not_contacted') in ('not_contacted', 'contacted', 'no_response')
   and exists (select 1 from public.inbound_messages m where m.lead_id = l.id
                  and coalesce(m.ai_category, '') not in ('test_reply', 'spam', 'opt_out', 'no_auto_reply')
                  and not public.fn_inbound_is_auto_reply(m.subject, m.body, m.raw));
-- everything else: the trigger derives it from the row (UPDATE OF lifecycle_stage fires it); only rows whose result differs
update public.leads l set lifecycle_stage = coalesce(l.lifecycle_stage, 'not_contacted')
 where not coalesce(l.is_demo, false) and not public.fn_is_demo_email(l.email)
   and ((coalesce(l.claimed, false) or l.accepted_terms_at is not null or l.signed_terms_at is not null
         or l.registration_submitted_at is not null or coalesce(l.approval_status, '') = 'approved') and l.lifecycle_stage is distinct from 'registered'
     or coalesce(l.invite_status, '') in ('sent', 'bounced', 'complained') and (not coalesce(l.contacted, false)
         or coalesce(l.lifecycle_stage, 'not_contacted') = 'not_contacted'));
-- the proof, in the same transaction: Shine Carpets reads 'registered' and contacted; no sent invitation reads 'not_contacted'
do $chk$
begin
  if (select lifecycle_stage from public.leads where id = 2936) is distinct from 'registered'
     or not (select coalesce(contacted, false) from public.leads where id = 2936) then
    raise exception 'BACKFILL FAILED: leads 2936 is not registered and contacted';
  end if;
  if exists (select 1 from public.leads where not coalesce(is_demo, false) and invite_status = 'sent' and coalesce(lifecycle_stage, 'not_contacted') = 'not_contacted') then
    raise exception 'BACKFILL FAILED: a sent invitation still reads not_contacted';
  end if;
end $chk$;
