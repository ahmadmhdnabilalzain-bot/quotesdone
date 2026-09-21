-- PROBE: a bounce report is proven to arrive every day, or it is a finding (21 Sep 2026, customer_support).
--
-- Pure read. No DDL, no writes. Run AFTER a_bounce_report_is_proven_to_arrive_every_day_or_it_is_a_finding.sql
-- is applied and resilience_ping is deployed. Returns ONE verdict row: 'PROBE OK …' or 'PROBE FAILED: <reasons>'.
-- Before the change file is applied it answers PROBE FAILED (no routine, no schedule row).
-- The judging logic itself was rehearsed rolled-back on 21 Sep 2026 (queue -> silence raises the finding ->
-- next day's arrival closes it and leaves no canary suppression): PROBE OK.
with f as (
  select unnest(array[
    case when to_regprocedure('public.fn_delivery_feedback_canary_tick()') is null then 'fn_delivery_feedback_canary_tick() does not exist' end,
    case when exists (select 1 from pg_proc p where p.oid = to_regprocedure('public.fn_delivery_feedback_canary_tick()')
                       and (has_function_privilege('anon', p.oid, 'execute') or has_function_privilege('authenticated', p.oid, 'execute')
                            or not coalesce(array_to_string(p.proconfig, ',') like '%search_path%', false)))
         then 'the canary routine is callable by anon/authenticated or has no pinned search_path' end,
    case when not exists (select 1 from public.resilience_step where step = 'deliveryCanary' and every <= interval '1 hour')
         then 'the heartbeat does not schedule deliveryCanary' end,
    -- once it has run for a day while mail was going out, a canary must exist and the newest judged one must have arrived
    case when exists (select 1 from public.resilience_step where step = 'deliveryCanary' and last_ok_at < now() - interval '1 day')
          and exists (select 1 from public.notifications where status = 'sent' and sent_at > now() - interval '24 hours'
                       and type <> 'delivery_feedback_canary')
          and not exists (select 1 from public.notifications where type = 'delivery_feedback_canary' and created_at > now() - interval '26 hours')
         then 'mail went out in the last day and no canary was queued' end,
    case when (select last_error from public.notifications where type = 'delivery_feedback_canary' and last_error like 'canary verdict:%'
                order by id desc limit 1) like 'canary verdict: NO%'
         then 'the newest judged canary bounce never reached resend_webhook' end
  ]) why
)
select case when count(why) = 0
            then 'PROBE OK: canary scheduled; newest verdict: ' || coalesce((select last_error from public.notifications
                   where type = 'delivery_feedback_canary' and last_error is not null order by id desc limit 1), 'none yet')
            else 'PROBE FAILED: ' || string_agg(why, '; ') end as verdict
  from f;
