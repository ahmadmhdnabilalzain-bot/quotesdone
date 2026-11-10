-- Seat: customer_support. Assigned: customer_support (supplier follow-up of #1909, item 1; founder ruling 1608).
--
-- MEASURED on origin/main (production, 10 Nov 2026): a supplier's quotation sent by e-mail never reached his request.
-- resend_inbound treated every attachment from a matched supplier as a profile document and answered "our team will
-- add them to your profile". The code change (resend_inbound/quote_by_email.ts, supplier_api/email_quote.ts) hands a
-- verified supplier's quotation for one of his open requests to supplier_api's internal door 'email_quote', which runs
-- the portal's own extract_quote and submit_quote. resend_inbound presents its own credential, fn.resend_inbound,
-- whose scope was ['ai_gateway', 'email_triage'] (internal_credential id 112, read 10 Nov 2026): fn_internal_auth would
-- refuse that call. This file adds 'supplier_api' to that one credential's scope, and nothing else.
--
-- NOT CHANGED: every other credential; supplier_api's other doors (each checks its own action); the scope's existing
-- entries. Idempotent: adding a name already present changes nothing.
-- prevented by: resend_inbound/quote_by_email_handler.test.ts (the call is made with this credential) and the verdict below.
-- Pending until the release applies it: scripts/sql/pending/resend_inbound_hands_an_emailed_quotation_to_the_supplier_portal.txt

update public.internal_credential
   set scope = (select array_agg(distinct s order by s) from unnest(scope || array['supplier_api']) s)
 where context = 'fn.resend_inbound' and active and not ('supplier_api' = any (scope));

select case
  when not exists (select 1 from public.internal_credential where context = 'fn.resend_inbound' and active)
    then 'PROBE FAILED: no active fn.resend_inbound credential'
  when exists (select 1 from public.internal_credential where context = 'fn.resend_inbound' and active and not ('supplier_api' = any (scope)))
    then 'PROBE FAILED: fn.resend_inbound may still not call supplier_api'
  when exists (select 1 from public.internal_credential where context = 'fn.resend_inbound' and active and not (scope @> array['ai_gateway', 'email_triage']))
    then 'PROBE FAILED: an existing scope entry of fn.resend_inbound was lost'
  else 'PROBE OK' end as verdict;
