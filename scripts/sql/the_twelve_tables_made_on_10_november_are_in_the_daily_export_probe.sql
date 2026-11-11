-- PROBE for the_twelve_tables_made_on_10_november_are_in_the_daily_export.sql. Seat: it_engineer. Never applied: it writes
-- nothing and always raises CHK<<...>>, so the transaction rolls back either way. Run it after the file is applied.
-- Asserts: each of the twelve tables exists, has its registry row with exported = true, and is in fn_table_export_list()
-- (what backup/index.ts exports every day); and no exported row names a table that does not exist (the export would fail
-- that day on it).
do $probe$
declare
  v_want text[] := array['break_even_basis', 'break_even_cost_line', 'ceo_break_even_month', 'ceo_break_even_replan',
    'ceo_brief_line', 'ceo_seat_month_target', 'ceo_year_plan_archive', 'customer_trade_waitlist', 'it_session_fix_day',
    'supplier_strike_event', 'trade_customer_opening', 'trade_opening_rule'];
  v_bad text := ''; v_t text; v_listed int; v_gone text;
begin
  foreach v_t in array v_want loop
    if to_regclass('public.' || v_t) is null then v_bad := v_bad || ' no-table:' || v_t; end if;
    if not exists (select 1 from public.table_export_registry r where r.table_name = v_t and r.exported) then
      v_bad := v_bad || ' not-exported:' || v_t; end if;
  end loop;
  select count(*) into v_listed from public.fn_table_export_list() l where l.table_name = any (v_want);
  if v_listed <> 12 then v_bad := v_bad || ' listed=' || v_listed; end if;
  select string_agg(r.table_name, ',') into v_gone from public.table_export_registry r
   where r.exported and to_regclass('public.' || r.table_name) is null;
  if v_gone is not null then v_bad := v_bad || ' exported-but-missing:' || v_gone; end if;
  if v_bad <> '' then raise exception 'CHK<<PROBE FAILED:%>>', v_bad; end if;
  raise exception 'CHK<<PROBE OK 12 of 12 exported and listed>>';
end $probe$;
