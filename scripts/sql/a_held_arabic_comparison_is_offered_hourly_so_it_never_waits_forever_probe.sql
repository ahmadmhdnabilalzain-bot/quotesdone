-- PROBE for a_held_arabic_comparison_is_offered_hourly_so_it_never_waits_forever.sql. Never applied: it always raises,
-- so every row it writes (and every real waiter the routine stamps as offered) is rolled back. Must print PROBE OK.
-- Seat: sales_engineer. Two waiters under ids no real inquiry carries, on a line no document contains: one created 2 h
-- ago (the clock offers it although its line has no Arabic), one created now (not offered).
do $$
declare v_first jsonb; v_second jsonb; v_fresh boolean;
begin
  insert into public.arabic_compare_waiter (inquiry_id, texts, created_at) values
    ('zz-probe-clock-old', array['ZZ PROBE clock line'], now() - interval '2 hours'),
    ('zz-probe-clock-new', array['ZZ PROBE clock line'], now());
  v_first := public.fn_arabic_compare_waiters_ready(100);
  v_fresh := exists (select 1 from public.arabic_compare_waiter where inquiry_id = 'zz-probe-clock-new' and last_offered_at is not null);
  v_second := public.fn_arabic_compare_waiters_ready(100);
  if not (v_first ? 'zz-probe-clock-old') then raise exception 'CHK<<PROBE FAILED: an incomplete waiter older than 1 h was not offered>>'; end if;
  if v_fresh then raise exception 'CHK<<PROBE FAILED: a fresh incomplete waiter was offered>>'; end if;
  if v_second ? 'zz-probe-clock-old' then raise exception 'CHK<<PROBE FAILED: offered twice within the hour>>'; end if;
  if has_function_privilege('anon', 'public.fn_arabic_compare_waiters_ready(integer)', 'execute') then raise exception 'CHK<<PROBE FAILED: anon may execute>>'; end if;
  raise exception 'CHK<<PROBE OK>>';
end $$;
