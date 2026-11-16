-- A STRANGER WRITING TO info@ OR management@ REACHES THE SEATS (it_engineer for the mail path, customer_support for the
-- answer; 16 Nov 2026; ledger 1446, 1453, 1543).
--
-- The founder: "All our emails should be with the agents" (1446). "Every email from a supplier to management@, supplier@ or
-- info@ requires a reply, except mail from the bank and such services ... A supplier does NOT have to be in the lead list"
-- (1543). "I don't want you to wait on me" (1710).
--
-- MEASURED (SELECT, production, 16 Nov 2026 ~14:15Z):
--   * info@quotesdone.com is a Microsoft 365 mailbox (quotesdone.com MX is quotesdone-com.mail.protection.outlook.com,
--     docs/reports/QuotesDone Campaign/GLOCKAPPS_27_OCT_RESULT_AND_FIX_PLAN.md). It is the From and Reply-To of every
--     sign-in code (login_otp) and KYC mail (kyc), app_secrets.email_reply_info = info@quotesdone.com.
--   * resilience_ping reads it every 15 minutes (_shared/m365_reply_inbox.ts pollTenantMailboxes). agent_runs, agent
--     'resend_inbound', counts.m365_tenant: "read info@quotesdone.com, management@quotesdone.com (list from graph)",
--     mailboxes 2, handed 0, skipped 134-136, not_handed 68-70, every tick.
--   * inbound_messages, 60 days: info@quotesdone.com 0 rows, management@quotesdone.com 1 row (a known supplier).
--   * WHY: a sender who is no customer, lead or staff address, writing outside one of our threads, is handed only after
--     app_secrets.m365_tenant_strangers_from. That row does not exist, so every such mail is 'skipped' and stays in the
--     mailbox unread by any seat. A reply to a sign-in code or a KYC mail comes from exactly such a person (a sign-up that
--     is not yet a customer or lead), and its In-Reply-To is the Message-ID Resend gave the code mail, which is not ours.
--     The switch was left off "by decision, after watching first runs" (memory checkpoint-2-nov-10-hour-push.md, #1741):
--     two weeks of runs since are status ok, hand_failed 0, list_failed 0.
--
-- WHAT CHANGES: the switch is set to the moment this file is applied. From then on a stranger's NEW mail to info@ or
--   management@ is handed to resend_inbound, the same handler, tables and threading as every other address, and email_triage
--   reads it there (info@ is customer correspondence, customer_mail.ts; management@ gets the normal triage, tenantMailAnswerable).
--   ORDER (coordinator, 16 Nov 2026): apply this ONLY AFTER email_triage is deployed with the info@/management@ reading and
--   scripts/sql/info_and_management_mail_is_read_before_it_is_answered.sql is applied. Then a model reads each such mail first
--   and decides: answer (a real person we owe an answer), route to the owning seat (vendor, pitch, invoice; legal and press to
--   the CEO), close with the reason (spam, newsletter, auto-reply, bounce), or hold it when it cannot read it. Only 'answer'
--   reaches the reply path.
--   Nothing older than the apply is handed, so no old mail is answered. Unchanged, still never handed: the founder and staff,
--   our own domains, a bank (mashreq*, app_secrets.m365_financial_domains), a machine sender (no-reply, alerts, billing,
--   notifications, delivery reports), a DMARC report, and a stranger in Junk. email_triage then still refuses list mail,
--   auto-replies, no-reply senders, calendar replies, the daily cap and reply loops (customer_mail.ts noAutoReply).
--   supplier@ is untouched: pollReplyInbox reads it, not this switch.
--
-- PREVENTED BY: supabase/functions/_shared/m365_tenant_mailboxes.test.ts ("a reply to a sign-in code in info@ ...": the canon
--   must set this switch, and with it a stranger's reply to the code reaches resend_inbound addressed to info@) and
--   scripts/sql/a_stranger_writing_to_info_or_management_reaches_the_seats_probe.sql.
-- PRODUCTION SIGNAL after the apply: the next tenant agent_runs row reads handed >= 1 whenever a stranger has written, and
--   inbound_messages gains rows with to_email info@quotesdone.com and provider_email_id 'm365:...'.

insert into public.app_secrets (key, value)
values ('m365_tenant_strangers_from', to_char(now() at time zone 'utc', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'))
on conflict (key) do nothing;

select case
  when (select value from public.app_secrets where key = 'm365_tenant_strangers_from') ~ '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$'
   and (select value::timestamptz from public.app_secrets where key = 'm365_tenant_strangers_from') <= now()
  then 'PROBE OK: strangers writing to info@ and management@ are handed to resend_inbound from '
       || (select value from public.app_secrets where key = 'm365_tenant_strangers_from')
  else 'PROBE FAILED: app_secrets.m365_tenant_strangers_from is not an ISO time at or before now' end as verdict;
