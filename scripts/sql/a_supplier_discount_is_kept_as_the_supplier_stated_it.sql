-- A SUPPLIER'S DISCOUNT IS KEPT AS THE SUPPLIER STATED IT — founder rulings 1207 and 1208, 13 Oct 2026.
-- Seat: sales_engineer (the quotation and the comparison); the fee basis is the accountant's.
--
-- 1207: a supplier's quotation may state anything (a discount, VAT or no VAT, any terms). QuotesDone shows the
-- customer EXACTLY what the supplier stated — "AED 2,000, after discount AED 1,700" — so the price before the
-- discount, the discount and its wording are structured columns, no longer folded into `conditions`.
-- 1208: the 3% is taken on the FINAL price BEFORE VAT, after the stated discount (2,000 → 1,700 + VAT → 3% × 1,700).
-- That figure is quotes.price_ex_vat, and quotes.quote_amount (what every charge path reads) is written from it by
-- supplier_api (_shared/stated_price.ts storedPrice). These three columns only record what the supplier wrote.
--
-- Additive and nullable: no rewrite of the table, no default, no lock beyond the catalogue update.
-- prevented by: supabase/functions/_shared/stated_price.test.ts (the fee base in every case the ruling names)
set lock_timeout = '5s';
alter table public.quotes add column if not exists gross_amount numeric;
alter table public.quotes add column if not exists discount_amount numeric;
alter table public.quotes add column if not exists discount_label text;
comment on column public.quotes.gross_amount is 'Ruling 1207: the supplier''s price before its stated discount, as stated. Null when no discount was stated.';
comment on column public.quotes.discount_amount is 'Ruling 1207: the discount the supplier stated, in AED. price_ex_vat (and quote_amount, the fee base, ruling 1208) is the price AFTER it, excluding VAT.';
comment on column public.quotes.discount_label is 'Ruling 1207: the supplier''s own words for the discount ("Special discount 15%"), identity-scrubbed.';
select case when (select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'quotes'
                  and column_name in ('gross_amount', 'discount_amount', 'discount_label')) = 3
            then 'PROBE OK' else 'PROBE FAILED: the three discount columns are not all present' end as verdict;
