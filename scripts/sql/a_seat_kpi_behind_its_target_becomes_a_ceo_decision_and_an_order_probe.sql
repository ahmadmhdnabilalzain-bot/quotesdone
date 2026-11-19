-- PROBE for a_seat_kpi_behind_its_target_becomes_a_ceo_decision_and_an_order.sql. Seat: ceo. 19 Nov 2026.
-- Agent: ceo kpi-to-order builder. Never applied: it ALWAYS raises CHK<<...>>, which rolls back every row it writes, the
-- real KPI orders the duty would give included. Its subjects are ZZ DEMO month targets for marketing in the current Dubai
-- month (metrics zz_demo_probe_kpi and zz_demo_probe_held) and ZZ DEMO founder holds (on a flag key that does not
-- exist, so fn_held_targets reads them held). It sends nothing: the notifications count must not move.
--   A: the ZZ DEMO KPI reads behind -> one order to marketing (target_miss, seat_kpi:...), evidence carries 'metric',
--      and one decision-log row.
--   B: a second run the same day -> no new order and no new decision-log row (once per KPI per day).
--   C: the KPI turns met in its month -> the order's done-condition reads true.
--   D: a held target reading behind -> NO order, and a decision-log row that names the hold.
--   E: a hold is added on the first KPI's metric -> fn_ceo_directive_run pauses its open order (it reads evidence->>'metric').
--   F: the month changes (the row is moved to next month, then deleted) -> the order's done-condition reads FALSE both
--      times: a November order is never met by December's row, nor by a missing row.
-- Run on the LOCAL database: node scripts/ci/rehearse_sql.mjs <the file> <this probe>; it must print PROBE OK.
do $probe$
declare r1 jsonb; r2 jsonb; r3 jsonb; n_notif bigint; n_notif_after bigint;
  v_kpi text := 'month_target:marketing:zz_demo_probe_kpi'; v_held_kpi text := 'month_target:marketing:zz_demo_probe_held';
  v_month date := date_trunc('month', (now() at time zone 'Asia/Dubai'))::date; v_ref text; v_held_ref text;
  n_dir_1 int; n_dir_2 int; n_log_1 int; n_log_2 int; v_dir_id bigint; v_dir_seat text; v_dir_status text; v_metric text;
  v_done_sql text; v_done_met boolean; v_held_orders int; v_held_log text; v_paused text; v_done_next_month boolean;
  v_done_missing boolean; v_behind_seen boolean;
begin
  select count(*) into n_notif from public.notifications;
  insert into public.ceo_seat_month_target (month, seat, metric, target, measured, status, basis, checked_at) values
    (v_month, 'marketing', 'zz_demo_probe_kpi', 10, 1, 'behind', 'ZZ DEMO probe target', now()),
    (v_month, 'marketing', 'zz_demo_probe_held', 10, 1, 'behind', 'ZZ DEMO probe held target', now());
  insert into public.founder_hold (hold_key, what_is_held, until_when, target_keys, flag_key, flag_released_value, note)
  values ('zz_demo_probe_hold', 'ZZ DEMO probe hold', 'ZZ DEMO never', array['zz_demo_probe_held'], 'zz_demo_probe_flag_absent', 'true', 'ZZ DEMO probe');
  select behind into v_behind_seen from public.seat_kpi where kpi = v_kpi and month = v_month;
  v_ref := 'seat_kpi:' || v_kpi || ':' || to_char(v_month, 'YYYY-MM');
  v_held_ref := 'seat_kpi:' || v_held_kpi || ':' || to_char(v_month, 'YYYY-MM');

  r1 := public.fn_ceo_kpi_behind_becomes_an_order();                                                  -- A, D
  select count(*) into n_dir_1 from public.ceo_directive where source_ref = v_ref;
  select count(*) into n_log_1 from public.ceo_decision_log where dedupe_key like 'seat_directive:kpi:' || v_kpi || ':%';
  select id, seat, status, done_sql, evidence->>'metric' into v_dir_id, v_dir_seat, v_dir_status, v_done_sql, v_metric
    from public.ceo_directive where source_ref = v_ref order by id desc limit 1;
  select count(*) into v_held_orders from public.ceo_directive where source_ref = v_held_ref;
  select evidence->>'founder_hold' into v_held_log from public.ceo_decision_log where dedupe_key like 'seat_directive:kpi:' || v_held_kpi || ':%';

  r2 := public.fn_ceo_kpi_behind_becomes_an_order();                                                  -- B
  select count(*) into n_dir_2 from public.ceo_directive where source_ref = v_ref;
  select count(*) into n_log_2 from public.ceo_decision_log where dedupe_key like 'seat_directive:kpi:' || v_kpi || ':%';

  update public.ceo_seat_month_target set measured = 10, status = 'met'                               -- C
   where month = v_month and seat = 'marketing' and metric = 'zz_demo_probe_kpi';
  execute 'select coalesce((' || v_done_sql || ')::boolean, false)' into v_done_met;

  update public.ceo_seat_month_target set month = (v_month + interval '1 month')::date                 -- F
   where month = v_month and seat = 'marketing' and metric = 'zz_demo_probe_kpi';
  execute 'select coalesce((' || v_done_sql || ')::boolean, false)' into v_done_next_month;
  delete from public.ceo_seat_month_target where seat = 'marketing' and metric = 'zz_demo_probe_kpi';
  execute 'select coalesce((' || v_done_sql || ')::boolean, false)' into v_done_missing;

  -- E: a second ZZ DEMO hold on the first KPI's metric (founder_hold rows are never updated: a trigger lifts a hold only
  -- by its flag); the CEO's close loop must pause the open order rather than close or re-issue it.
  insert into public.founder_hold (hold_key, what_is_held, until_when, target_keys, flag_key, flag_released_value, note)
  values ('zz_demo_probe_hold_2', 'ZZ DEMO probe hold 2', 'ZZ DEMO never', array['zz_demo_probe_kpi'], 'zz_demo_probe_flag_absent', 'true', 'ZZ DEMO probe');
  r3 := public.fn_ceo_directive_run(now());
  select status into v_paused from public.ceo_directive where id = v_dir_id;
  select count(*) into n_notif_after from public.notifications;

  raise exception 'CHK<<run1=% run2=% close_loop=% behind_seen=% orders_after_1=% orders_after_2=% log_after_1=% log_after_2=% seat=% status=% metric=% done_once_met=% held_orders=% held_log_hold=% paused_when_held=% done_next_month=% done_missing_row=% notifications_delta=% verdict=%>>',
    r1, r2, r3, v_behind_seen, n_dir_1, n_dir_2, n_log_1, n_log_2, v_dir_seat, v_dir_status, v_metric, v_done_met, v_held_orders,
    v_held_log, v_paused, v_done_next_month, v_done_missing, n_notif_after - n_notif,
    case when v_behind_seen and n_dir_1 = 1 and n_dir_2 = 1 and n_log_1 = 1 and n_log_2 = 1 and v_dir_seat = 'marketing'
              and v_dir_status = 'open' and v_metric = 'zz_demo_probe_kpi' and v_done_met
              and v_held_orders = 0 and v_held_log = 'zz_demo_probe_hold' and v_paused = 'paused'
              and not v_done_next_month and not v_done_missing
              and n_notif_after = n_notif and (r2->>'already_decided_today')::int >= 2
         then 'PROBE OK' else 'PROBE FAILED' end;
end $probe$;
