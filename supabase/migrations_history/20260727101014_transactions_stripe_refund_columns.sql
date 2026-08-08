-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260727101014   name: transactions_stripe_refund_columns
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- Approving a refund previously only flipped a status column; no money moved and nothing
-- recorded that fact. These columns let refunds_api prove the Stripe refund happened
-- before it marks the transaction refunded and charges the supplier.
alter table public.transactions
  add column if not exists refund_stripe_id text,
  add column if not exists refund_amount_aed numeric,
  add column if not exists refund_confirmed_at timestamptz;

create unique index if not exists transactions_refund_stripe_uidx
  on public.transactions (refund_stripe_id) where refund_stripe_id is not null;
