-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260620120149   name: prereveal_questions
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

create table if not exists public.questions (
  id bigint generated always as identity primary key,
  inquiry_id uuid references public.inquiries(id) on delete cascade,
  supplier_id bigint references public.leads(id) on delete cascade,
  customer_id uuid references public.customers(id) on delete set null,
  question text not null,
  answer text,
  asked_at timestamptz default now(),
  answered_at timestamptz
);
create index if not exists q_sup_idx on public.questions(supplier_id, answered_at);
create index if not exists q_inq_sup_idx on public.questions(inquiry_id, supplier_id);
alter table public.questions enable row level security;
