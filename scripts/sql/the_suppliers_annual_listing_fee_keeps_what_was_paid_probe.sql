-- Probe for the_suppliers_annual_listing_fee_keeps_what_was_paid.sql (22 Sep 2026). Pure probe, no DDL:
-- reads the catalogue only and answers one verdict row.
select case when count(*) = 2 then 'PROBE OK' else 'PROBE FAILED' end as verdict,
       string_agg(column_name || ':' || data_type, ', ' order by column_name) as seen
  from information_schema.columns
 where table_schema = 'public' and table_name = 'leads'
   and column_name in ('registration_payment_ref', 'registration_amount_aed');
