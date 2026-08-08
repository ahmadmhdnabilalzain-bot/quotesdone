-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260626204910   name: quote_pdf_cache
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

create table if not exists public.quote_pdf_cache (
  quote_id    uuid not null,
  lang        text not null,
  customer_id uuid,
  bucket      text not null,
  path        text not null,
  created_at  timestamptz not null default now(),
  primary key (quote_id, lang)
);
alter table public.quote_pdf_cache enable row level security;
revoke all on public.quote_pdf_cache from anon, authenticated;
create index if not exists idx_quote_pdf_cache_cust_time on public.quote_pdf_cache(customer_id, created_at);
