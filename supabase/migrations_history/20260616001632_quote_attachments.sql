-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260616001632   name: quote_attachments
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

alter table public.quotes
  add column if not exists original_file_path text,
  add column if not exists original_file_name text,
  add column if not exists source text not null default 'form',
  add column if not exists masked_terms jsonb,
  add column if not exists extracted jsonb;

insert into storage.buckets (id, name, public)
values ('quote-files','quote-files', false)
on conflict (id) do nothing;
