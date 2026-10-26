-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260727085305   name: payment_dispute_table
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

create table if not exists public.payment_dispute (
  id               bigserial primary key,
  stripe_dispute_id text unique,
  stripe_charge_id text,
  payment_ref      text,
  transaction_id   bigint,
  amount_aed       numeric,
  currency         text default 'aed',
  reason           text,
  status           text not null default 'needs_response'
                   check (status in ('needs_response','under_review','won','lost','warning_closed','withdrawn')),
  evidence_due_by  timestamptz,
  evidence_submitted_at timestamptz,
  outcome_note     text,
  opened_at        timestamptz not null default now(),
  closed_at        timestamptz,
  owner_agent      text default 'cfo'
);
create index if not exists payment_dispute_open_idx on public.payment_dispute (status, evidence_due_by);
alter table public.payment_dispute enable row level security;
