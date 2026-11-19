-- A SEAT KPI BEHIND ITS TARGET BECOMES A CEO DECISION AND AN ORDER TO THE SEAT THAT OWNS IT.     seat: ceo · 19 Nov 2026
-- Assigned: ceo
-- Agent: ceo kpi-to-order builder
--
-- Founder, ledger 1705: the company must run itself like a real company: the CEO plans and orders, every seat has
-- real-job KPIs, IT fixes rather than reports.
--
-- MEASURED BEFORE WRITING (production htdblwldjkcgjvmqkbeh, read-only SELECTs, 19 Nov 2026 ~16:20Z):
--   * public.ceo_decision is the CEO's RULE REGISTER (primary key decision_key), not a log: 17 rules, all active, the
--     last added 2 Nov 2026. "0 rows in 7 days" there is the register standing still, not the CEO standing still.
--     The decisions themselves are public.ceo_decision_log: 349 rows, 74 in 7 days, 16 in 48 h, the last at
--     2026-11-19 03:30Z (supplier_growth 22, directive_escalation 29, paid_inference 7, seat_directive 6, ...).
--   * public.ceo_directive (the CEO's order to a seat, fn_ceo_directive_issue): 86 issued in 7 days, the last
--     2026-11-19 02:49Z. Statuses over all time: missed 120, escalated 47, open 35, withdrawn 34, met 25, paused 6.
--   * public.ceo_seat_month_target, November: sales_engineer invitations_sent 82 of 750 'behind', sales_engineer
--     suppliers_verified 2 of 768 'behind', ceo trades_open 0 of 77 'behind' (checked 16 Nov 23:23Z). NONE of the
--     three has a directive: the 7 target_miss directives of the week come from the year-one plan
--     (fn_ceo_directive_run step 1) and from the supplier-growth rules, never from this table. A seat KPI could read
--     behind for the whole month and nobody was ordered to move it.
--   * public.ceo_supplier_goal suppliers_registered_2026: 300-400 by 31 Dec 2026 (ledger 1436), set 2 Nov. Real leads
--     with registration_submitted_at set: 3. The straight path from 0 on 2 Nov reads 86 on 19 Nov.
--   * public.employee_kpi: 0 rows ever. It has no direction column (is higher better?), so it is not read here; a
--     seat KPI belongs in ceo_seat_month_target, which carries a status its owner measures.
--   * app_secrets.ceo_growth_act_golive = 'false', unchanged since 2026-11-02 05:33Z (seeded off by
--     the_ceo_holds_the_supplier_target_and_acts_within_bounded_powers.sql, ledger 1438). Since 10 Nov the
--     safety-side powers apply without it (the_ceo_applies_its_safety_side_growth_powers_without_waiting_for_a_switch
--     .sql); 15 growth actions applied since. Nothing here reads or changes that switch.
--
-- WHAT THIS FILE CHANGES
--   1. public.seat_kpi (view): one row per KPI -- kpi, owner_seat, measured, target, behind, as_of, source, basis --
--      read from the tables that already hold them: every ceo_seat_month_target row of the current Dubai month, and
--      the supplier-registration goal on its straight path (real leads only: not is_demo).
--   2. fn_ceo_kpi_behind_becomes_an_order(): for every seat_kpi row that is behind, once per KPI per Dubai day:
--        - an order to the owning seat through the existing fn_ceo_directive_issue (source_kind 'target_miss',
--          source_ref 'seat_kpi:<kpi>:<YYYY-MM>', 7-day deadline, done when the KPI no longer reads behind). That
--          routine already refuses a second live order for the same signal and an order whose condition holds, and
--          fn_ceo_directive_review re-issues a missed one: nothing new is invented for escalation;
--        - a ceo_decision_log row under the existing rule seat_directive (dedupe 'seat_directive:kpi:<kpi>:<day>'),
--          naming the reading and the order it gave or the order that already stands.
--      The register's seat_directive trigger is widened to say so. No new rule key, so fn_ceo_decisions_evaluate
--      (which names seat_directive as decided elsewhere) is untouched.
--   3. Duty ceo.kpi_orders, hourly.
--
-- WHAT THIS DOES NOT CHANGE: ceo_growth_act_golive (founder-gated; not read, not written); who measures
-- ceo_seat_month_target (its readings are as fresh as its own checker leaves them, as_of says when); the year-one-plan
-- directives of fn_ceo_directive_run; employee_kpi.
--
-- Prevented by: scripts/checks/the_ceo_decided_something_in_the_last_48_hours.test.mjs (live: a ceo_decision_log row in
--   48 h, and every behind seat_kpi has a live order) and this file's _probe.sql (ZZ DEMO, rolled back).
-- Rehearse locally: node scripts/db/local_pg16.mjs start, then psql this file and its _probe.sql (PROBE OK).
-- Apply at merge: node scripts/apply_sql.mjs scripts/sql/a_seat_kpi_behind_its_target_becomes_a_ceo_decision_and_an_order.sql --apply --ddl --seat ceo
-- Rollback: delete from public.seat_duty where duty = 'ceo.kpi_orders';
--           drop function public.fn_ceo_kpi_behind_becomes_an_order(); drop view public.seat_kpi;
--           (orders already issued stay, and close on their own condition.)

set local lock_timeout = '5s';

-- 1. THE KPI VIEW -----------------------------------------------------------------------------------------------------
create or replace view public.seat_kpi with (security_invoker = true) as
  select 'month_target:' || t.seat || ':' || t.metric as kpi,
         t.seat as owner_seat,
         t.measured,
         t.target,
         (t.status = 'behind') as behind,
         coalesce(t.checked_at, (t.month::timestamp at time zone 'Asia/Dubai')) as as_of,
         'ceo_seat_month_target' as source,
         format('%s target for %s: %s', t.metric, to_char(t.month, 'FMMonth YYYY'), t.basis) as basis
    from public.ceo_seat_month_target t
   where t.month = date_trunc('month', (now() at time zone 'Asia/Dubai'))::date
  union all
  select 'supplier_goal:' || g.goal,
         'marketing',            -- the year-one plan gives registrations_submitted to marketing (directive #2679)
         (select count(*) from public.leads l where l.registration_submitted_at is not null and not coalesce(l.is_demo, false))::numeric,
         floor(g.target_low * least(1, greatest(0, ((now() at time zone 'Asia/Dubai')::date - (g.set_at at time zone 'Asia/Dubai')::date)::numeric
                                      / greatest(1, g.due_on - (g.set_at at time zone 'Asia/Dubai')::date)))),
         (select count(*) from public.leads l where l.registration_submitted_at is not null and not coalesce(l.is_demo, false))
           < floor(g.target_low * least(1, greatest(0, ((now() at time zone 'Asia/Dubai')::date - (g.set_at at time zone 'Asia/Dubai')::date)::numeric
                                      / greatest(1, g.due_on - (g.set_at at time zone 'Asia/Dubai')::date)))),
         now(),
         'ceo_supplier_goal',
         format('%s-%s by %s on a straight path from %s (%s); counts %s', g.target_low, g.target_high, g.due_on,
                (g.set_at at time zone 'Asia/Dubai')::date, g.ruling, g.counts_as)
    from public.ceo_supplier_goal g
   where g.due_on >= (now() at time zone 'Asia/Dubai')::date;

revoke all on public.seat_kpi from public, anon, authenticated;
comment on view public.seat_kpi is
  'One row per seat KPI: measured, target, behind, owner seat, as_of. Fed by ceo_seat_month_target (current Dubai month) and ceo_supplier_goal (straight path, real leads). Read by fn_ceo_kpi_behind_becomes_an_order. 19 Nov 2026, ledger 1705.';

-- 2. THE CEO DUTY: A KPI BEHIND BECOMES A DECISION AND AN ORDER -------------------------------------------------------
create or replace function public.fn_ceo_kpi_behind_becomes_an_order()
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  k record; v_day date := (now() at time zone 'Asia/Dubai')::date; v_month text := to_char(now() at time zone 'Asia/Dubai', 'YYYY-MM');
  v_ref text; v_dedupe text; v_new bigint; v_live record; v_decision text;
  n_behind int := 0; n_ordered int := 0; n_standing int := 0; n_decided int := 0; n_seen_today int := 0; n_no_seat int := 0;
begin
  for k in select * from public.seat_kpi where behind order by owner_seat, kpi loop
    n_behind := n_behind + 1;
    v_dedupe := 'seat_directive:kpi:' || k.kpi || ':' || v_day;
    if exists (select 1 from public.ceo_decision_log where dedupe_key = v_dedupe) then
      n_seen_today := n_seen_today + 1;
      continue;                                   -- once per KPI per Dubai day
    end if;
    v_ref := 'seat_kpi:' || k.kpi || ':' || v_month;
    v_new := public.fn_ceo_directive_issue(k.owner_seat, 'target_miss', v_ref,
      format('Bring %s back to its target: it reads %s against %s (as of %s). Name the step that is not converting, change that step, and say what you changed.',
             k.kpi, coalesce(k.measured::text, 'nothing measured'), k.target, to_char(k.as_of at time zone 'Asia/Dubai', 'DD Mon HH24:MI')),
      format('seat_kpi %s no longer reads behind its target.', k.kpi),
      format('coalesce((select not s.behind from public.seat_kpi s where s.kpi = %L), true)', k.kpi),
      now() + interval '7 days',
      jsonb_build_object('kpi', k.kpi, 'measured', k.measured, 'target', k.target, 'as_of', k.as_of, 'source', k.source, 'basis', k.basis));
    select d.id, d.status, d.deadline into v_live from public.ceo_directive d
     where d.seat = k.owner_seat and d.source_kind = 'target_miss' and d.source_ref = v_ref and d.status <> 'met'
     order by d.id desc limit 1;
    if v_new is not null then
      n_ordered := n_ordered + 1;
      v_decision := format('%s is behind: %s against %s. Ordered %s to move it by %s (directive #%s).', k.kpi,
                           coalesce(k.measured::text, 'nothing measured'), k.target, k.owner_seat,
                           to_char((now() + interval '7 days') at time zone 'Asia/Dubai', 'DD Mon'), v_new);
    elsif v_live.id is not null then
      n_standing := n_standing + 1;
      v_decision := format('%s is still behind: %s against %s. The order to %s stands (directive #%s, %s, due %s).', k.kpi,
                           coalesce(k.measured::text, 'nothing measured'), k.target, k.owner_seat, v_live.id, v_live.status,
                           to_char(v_live.deadline at time zone 'Asia/Dubai', 'DD Mon'));
    else
      n_no_seat := n_no_seat + 1;                 -- the seat is not active, or the done-condition already holds
      v_decision := format('%s reads behind (%s against %s) but no order could be given to %s: the seat is not active or the condition already holds.',
                           k.kpi, coalesce(k.measured::text, 'nothing measured'), k.target, k.owner_seat);
    end if;
    insert into public.ceo_decision_log (decision_key, the_decision, evidence, reading_before, dedupe_key)
    values ('seat_directive', v_decision,
            jsonb_build_object('kpi', k.kpi, 'owner_seat', k.owner_seat, 'measured', k.measured, 'target', k.target,
                               'as_of', k.as_of, 'source', k.source, 'basis', k.basis, 'directive_id', coalesce(v_new, v_live.id),
                               'new_order', v_new is not null, 'by', 'fn_ceo_kpi_behind_becomes_an_order'),
            format('%s %s / %s', k.kpi, coalesce(k.measured::text, 'null'), k.target), v_dedupe)
    on conflict (dedupe_key) where dedupe_key is not null do nothing;
    n_decided := n_decided + 1;
    v_live := null;
  end loop;
  return jsonb_build_object('day', v_day, 'kpis', (select count(*) from public.seat_kpi), 'behind', n_behind,
    'ordered', n_ordered, 'order_standing', n_standing, 'not_orderable', n_no_seat, 'decided', n_decided,
    'already_decided_today', n_seen_today);
end $fn$;

revoke execute on function public.fn_ceo_kpi_behind_becomes_an_order() from public, anon, authenticated;

-- 3. THE REGISTER SAYS WHAT NOW TRIGGERS seat_directive ----------------------------------------------------------------
update public.ceo_decision
   set trigger_condition = 'The day''s plan names a binding stage a seat can move and no directive for it is open; or an open directive is met or past its deadline; or a seat_kpi row reads behind its target (fn_ceo_kpi_behind_becomes_an_order, once per KPI per Dubai day, 19 Nov 2026).'
 where decision_key = 'seat_directive' and trigger_condition not like '%seat_kpi%';

-- 4. THE DUTY -----------------------------------------------------------------------------------------------------------
insert into public.seat_duty (duty, owner_seat, every, routine, what, owner_file) values
  ('ceo.kpi_orders', 'ceo', interval '1 hour', 'fn_ceo_kpi_behind_becomes_an_order',
   'Every seat KPI in seat_kpi that reads behind its target becomes, once per KPI per Dubai day, a CEO decision (ceo_decision_log, rule seat_directive) and an order to the owning seat (ceo_directive target_miss, 7 days, closes when the KPI is no longer behind). Ledger 1705.',
   'scripts/sql/a_seat_kpi_behind_its_target_becomes_a_ceo_decision_and_an_order.sql')
on conflict (duty) do update set every = excluded.every, routine = excluded.routine, what = excluded.what, owner_file = excluded.owner_file;

-- VERDICT (read-only) -------------------------------------------------------------------------------------------------
select case when problems is null then 'PROBE OK' else 'PROBE FAILED: ' || problems end as verdict from (
  select string_agg(p, '; ') problems from (
    select 'the view is missing' p where to_regclass('public.seat_kpi') is null
    union all select 'the duty is not registered' where not exists (select 1 from public.seat_duty where duty = 'ceo.kpi_orders' and enabled)
    union all select 'the routine is executable by a client role'
     where has_function_privilege('anon', 'public.fn_ceo_kpi_behind_becomes_an_order()', 'execute')
        or has_function_privilege('authenticated', 'public.fn_ceo_kpi_behind_becomes_an_order()', 'execute')
    union all select 'the view is readable by a client role'
     where has_table_privilege('anon', 'public.seat_kpi', 'select') or has_table_privilege('authenticated', 'public.seat_kpi', 'select')
  ) z) y;
