-- PROBE for a_seat_kpi_behind_its_target_becomes_a_ceo_decision_and_an_order.sql. Seat: ceo. 19 Nov 2026.
-- Agent: ceo kpi-to-order builder. Never applied: it ALWAYS raises CHK<<...>>, which rolls back every row it writes, the
-- real KPI orders the duty would give included. Its subject is a ZZ DEMO month target for marketing in the current Dubai
-- month (metric zz_demo_probe_kpi). It sends nothing: it asserts the notifications count does not move.
--   A: the ZZ DEMO KPI reads behind -> one directive to marketing (target_miss, seat_kpi:...) and one decision-log row.
--   B: a second run the same day -> no new directive and no new decision-log row (once per KPI per day).
--   C: the KPI turns met -> fn_ceo_directive_issue's own done-condition reads true for the order.
--   D: the run left exactly 0 ZZ DEMO rows behind once the CHK rolls it back (asserted by the caller re-reading).
-- Run on the LOCAL database (node scripts/db/local_pg16.mjs start): psql -f <this file>; read PROBE OK in the CHK.
do $probe$
declare r1 jsonb; r2 jsonb; n_notif bigint; n_notif_after bigint; v_ref text; v_kpi text := 'month_target:marketing:zz_demo_probe_kpi';
  n_dir_1 int; n_dir_2 int; n_log_1 int; n_log_2 int; v_dir_seat text; v_dir_status text; v_done boolean; v_done_sql text;
  v_behind_seen boolean; v_month date := date_trunc('month', (now() at time zone 'Asia/Dubai'))::date;
begin
  select count(*) into n_notif from public.notifications;
  insert into public.ceo_seat_month_target (month, seat, metric, target, measured, status, basis, checked_at)
  values (v_month, 'marketing', 'zz_demo_probe_kpi', 10, 1, 'behind', 'ZZ DEMO probe target', now());
  select behind into v_behind_seen from public.seat_kpi where kpi = v_kpi;
  v_ref := 'seat_kpi:' || v_kpi || ':' || to_char(now() at time zone 'Asia/Dubai', 'YYYY-MM');

  r1 := public.fn_ceo_kpi_behind_becomes_an_order();                                                  -- A
  select count(*) into n_dir_1 from public.ceo_directive where source_ref = v_ref;
  select count(*) into n_log_1 from public.ceo_decision_log where dedupe_key like 'seat_directive:kpi:' || v_kpi || ':%';
  select seat, status, done_sql into v_dir_seat, v_dir_status, v_done_sql from public.ceo_directive where source_ref = v_ref order by id desc limit 1;

  r2 := public.fn_ceo_kpi_behind_becomes_an_order();                                                  -- B
  select count(*) into n_dir_2 from public.ceo_directive where source_ref = v_ref;
  select count(*) into n_log_2 from public.ceo_decision_log where dedupe_key like 'seat_directive:kpi:' || v_kpi || ':%';

  update public.ceo_seat_month_target set measured = 10, status = 'met'                               -- C
   where month = v_month and seat = 'marketing' and metric = 'zz_demo_probe_kpi';
  execute 'select coalesce((' || v_done_sql || ')::boolean, false)' into v_done;
  select count(*) into n_notif_after from public.notifications;

  raise exception 'CHK<<run1=% run2=% behind_seen=% directives_after_1=% directives_after_2=% log_after_1=% log_after_2=% seat=% status=% done_once_met=% notifications_delta=% verdict=%>>',
    r1, r2, v_behind_seen, n_dir_1, n_dir_2, n_log_1, n_log_2, v_dir_seat, v_dir_status, v_done, n_notif_after - n_notif,
    case when v_behind_seen and n_dir_1 = 1 and n_dir_2 = 1 and n_log_1 = 1 and n_log_2 = 1 and v_dir_seat = 'marketing'
              and v_dir_status = 'open' and v_done and n_notif_after = n_notif and (r2->>'already_decided_today')::int >= 1
         then 'PROBE OK' else 'PROBE FAILED' end;
end $probe$;
