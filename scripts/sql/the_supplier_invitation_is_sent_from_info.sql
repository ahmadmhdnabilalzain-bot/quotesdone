-- marketing, ledger 993, 24 Sep 2026. The supplier invitation lands in Microsoft 365 Junk.
-- Measured on management@doratajewelries.com (Resend 01a0d33c..., 11:46:30Z): SCL:5 SFV:SPM CAT:SPM BCL:0,
-- compauth=pass reason=100, spf/dkim/dmarc pass, dest:J by SpamFilterAuthJ -- a spam-filter verdict, not auth.
-- Seed sends the same day (scripts/invitation_inbox_check.mjs):
--   supplier path, toned-down copy ............ Junk
--   supplier path, three-line body, no link ... Junk
--   info@ path, the same three-line body ....... Inbox
--   info@ path, the full live invitation ....... Inbox
-- The copy is not the cause; the supplier@ sending identity is. info@quotesdone.com has sent transactional
-- mail since June that this tenant accepts; supplier@ carried the Jul-Aug cold batch (5.8% bounces).
-- This moves only the From. The supplier frame, Reply-To and RFC 8058 unsubscribe headers stay, because
-- they are built from to_role, not from this key.
update public.app_secrets set value = 'QuotesDone <info@quotesdone.com>' where key = 'email_from_supplier';
select case when (select value from public.app_secrets where key = 'email_from_supplier') = 'QuotesDone <info@quotesdone.com>'
            then 'PROBE OK' else 'PROBE FAILED: email_from_supplier not moved' end as verdict;
