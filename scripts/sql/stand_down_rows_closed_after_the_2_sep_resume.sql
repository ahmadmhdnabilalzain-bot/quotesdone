-- THE STAND-DOWN THE FOUNDER LIFTED WAS STILL OPEN IN THE TABLE EIGHT ROUTINES READ.
--
-- Measured 3 Sep 2026 on production: company_stand_down rows 1-4 (16 Aug) carry resumed_at = null.
-- Rows 5 and 6 record the founder's 2 Sep order — "lift all previous limits or frozen gates; the
-- only thing that remains blocked is OpenRouter" — but they were written as already-closed markers
-- (stood_down_at = resumed_at) and never closed the four open rows. Every reader tests
-- `exists (select 1 from company_stand_down where resumed_at is null)` or takes the newest open
-- row, so fn_org_task_sla_watch, fn_handoff_watchdog, fn_objective_review, fn_promotion_review,
-- fn_outcome_evaluate, fn_action_queue_consequential_sweep, fn_phase_d_gate_evaluate and
-- fn_reputation_recompute all still returned PAUSED_BY_FOUNDER_STANDDOWN on every tick, eighteen
-- days after the hold ended. Three of them run on active crons (objective_review_weekly,
-- org_task_sla_watch_daily, handoff_watchdog_6h) and have been no-ops since.
--
-- The rows are closed at apply time — not back-dated to 2 Sep — and the reason says why. The SLA
-- watch's founder-page path was measured before this was written: 0 corrective tasks are past
-- their SLA today, so closing the hold pages nobody.
--
-- fn_reputation_hold_state was a kernel board built for the hold: it was green only while the
-- reputation cron was INACTIVE. With no hold open that expectation is inverted — the machinery is
-- supposed to run — so the board now states the expectation for both states and reads it back.
--
--   node scripts/apply_sql.mjs scripts/sql/stand_down_rows_closed_after_the_2_sep_resume.sql --apply --ddl

update public.company_stand_down
   set resumed_at = now(),
       reason = reason || E'\n\nCLOSED ' || to_char(now(), 'YYYY-MM-DD HH24:MI') || ' UTC: the founder lifted every '
             || 'hold on 2 Sep 2026 (rows 5 and 6 record the order). Those rows were written as '
             || 'already-closed markers and left this one open, so the eight routines that read '
             || 'company_stand_down kept returning PAUSED_BY_FOUNDER_STANDDOWN. Closed at apply time, '
             || 'not back-dated.'
 where resumed_at is null
   and stood_down_at < '2026-09-01';

create or replace function public.fn_reputation_hold_state()
 returns table(check_name text, expected text, actual text, ok boolean)
 language sql
 stable security definer
 set search_path to 'public', 'pg_temp'
as $function$
  with hold as (
    select id, stood_down_at, resumed_at from public.company_stand_down
     where resumed_at is null order by stood_down_at desc limit 1
  ), snap as (
    select max(computed_at) as computed_at, count(*) as n from public.agent_reputation
  )
  select 'scorer_status',
         'PAUSED_BY_FOUNDER_STANDDOWN while a hold is open; MEASURING otherwise',
         case when (select id from hold) is not null
              then 'PAUSED_BY_FOUNDER_STANDDOWN since ' || (select stood_down_at::text from hold)
              else 'MEASURING -- no open stand-down' end,
         true
  union all
  select 'snapshot_disposition',
         'STALE_DUE_TO_FOUNDER_STANDDOWN while the hold is open; scored inside 14 days otherwise',
         case when (select id from hold) is not null
                   and (select computed_at from snap) < (select stood_down_at from hold)
              then 'STALE_DUE_TO_FOUNDER_STANDDOWN: ' || (select n from snap)::text
                   || ' employee(s) last scored ' || (select computed_at::text from snap)
              else 'last scored ' || coalesce((select computed_at::text from snap), '(never)')
                   || ' over ' || (select n from snap)::text || ' employee(s)' end,
         (select id from hold) is not null
           or coalesce((select computed_at from snap) > now() - interval '14 days', false)
  union all
  -- NOT informational. If the routine can still move authority while a hold is open, the policy
  -- is prose and not a mechanism, and this row is how that is caught.
  select 'stale_snapshot_may_not_move_authority', '0 authority changes are possible while held',
         case when (select id from hold) is null then 'no hold is open; the guard is not engaged'
              else 'fn_reputation_recompute returns PAUSED_BY_FOUNDER_STANDDOWN and writes no row to '
                || 'agent_reputation, employee_authority or autonomy_control_audit' end,
         (select id from hold) is null
           or position('PAUSED_BY_FOUNDER_STANDDOWN' in
                (select p.prosrc from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                  where n.nspname = 'public' and p.proname = 'fn_reputation_recompute')) > 0
  union all
  -- The cron is the mechanism: it must be OFF while a hold is open and ON when none is.
  select 'reputation_weekly_matches_hold_state',
         case when (select id from hold) is not null then 'inactive while a hold is open' else 'active while no hold is open' end,
         coalesce((select 'active=' || active::text from cron.job where jobname = 'reputation_weekly'), '(no such job)'),
         coalesce((select case when (select id from hold) is not null then not active else active end
                     from cron.job where jobname = 'reputation_weekly'), false)
  union all
  select 'outcome_evaluate_daily_matches_hold_state',
         case when (select id from hold) is not null then 'inactive while a hold is open' else 'any state while no hold is open' end,
         coalesce((select 'active=' || active::text from cron.job where jobname = 'outcome_evaluate_daily'), '(no such job)'),
         coalesce((select case when (select id from hold) is not null then not active else true end
                     from cron.job where jobname = 'outcome_evaluate_daily'), true);
$function$;
