-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260608191638   name: inbound_pipeline_tables
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

create table if not exists public.inbound_messages (
  id bigint generated always as identity primary key,
  lead_id bigint references public.leads(id),
  from_email text,
  to_email text,
  subject text,
  body text,
  attachments_count int default 0,
  matched_existing boolean default false,
  created_new_lead boolean default false,
  ai_ok boolean default false,
  ai_notes text,
  raw jsonb,
  created_at timestamptz default now()
);
alter table public.inbound_messages enable row level security;
-- no policies = service_role only (edge functions). deny-all for anon.

-- webhook shared secret used by the email router to authenticate to our endpoint
insert into public.app_secrets(key, value)
values ('inbound_secret', encode(gen_random_bytes(24), 'hex'))
on conflict (key) do nothing;
