-- TWO MORE FENCED SEAT DUTIES KEEP THEIR FIXTURE SWITCH.
--
-- Agent: it_engineer (the fence of #1348 is its own); the duties stay their seats' (sales_engineer:
-- fn_sales_engineer_comparison_kpi; customer_support: fn_support_case_idle_close). 18 Oct 2026.
--
-- #1348 (demo_data_is_purged_by_its_marker_and_no_seat_duty_reads_it.sql, founder ruling 1199) put an unconditional
-- "not <demo>" on six seat duties. #1418 (a_fenced_seat_duty_keeps_its_fixture_switch.sql) gave four of them the
-- estate's fixture switch; these are the remaining two. Without it an aborted ZZ DEMO probe -- the only kind the
-- sandbox rule allows -- can prove nothing about them: the duty skips exactly the rows the probe builds.
-- MEASURED (production htdblwldjkcgjvmqkbeh, read-only, 18 Oct 2026): both bodies below were taken from the canonical
-- file (#1348, MANIFEST line 2022) and equalled production's prosrc byte for byte before this edit.
--
-- WHAT THIS DOES: each "not <predicate>" becomes "<predicate> = <switch>", the switch being qd.duty_fixtures = 'on'
-- (set local, only inside a probe). Fixture run: ONLY demo rows; every real run and cron: ONLY real ones.
-- fn_support_case_idle_close's UPDATE is fenced by the same predicate, so a fixture run can never close a real case.
-- Nothing else in either body changes. CREATE OR REPLACE keeps each routine's ACL (both revoked when first created).
-- Prevented by: scripts/checks/two_more_fenced_seat_duties_keep_their_fixture_switch.test.mjs,
-- scripts/checks/no_seat_duty_reads_demo_rows.test.mjs.
--   node scripts/apply_sql.mjs scripts/sql/two_more_fenced_seat_duties_keep_their_fixture_switch.sql --apply --ddl --seat it_engineer


CREATE OR REPLACE FUNCTION public.fn_sales_engineer_comparison_kpi(p_days integer DEFAULT 7)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
with rep as (
  select c.inquiry_id, min(c.created_at) as reported_at
    from public.qd_compare_cache c
   where not (c.analysis ? '__failed')
     -- fixture run (qd.duty_fixtures = 'on'): ONLY demo requests; every real run: ONLY real ones
     and exists (select 1 from public.inquiries di where di.id::text = c.inquiry_id and public.fn_inquiry_is_demo(di.id))
         = (coalesce(current_setting('qd.duty_fixtures', true), '') = 'on')
     and c.created_at >= now() - make_interval(days => greatest(1, p_days))
   group by c.inquiry_id
),
q as (
  select r.inquiry_id,
         count(*) filter (where coalesce(qt.price_ex_vat, qt.quote_amount) is not null
                            and nullif(btrim(qt.lead_time), '') is not null
                            and nullif(btrim(qt.validity), '') is not null
                            and nullif(btrim(qt.warranty), '') is not null
                            and nullif(btrim(qt.payment_terms), '') is not null) as complete_n,
         count(*) filter (where nullif(btrim(qt.exclusions), '') is not null) as excl_n
    from rep r
    left join public.quotes qt on qt.inquiry_id::text = r.inquiry_id
   group by r.inquiry_id
),
t as (
  select r.inquiry_id, extract(epoch from (r.reported_at - i.created_at)) / 3600.0 as hours,
         q.complete_n, q.excl_n
    from rep r
    join q on q.inquiry_id = r.inquiry_id
    left join public.inquiries i on i.id::text = r.inquiry_id
)
select jsonb_build_object(
  'window_days', greatest(1, p_days),
  'reports', count(*),
  'hours_median', round((percentile_cont(0.5) within group (order by hours))::numeric, 1),
  'hours_p90', round((percentile_cont(0.9) within group (order by hours))::numeric, 1),
  'share_3plus_complete', case when count(*) > 0 then round(count(*) filter (where complete_n >= 3)::numeric / count(*), 3) end,
  'reports_with_exclusions', count(*) filter (where excl_n > 0),
  'quotes_with_exclusions', coalesce(sum(excl_n), 0))
from t;
$function$;

create or replace function public.fn_support_case_idle_close()
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
declare v_fx boolean := coalesce(current_setting('qd.duty_fixtures', true), '') = 'on';   -- fixture run: ONLY demo cases
  v_days int := greatest(1, public.fn_seat_clock_policy('support_case_append_days', 7)::int); n int;
begin
  update public.support_case
     set state = 'closed', closed_at = now(),
         close_reason = 'resolved — answered, and no reply from the customer in ' || v_days || ' days (closed by customer_support)'
   where state = 'waiting_customer' and last_activity_at < now() - make_interval(days => v_days)
     and public.fn_party_is_demo(party_kind, party_id) = v_fx;   -- a fixture run can never close a real case
  get diagnostics n = row_count;
  return jsonb_build_object('closed', n);
end $function$;

-- verdict: both live bodies carry the switch (read back from the catalog inside the apply's own transaction)
select case when (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                   where n.nspname = 'public' and p.proname in ('fn_sales_engineer_comparison_kpi', 'fn_support_case_idle_close')
                     and p.prosrc like '%qd.duty_fixtures%') = 2
            then 'PROBE OK' else 'PROBE FAILED: a duty lacks the qd.duty_fixtures switch' end as verdict;
