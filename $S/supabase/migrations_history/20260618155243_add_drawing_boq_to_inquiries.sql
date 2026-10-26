-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260618155243   name: add_drawing_boq_to_inquiries
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

alter table public.inquiries
  add column if not exists drawing_file_path text,
  add column if not exists drawing_file_name text,
  add column if not exists boq jsonb,
  add column if not exists boq_confidence text;

insert into storage.buckets (id, name, public)
values ('drawing-files','drawing-files', false)
on conflict (id) do nothing;
