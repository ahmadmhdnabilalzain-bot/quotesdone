-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260709102537   name: dropbox_files_table
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

create table if not exists public.dropbox_files (
  id bigint generated always as identity primary key,
  dropbox_id text unique,
  path text not null,
  name text,
  is_folder boolean default false,
  size bigint default 0,
  content_hash text,
  server_modified timestamptz,
  synced_at timestamptz not null default now()
);
create index if not exists dropbox_files_path on public.dropbox_files(path);
revoke all on public.dropbox_files from anon, authenticated;
