-- THE SUPPLIER'S ANNUAL LISTING FEE KEEPS WHAT WAS PAID (22 Sep 2026, seats: accountant + sales_engineer).
--
-- MEASURED 22 Sep 2026 on production (read-only):
--   * public.leads carries registration_paid_at, registration_expires_at and subscription_paid_until for a
--     paid annual listing fee, and nothing else: no amount and no payment reference.
--     stripe_webhook (supplier_registration) knows both (session amount_total, payment_intent) and wrote
--     them only into a seat handoff payload.
--   * 0 leads have registration_paid_at set; 0 supplier_dues have paid_at set. Nothing needs back-filling.
--   * pricing_config.supplier_reg_fee = 1000 AED today, so the fee cannot be re-derived later from config:
--     the price a supplier paid must be recorded with the payment.
--
-- WHAT WAS WRONG. Audit of every document we issue (22 Sep 2026, finding 2): a supplier's only document
-- for the listing fee was Stripe's own invoice (supplier_pay turned invoice_creation on). The founder
-- (instructions 568, 569): no third-party PDF is sent as ours. The Stripe invoice is now OFF for both
-- supplier checkouts and the invoice and receipt are QuotesDone's own
-- (supabase/functions/_shared/supplier_payment_documents.ts, served by supplier_api receipt_pdf) — which
-- need the amount and the reference the payment carried.
--
-- WHAT THIS CHANGES. Two nullable columns on public.leads, written by stripe_webhook on settlement (a
-- separate best-effort update, so this file not being applied yet can never undo a settlement).
--
-- WHAT IT DOES NOT CHANGE. No routine, no trigger, no policy, no grant; the registration state rules
-- (fn_supplier_registration_state, trg_bz_supplier_registration_state) are untouched. leads' existing RLS and
-- grants cover the new columns.
--
-- Probe: scripts/sql/the_suppliers_annual_listing_fee_keeps_what_was_paid_probe.sql (pure probe, verdict row).

alter table public.leads add column if not exists registration_payment_ref text;
alter table public.leads add column if not exists registration_amount_aed numeric(12,2)
  check (registration_amount_aed is null or registration_amount_aed >= 0);

comment on column public.leads.registration_payment_ref is
  'The Stripe payment reference of the last annual listing fee paid (stripe_webhook, supplier_registration). Printed on the supplier''s QuotesDone invoice and receipt.';
comment on column public.leads.registration_amount_aed is
  'The amount in AED of the last annual listing fee paid, as charged. Printed on the supplier''s QuotesDone invoice and receipt.';
