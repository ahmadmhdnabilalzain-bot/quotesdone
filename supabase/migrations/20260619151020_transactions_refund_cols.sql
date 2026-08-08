-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260619151020   name: transactions_refund_cols
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

alter table public.transactions
  add column if not exists refund_reason text,
  add column if not exists refund_requested_at timestamptz,
  add column if not exists refund_resolved_at timestamptz,
  add column if not exists refund_note text;
