-- PROBE for the_company_legal_calendar_carries_its_licence_nol_vat_and_terms_dates.sql (seat: accountant).
-- Pure probe: no DDL, no writes of its own. It is sent AFTER the .sql text in ONE request through
-- scripts/lib/safe_replay.mjs replaySql({ rows: true }), which always rolls the request back, so the
-- calendar rows the .sql writes are read here and never persist. Its last (only) statement is the verdict row.
with m as (
  select
    (select count(*) from public.it_expiry
      where item in ('trade_licence_det_1633275', 'tdra_nol_26_100000665') and warn_days = array[90, 60, 30])::int as expiries,
    (select count(*) from public.company_calendar where kind = 'compliance' and owner_dept = 'accountant' and event_name in (
      'Trade licence DET 1633275 expires', 'TDRA NOL NOL-26-100000665 expires',
      'VAT registration threshold watch (AED 375,000, rolling 12 months)', 'Terms versions in force'))::int as calendar,
    (select count(*) from public.company_calendar where event_name = 'Trade licence DET 1633275 expires'
      and starts_on = date '2027-06-24')::int as licence_date,
    (select count(*) from public.company_calendar where event_name = 'TDRA NOL NOL-26-100000665 expires'
      and starts_on = date '2027-09-14')::int as nol_date,
    (select count(*) from public.table_export_registry where table_name = 'company_calendar' and exported)::int as exported
)
select case when expiries = 2 and calendar = 4 and licence_date = 1 and nol_date = 1 and exported = 1
            then 'PROBE OK' else 'PROBE FAILED' end
       || format(' expiries=%s calendar=%s licence_date=%s nol_date=%s exported=%s',
                 expiries, calendar, licence_date, nol_date, exported) as verdict
  from m;
