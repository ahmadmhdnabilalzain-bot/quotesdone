-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260713112611   name: finance_subscription_reminders
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

alter table expenses add column if not exists next_due date;
alter table expenses add column if not exists last_reminded_at timestamptz;
alter table expenses add column if not exists reminder_days int not null default 3;
create index if not exists expenses_next_due_idx on expenses(next_due) where active;
-- backfill a sane next_due for existing active recurring expenses that lack one
update expenses set next_due = (case when coalesce(cadence,'monthly') ilike 'annual%' or cadence ilike 'year%' then (coalesce(expense_date, current_date) + interval '1 year') else (coalesce(expense_date, current_date) + interval '1 month') end)::date
where active and next_due is null;
