-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260611104735   name: invite_campaign_setup
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

alter table leads add column if not exists invite_status text;   -- null/none | queued | sent | bounced | unsub
alter table leads add column if not exists invited_at timestamptz;
create index if not exists leads_invite_status_idx on leads(invite_status);

insert into app_secrets(key,value) values
  ('invite_enabled','false'),                 -- master switch; stays OFF until you say go
  ('invite_daily_cap','40'),                  -- warm-up: start small, raise over days
  ('invite_subject','Invitation to join QuotesDone — receive quote requests from UAE clients'),
  ('invite_body', E'Dear Sir/Madam,\n\nQuotesDone is a UAE marketplace that connects building, fit-out and facility clients with trusted suppliers. Clients describe a job, and we pass the request to suppliers who can quote for it.\n\nWe would like to invite your company to join — it is free to register. Once listed, you will receive relevant quote requests directly.\n\nTo join, please visit quotesdone.com and open the Suppliers section to complete a short registration. You will enter your company details and upload your documents yourself.\n\nWe will never ask for payment or passwords by email. If you would prefer not to receive these invitations, simply reply and we will remove you.\n\nLooking forward to welcoming you.')
on conflict (key) do nothing;
