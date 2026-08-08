-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260610135823   name: email_channels_setup
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- Sender identities + toggle (resend_api_key to be added by the user)
insert into app_secrets(key,value) values
  ('email_from_supplier','QuotesDone Suppliers <supplier@quotesdone.com>'),
  ('email_from_info','QuotesDone <info@quotesdone.com>'),
  ('email_reply_supplier','supplier@quotesdone.com'),
  ('email_reply_info','info@quotesdone.com'),
  ('email_enabled','false')
on conflict (key) do nothing;

-- Document review queue (AI analyses inbound docs, admin approves before attaching to profile)
create table if not exists doc_reviews (
  id bigint generated always as identity primary key,
  lead_id bigint references leads(id),
  from_email text,
  subject text,
  file_name text,
  file_path text,            -- path in supplier-docs storage bucket
  mime text,
  ai_relevant boolean,
  ai_category text,          -- e.g. trade_license, company_profile, catalogue, certificate, bank_letter, other
  ai_summary text,
  ai_suggested_field text,   -- which profile field/column it informs, if any
  ai_confidence text,        -- low|medium|high
  status text not null default 'pending',   -- pending|approved|rejected
  decided_by text,
  decided_at timestamptz,
  created_at timestamptz default now()
);
create index if not exists doc_reviews_status_idx on doc_reviews(status, created_at desc);

-- notifications: ensure a status column default we can scan ('queued')
update notifications set status='queued' where status is null;
