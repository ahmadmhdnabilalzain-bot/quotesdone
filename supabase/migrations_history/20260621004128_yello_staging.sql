-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260621004128   name: yello_staging
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

create table if not exists yello_staging (
  company_id text primary key,
  slug text,
  name text,
  city text,
  src_category text,
  profile_url text,
  website text,
  phone text,
  mobile text,
  whatsapp text,
  categories text[],
  manager text,
  established text,
  address text,
  email text,
  email_source text,
  sector text,
  stage text not null default 'listed',
  note text,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);
create index if not exists yello_stage_idx on yello_staging(stage);
create index if not exists yello_email_idx on yello_staging(email);
create index if not exists yello_website_idx on yello_staging(website);
