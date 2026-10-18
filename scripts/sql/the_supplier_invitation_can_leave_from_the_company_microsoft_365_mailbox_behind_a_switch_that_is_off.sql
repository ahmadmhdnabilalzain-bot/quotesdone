-- THE SUPPLIER INVITATION CAN LEAVE FROM THE COMPANY'S MICROSOFT 365 MAILBOX, BEHIND A SWITCH THAT IS OFF
-- (5 Oct 2026, founder ledger 1115; Assigned: it_engineer (mail path) + marketing (copy)).
--
-- MEASURED: GlockApps put 54% of the invitation in spam at Outlook/Hotmail/Yahoo/AOL - Resend's shared SES IPs
-- were on 11 blocklists and the invitation lane's subdomain had no reputation. send_outbox now has a second
-- provider path (supabase/functions/send_outbox/m365_lane.ts): Microsoft Graph, client credentials, sendMail as
-- MIME so List-Unsubscribe is a real header. Only supplier_invite, supplier_invite_seed and supplier_invite_nudge
-- to a supplier ever take it; refused or unconfigured = the row is HELD, never sent through Resend.
--
-- WHAT THIS CHANGES: two settings, seeded and never overwritten.
--   invite_m365_enabled  'false'  - the switch. Nothing leaves through Microsoft 365 until someone sets 'true'.
--   invite_m365_mailbox  'supplier@quotesdone.com' - the sending mailbox (needs Mail.Send application permission).
-- The credentials are NOT here: MS_TENANT_ID, MS_CLIENT_ID, MS_CLIENT_SECRET are edge-function secrets, read by
-- name in send_outbox and never stored in the database.
-- WHAT IT DOES NOT CHANGE: invite_lane_enabled, invite_daily_cap (shared, the lane also stops at 150/day),
-- invite_enabled, supplier_outreach_golive. No routine, no table.

insert into public.app_secrets (key, value) values
  ('invite_m365_enabled', 'false'),
  ('invite_m365_mailbox', 'supplier@quotesdone.com')
on conflict (key) do nothing;

select case
  when (select count(*) from public.app_secrets where key in ('invite_m365_enabled', 'invite_m365_mailbox')) <> 2
    then 'PROBE FAILED: the two Microsoft 365 lane settings are not both present'
  when (select value from public.app_secrets where key = 'invite_m365_mailbox') !~ '^[^@\s]+@[^@\s]+\.[a-z]{2,}$'
    then 'PROBE FAILED: invite_m365_mailbox is not an address'
  else 'PROBE OK' end as verdict;
