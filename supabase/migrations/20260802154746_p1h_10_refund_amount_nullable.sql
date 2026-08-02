-- The CHECK (amount_fils > 0) was relaxed, but the column was still NOT NULL - so "store unknown as
-- unknown" was still impossible and every dashboard-issued refund with no amount would have been
-- rejected outright, which is worse than the 1-fils placeholder it replaced. Caught by the test
-- rather than by reading, which is the argument for the tests.
alter table public.refunds alter column amount_fils drop not null;

comment on column public.refunds.amount_fils is
  'Refund amount in fils. NULL means genuinely unknown - the event carried none and Stripe could not be read. NULL is excluded from every financial total and keeps the row in v_refunds_unreconciled until resolved. It is never a placeholder.';
comment on column public.refunds.amount_source is
  'Where the amount came from: in_platform_request, webhook_event, stripe_api, manual, or unknown.';
