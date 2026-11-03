-- A SUPPLIER'S REPLY NAMES CONFIRMING THE SERVICES AND IS SIGNED.
-- Seat: sales_engineer. 2 Nov 2026, founder ledger 1469 (a supplier is verified only after it confirms its services).
--
-- MEASURED 2 Nov 2026 (production, read-only): public.fn_supplier_reply_answer is byte for byte the body in
-- a_supplier_reply_gets_the_action_it_asked_for.sql (pg_get_functiondef read through the database; IMMUTABLE, not
-- security definer, ACL postgres + service_role). The text that went to a supplier asking to register a
-- separately licensed company was:
--   "It needs its licensed name, a UAE mobile number verified with a code, the verified work e-mail, the trade licence,
--    the company profile and acceptance of the supplier terms."
-- It lists the six and stops. Under ledger 1469 a company with all six and a licence in date is still held
-- (pending / services_unconfirmed) until its supplier confirms the services it provides in the Services tab, so a reply that
-- lists requirements without that step sends the supplier to a registration that does not finish. And none of the three
-- answers ends with a signature: the other replies end "Kind regards, The QuotesDone Team" (composeMailReply,
-- supabase/functions/_shared/customer_mail.ts), and fn_inbox_send adds nothing, so these went out unsigned.
--
-- CHANGED: the 'subsidiary' and the default ('interested') answers name confirming the services, as the step after the six, with
-- what happens until then (held) and after (verified); all three answers (and 'later') end with the QuotesDone sign-off.
-- English only: suppliers are always written to in English (founder, 28 Sep 2026). Nothing else in the three answers moves.
-- The reminders and follow-up bodies in a_supplier_reply_gets_the_action_it_asked_for.sql list no requirements (they link to the
-- portal, which names what is left), so the services omission does not apply to them; their sign-off is reported separately.
-- CREATE OR REPLACE keeps the ACL; the revoke below only restates it. Data only otherwise: no table, no grant.
--
-- Prevented by: scripts/checks/a_supplier_reply_names_confirming_services_and_is_signed.test.mjs and the _probe.sql beside this file.

create or replace function public.fn_supplier_reply_answer(p_intent text, p_link text)
returns text
language sql immutable
set search_path to 'public', 'pg_temp'
as $fn$
  select (case p_intent
    when 'subsidiary' then
      E'Thank you for your message.\n\nA separately licensed company registers on its own, with its own trade licence and a different e-mail address: one e-mail address manages one company.\n\nTo register it, open ' || p_link || E' , choose "Create account" and use that company''s work e-mail. It needs its licensed name, a UAE mobile number verified with a code, the verified work e-mail, the trade licence, the company profile and acceptance of the supplier terms. Then the company confirms the services it provides in the Services tab of its portal: it is held until it does, and verified as soon as it has.\n\nAnything you have already started for your first company stays as it is. We will check in with you in a week.'
    when 'later' then
      E'Thank you, and there is no rush. Registration stays free for our first 1,000 suppliers.\n\nWhen the time suits you, open ' || p_link || E' and choose "Create account". We will write once more in two weeks. If you would rather we did not, reply "stop".'
    else
      E'Thank you for your reply.\n\nTo register, open ' || p_link || E' , choose "Create account" with your work e-mail and type the 6-digit code we send you. To be verified we need your licensed company name, a UAE mobile number verified with a code, the verified work e-mail, the trade licence, the company profile and your acceptance of the supplier terms. Then you confirm the services your company provides in the Services tab of your portal: you are held until you do, and verified as soon as you have. Only you can verify, accept and confirm these, so we cannot do it for you, but it takes a few minutes.\n\nIf you have a question, reply to this e-mail.'
    end) || E'\n\nKind regards,\nThe QuotesDone Team'
$fn$;
revoke execute on function public.fn_supplier_reply_answer(text, text) from public, anon, authenticated;
