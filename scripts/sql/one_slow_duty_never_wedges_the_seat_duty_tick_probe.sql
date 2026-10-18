-- PROBE for one_slow_duty_never_wedges_the_seat_duty_tick.sql (it_engineer, 18 Oct 2026). Run after the file in
-- the same query: an aborted transaction, no DDL of its own, ends in raise exception CHK<<...>>, so nothing commits.
-- Proves, against production as it is (65 duties overdue, ceo.improvement 9 s unbounded):
--   1. fn_seat_duties_tick(8) returns inside 8 s (the PostgREST statement timeout that rolled it back since 15 Oct);
--   2. it ran at least one duty and that duty's last_ok_at moved to this transaction;
--   3. fn_ceo_improvement_sweep alone returns inside 5 s.
do $probe$
declare t timestamptz; v jsonb; v_ms int; v_sweep_ms int; v_fail text := '';
begin
  t := clock_timestamp();
  v := public.fn_seat_duties_tick(8);
  v_ms := round(extract(epoch from clock_timestamp() - t) * 1000);
  if v_ms >= 8000 then v_fail := v_fail || ' tick took ' || v_ms || ' ms;'; end if;
  if jsonb_array_length(coalesce(v->'ran', '[]')) = 0 then v_fail := v_fail || ' tick ran no duty;'; end if;
  if not exists (select 1 from public.seat_duty where last_ok_at = now()) then v_fail := v_fail || ' no last_ok_at moved;'; end if;

  t := clock_timestamp();
  perform public.fn_ceo_improvement_sweep();
  v_sweep_ms := round(extract(epoch from clock_timestamp() - t) * 1000);
  if v_sweep_ms >= 5000 then v_fail := v_fail || ' sweep took ' || v_sweep_ms || ' ms;'; end if;

  raise exception 'CHK<<%>>', case when v_fail = '' then 'PROBE OK tick_ms=' || v_ms || ' ran=' || jsonb_array_length(v->'ran') || ' sweep_ms=' || v_sweep_ms
                                     else 'PROBE FAILED:' || v_fail end;
end $probe$;
