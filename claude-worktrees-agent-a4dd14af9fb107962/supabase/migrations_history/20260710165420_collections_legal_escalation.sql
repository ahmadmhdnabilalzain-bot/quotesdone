-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260710165420   name: collections_legal_escalation
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.


-- config for the non-response collections / legal escalation (founder-tunable)
create table if not exists public.collections_config(
  id int primary key default 1,
  interest_pa numeric not null default 0.09,        -- UAE commercial cap (Fed. Decree-Law 50/2022)
  admin_fee numeric not null default 250,           -- fixed collection/admin fee at legal stage
  escalate_working_days int not null default 30,    -- working days after due -> legal escalation
  reminder_max int not null default 3,
  updated_at timestamptz not null default now()
);
insert into public.collections_config(id) values (1) on conflict (id) do nothing;

-- escalation tracking on the non-response fine
alter table public.supplier_dues
  add column if not exists interest_amount numeric,
  add column if not exists admin_fee numeric,
  add column if not exists total_claim numeric,
  add column if not exists legal_stage text,
  add column if not exists legal_escalated_at timestamptz,
  add column if not exists demand_letter_path text,
  add column if not exists case_file_path text,
  add column if not exists evidence_terms_path text;

