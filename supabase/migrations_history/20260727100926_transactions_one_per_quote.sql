-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260727100926   name: transactions_one_per_quote
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- Both settlement writers (stripe_confirm:46, stripe_webhook:118) do select-then-insert,
-- and stripe_confirm's conflict handler is commented as relying on a constraint that did
-- not exist. Without it, two concurrent deliveries could each pass the existence check
-- and insert, charging a customer twice for one reveal.
create unique index if not exists transactions_quote_id_uidx
  on public.transactions (quote_id)
  where quote_id is not null;
