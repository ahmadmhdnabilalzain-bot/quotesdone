-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260625183820   name: auth_onboarding_schema
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

alter table public.customers
  add column if not exists date_of_birth date,
  add column if not exists email_verified boolean not null default false,
  add column if not exists tos_accepted_at timestamptz,
  add column if not exists tos_version text;
update public.customers set email_verified = true where email_verified = false;

alter table public.leads
  add column if not exists owner_dob date,
  add column if not exists owner_email_verified boolean not null default false,
  add column if not exists license_city text,
  add column if not exists doc_extracted_at timestamptz,
  add column if not exists name_corrected_from text,
  add column if not exists catalog_doc_paths text[],
  add column if not exists company_profile_doc_path text;
update public.leads set owner_email_verified = true where claimed = true and owner_email_verified = false;

create table if not exists public.email_verifications (
  id uuid primary key default gen_random_uuid(),
  email text not null,
  token text not null unique,
  purpose text not null default 'signup',
  user_kind text not null default 'customer',
  expires_at timestamptz not null,
  used_at timestamptz,
  created_at timestamptz not null default now()
);
create index if not exists idx_email_verif_email on public.email_verifications(email);
create index if not exists idx_email_verif_token on public.email_verifications(token);

create table if not exists public.phone_verifications (
  id uuid primary key default gen_random_uuid(),
  email text,
  phone text not null,
  code text not null,
  user_kind text not null default 'customer',
  expires_at timestamptz not null,
  used_at timestamptz,
  attempts int not null default 0,
  created_at timestamptz not null default now()
);
create index if not exists idx_phone_verif_phone on public.phone_verifications(phone);

alter table public.email_verifications enable row level security;
alter table public.phone_verifications enable row level security;
