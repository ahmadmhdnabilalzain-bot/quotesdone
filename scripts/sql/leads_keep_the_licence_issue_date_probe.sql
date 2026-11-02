-- PROBE for leads_keep_the_licence_issue_date.sql. Seat: sales_engineer. Never applied: it always raises CHK<<...>>
-- and rolls back. Proves the column exists as a date and is nullable.
do $probe$
declare f text[] := '{}'; v_type text; v_null text;
begin
  select data_type, is_nullable into v_type, v_null from information_schema.columns where table_schema = 'public' and table_name = 'leads' and column_name = 'license_issue_date';
  if v_type is distinct from 'date' then f := f || ('license_issue_date is not a date column: ' || coalesce(v_type, 'absent')); end if;
  if v_null is distinct from 'YES' then f := f || 'license_issue_date is not nullable'; end if;
  raise exception 'CHK<<%>> type % nullable %', case when cardinality(f) = 0 then 'PROBE OK' else 'PROBE FAILED: ' || array_to_string(f, '; ') end, v_type, v_null;
end
$probe$;
