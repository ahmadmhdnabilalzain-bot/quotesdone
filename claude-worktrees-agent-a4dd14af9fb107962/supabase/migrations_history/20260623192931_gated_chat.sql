-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260623192931   name: gated_chat
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.


alter table messages add column if not exists flagged boolean default false;
alter table messages add column if not exists blocked boolean default false;
alter table messages add column if not exists redacted_body text;

create table if not exists chat_threads (
  inquiry_id text not null,
  supplier_id bigint not null,
  customer_id bigint,
  status text not null default 'requested',
  reason text,
  requested_by text,
  category text,
  strikes int not null default 0,
  opened_at timestamptz,
  closed_at timestamptz,
  created_at timestamptz not null default now(),
  primary key (inquiry_id, supplier_id)
);
alter table chat_threads enable row level security;

create table if not exists chat_violations (
  id bigint generated always as identity primary key,
  inquiry_id text,
  supplier_id bigint,
  sender_role text,
  sender_email text,
  matched text,
  body text,
  created_at timestamptz not null default now()
);
alter table chat_violations enable row level security;

alter table leads add column if not exists banned boolean default false;
alter table leads add column if not exists banned_reason text;
alter table leads add column if not exists chat_strikes int default 0;
alter table customers add column if not exists banned boolean default false;
alter table customers add column if not exists banned_reason text;
alter table customers add column if not exists chat_strikes int default 0;

