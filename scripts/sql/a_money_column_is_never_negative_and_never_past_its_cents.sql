-- A MONEY COLUMN IS NEVER NEGATIVE AND NEVER PAST ITS CENTS.
-- Seat: accountant (quotes and quote lines are the sales_engineer's tables; the constraint is the
-- accountant's rule). 28 Sep 2026. Deep audit 28 Sep, runtime/data finding 7.
--
-- MEASURED (production htdblwldjkcgjvmqkbeh, read-only, 28 Sep 2026) BEFORE writing a single constraint:
--   rows    negative   past 2 dp (4 dp for unit prices)
--   quotes 3 · quote_items 7 · expense_entries 55 · expenses 4 · leads 19,905 · stripe_payout 2 ·
--   pricing_config 1 · ap_bills 0 · budget_lines 0 · po_lines 0 · quote_committed_items 0
--   -> 0 negative values and 0 values past their scale in every column below. No row is changed or
--   deleted by this file; every constraint is validated against the data already there.
--
-- WHAT THIS ADDS
--   * col >= 0 on the money columns that can only be a price, a fee, a cost or a payment. A NULL still
--     passes (a quote line without a price is held, not zero); NOT NULL is not added here.
--   * a scale CHECK only where the column is unconstrained numeric: 2 dp for an amount, 4 dp for a
--     unit price (the same scale po_lines.unit_price already has as numeric(18,4)). Columns typed
--     numeric(p,2) already enforce their scale and get only the sign check.
-- WHAT IT DOES NOT: signed ledger columns are left alone on purpose - bank_statement_line.amount_aed,
-- gl_journal_lines, refunds and anything that can
-- legitimately be a reversal. stripe_payout.amount_fils is integer fils, so only its sign is checked.
--
-- Re-runnable: each constraint is dropped if present and added again.
-- Prevented by: scripts/checks/a_money_column_is_never_negative.test.mjs.

-- quotes (the supplier's price, the customer's price, the platform fee, VAT)
alter table public.quotes drop constraint if exists quotes_customer_price_money_ck;
alter table public.quotes add constraint quotes_customer_price_money_ck check (customer_price >= 0 and customer_price = round(customer_price, 2));
alter table public.quotes drop constraint if exists quotes_app_fee_money_ck;
alter table public.quotes add constraint quotes_app_fee_money_ck check (app_fee >= 0 and app_fee = round(app_fee, 2));
alter table public.quotes drop constraint if exists quotes_vat_amount_money_ck;
alter table public.quotes add constraint quotes_vat_amount_money_ck check (vat_amount >= 0 and vat_amount = round(vat_amount, 2));
alter table public.quotes drop constraint if exists quotes_amount_as_stated_money_ck;
alter table public.quotes add constraint quotes_amount_as_stated_money_ck check (amount_as_stated >= 0 and amount_as_stated = round(amount_as_stated, 2));
alter table public.quotes drop constraint if exists quotes_quote_amount_scale_ck;
alter table public.quotes add constraint quotes_quote_amount_scale_ck check (quote_amount = round(quote_amount, 2));

-- quote lines
alter table public.quote_items drop constraint if exists quote_items_unit_price_money_ck;
alter table public.quote_items add constraint quote_items_unit_price_money_ck check (unit_price >= 0 and unit_price = round(unit_price, 4));
alter table public.quote_items drop constraint if exists quote_items_amount_money_ck;
alter table public.quote_items add constraint quote_items_amount_money_ck check (amount >= 0 and amount = round(amount, 2));
alter table public.quote_committed_items drop constraint if exists quote_committed_items_unit_price_money_ck;
alter table public.quote_committed_items add constraint quote_committed_items_unit_price_money_ck check (unit_price >= 0 and unit_price = round(unit_price, 4));
alter table public.quote_committed_items drop constraint if exists quote_committed_items_line_amount_money_ck;
alter table public.quote_committed_items add constraint quote_committed_items_line_amount_money_ck check (line_amount >= 0 and line_amount = round(line_amount, 2));

-- what the company owes and spends (ap_bills and budget_lines are numeric(18,2); po_lines numeric(18,4))
alter table public.ap_bills drop constraint if exists ap_bills_amounts_money_ck;
alter table public.ap_bills add constraint ap_bills_amounts_money_ck check (subtotal >= 0 and vat_amount >= 0 and total >= 0 and amount_paid >= 0);
alter table public.budget_lines drop constraint if exists budget_lines_amount_money_ck;
alter table public.budget_lines add constraint budget_lines_amount_money_ck check (amount >= 0);
alter table public.po_lines drop constraint if exists po_lines_unit_price_money_ck;
alter table public.po_lines add constraint po_lines_unit_price_money_ck check (unit_price >= 0);
alter table public.expenses drop constraint if exists expenses_amount_money_ck;
alter table public.expenses add constraint expenses_amount_money_ck check (amount >= 0 and amount = round(amount, 2));
alter table public.expense_entries drop constraint if exists expense_entries_amount_money_ck;
alter table public.expense_entries add constraint expense_entries_amount_money_ck check (amount >= 0 and amount = round(amount, 2));

-- what the company is paid and charges
alter table public.stripe_payout drop constraint if exists stripe_payout_amount_fils_money_ck;
alter table public.stripe_payout add constraint stripe_payout_amount_fils_money_ck check (amount_fils >= 0);
alter table public.pricing_config drop constraint if exists pricing_config_nonresponse_fee_money_ck;
alter table public.pricing_config add constraint pricing_config_nonresponse_fee_money_ck check (supplier_nonresponse_admin_fee_aed >= 0);
alter table public.leads drop constraint if exists leads_registration_fee_due_money_ck;
alter table public.leads add constraint leads_registration_fee_due_money_ck check (registration_fee_due >= 0 and registration_fee_due = round(registration_fee_due, 2));

-- Verdict: all 17 constraints exist and are validated.
select case when (select count(*) from pg_constraint
                   where connamespace = 'public'::regnamespace and convalidated
                     and conname in ('quotes_customer_price_money_ck','quotes_app_fee_money_ck','quotes_vat_amount_money_ck',
                       'quotes_amount_as_stated_money_ck','quotes_quote_amount_scale_ck','quote_items_unit_price_money_ck',
                       'quote_items_amount_money_ck','quote_committed_items_unit_price_money_ck',
                       'quote_committed_items_line_amount_money_ck','ap_bills_amounts_money_ck','budget_lines_amount_money_ck',
                       'po_lines_unit_price_money_ck','expenses_amount_money_ck','expense_entries_amount_money_ck',
                       'stripe_payout_amount_fils_money_ck','pricing_config_nonresponse_fee_money_ck',
                       'leads_registration_fee_due_money_ck')) = 17
       then 'PROBE OK' else 'PROBE FAILED: a money CHECK is missing or not validated' end as verdict;
