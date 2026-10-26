-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260710160952   name: quote_comparisons_snapshots
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.


create table if not exists public.quote_comparisons(
  id bigserial primary key,
  inquiry_id uuid not null,
  customer_id uuid,
  lang text default 'en',
  quote_count int,
  signature text,
  analysis jsonb not null,
  created_at timestamptz not null default now()
);
create index if not exists ix_quote_comparisons_inq on public.quote_comparisons(inquiry_id, created_at desc);

