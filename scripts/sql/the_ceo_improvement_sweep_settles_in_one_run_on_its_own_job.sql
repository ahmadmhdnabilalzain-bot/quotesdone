-- THE CEO IMPROVEMENT SWEEP SETTLES IN ONE RUN ON ITS OWN JOB (27 Oct 2026). Assigned: ceo.
--
-- MEASURED (production, 27 Oct 2026, read-only and rolled back):
--   * seat_duty ceo.improvement: every 7 days, own_job true (its own pg_cron job seat_duty:ceo.improvement, 60 s
--     statement_timeout), avg_ms 5 570. last_result of 25 Oct: {"passes": 1, "proposed": 8, "closed": 18, "open": 80,
--     "stopped_at_budget": true}. The sweep stops itself at 2 s, so a weekly run never reaches the pass that changes
--     nothing: what it left waits a week, and the next week brings more.
--   * Two calls of the live body in one rolled-back transaction: {proposed 21, closed 9, stopped_at_budget true} in
--     2.0 s, then {proposed 14, closed 5, stopped_at_budget true} in 2.1 s - it does not settle, which is the property
--     the_ceo_improvement_sweep_closes_before_it_proposes_and_settles_in_one_run.sql (30 Sep 2026) exists for.
--   * The same two calls with a 30 s budget: {proposed 82, closed 53, passes 10 (the old pass bound, so not settled)} in 12.1 s;
--     with the bound at 50 as well: settled on pass 11 (the pass that changes nothing), then a second run proposes 0.
--
-- WHY: one_slow_duty_never_wedges_the_seat_duty_tick.sql (18 Oct 2026) put the 2 s bound in because the sweep ran
-- inside the shared seat duty tick (8 s statement_timeout), and in the same file moved the sweep onto its own job,
-- where that reason no longer holds. The tick never runs an own_job duty, and a duty whose avg_ms grows past 1 s is
-- moved onto its own job by fn_seat_duty_run, so a longer budget cannot reach the tick.
--
-- WHAT THIS CHANGES: fn_ceo_improvement_sweep's budget is 30 s (inside the job's 60 s), and its pass bound 50 (was 10).
-- Nothing else in the body changes. CREATE OR REPLACE keeps the existing ACL (revoked from PUBLIC, anon,
-- authenticated); search_path stays pinned.
--
-- Prevented by: scripts/checks/the_ceo_year_one_plan_follows_the_founder_targets.test.mjs ("a second sweep proposed
-- more", and the_ceo_improvement_sweep_closes_before_it_proposes_and_settles_in_one_run_probe.sql), both red against
-- the 2 s body on 27 Oct 2026 (second sweep proposed 14) and green with this file replayed first.
-- Apply at merge:  node scripts/apply_sql.mjs scripts/sql/the_ceo_improvement_sweep_settles_in_one_run_on_its_own_job.sql --apply --ddl

create or replace function public.fn_ceo_improvement_sweep()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp'
as $function$
declare r record; n_new int := 0; n_done int := 0; c_id bigint; v bigint; v_ans timestamptz;
  v_pass int := 0; v_before int; v_t0 timestamptz := clock_timestamp();
begin
  select id into c_id from public.target_contract where contract_key = 'FOUNDER_TARGETS_YEAR_ONE_TO_2027_09_30' and status = 'active';

  -- Close, then propose, and repeat until a pass changes nothing. Closing one improvement completes its handoff,
  -- which can finalise the cases another lesson waits on, and frees a capped slot; a single close-then-propose
  -- still left 11 closes and 11 proposals for the next run (measured 30 Sep 2026). The last pass is the proof.
  -- ponytail: 50 passes and 30 s bound the loop. It runs only on its own pg_cron job seat_duty:ceo.improvement, under
  -- that job's 60 s statement_timeout; the 2 s it had was sized for the shared 8 s tick it no longer runs in, and left
  -- a weekly sweep that never settled (25 Oct 2026: passes 1, stopped_at_budget true). Measured 27 Oct 2026, rolled
  -- back: 10 passes hit the old bound unsettled in 12.1 s; with 50 it settles on pass 11 and a second run proposes 0.
  -- What is left past 30 s finishes on the next run,
  -- every step being idempotent.
  loop
  v_pass := v_pass + 1;
  v_before := n_new + n_done;

  -- 1. CLOSE FIRST. Tracked to done: the CEO is the originator, re-verifies, and is the one who closes.
  for r in select i.*, coalesce(i.evidence->>'lesson',
                                (select m.lessons[1] from public.seat_case_memory m where m.id = (i.evidence->>'case_memory_id')::bigint)) as lesson
             from public.ceo_improvement i where i.status in ('open', 'assigned') loop
    exit when clock_timestamp() - v_t0 > interval '30 seconds';
    if r.source_kind in ('recurring_miss', 'month_miss')
       and (select count(*) filter (where d.status in ('on_track', 'within_tolerance')) = 7 and count(*) = 7
              from public.target_daily_verdict d where d.contract_id = c_id and d.metric_key = r.evidence->>'metric'
               and d.day > current_date - 7 and d.day > r.created_at::date) then
      perform public.fn_ceo_improvement_close(r.id, format('%s back on its path for 7 days running (%s).', r.evidence->>'metric', current_date));
      n_done := n_done + 1;
    elsif r.source_kind = 'recurring_finding'
       and exists (select 1 from public.it_engineer_finding f where f.issue_key = r.source_ref and f.closed_at is not null) then
      perform public.fn_ceo_improvement_close(r.id, format('Finding %s closed.', r.source_ref));
      n_done := n_done + 1;
    elsif r.source_kind = 'lesson' and r.lesson is not null then
      -- answered = the seat replied on the handoff (or there was no handoff: the CEO's own lesson)
      select coalesce((a.detail->>'replied_at')::timestamptz, a.decided_at) into v_ans
        from public.agent_actions a where a.id = r.handoff_id;
      if r.handoff_id is null then v_ans := r.created_at; end if;
      if v_ans is not null
         and not exists (select 1 from public.seat_case_memory m
                          where m.seat = r.seat and m.case_kind = r.evidence->>'case_kind' and m.lessons[1] = r.lesson
                            and (not coalesce(m.finalised, false) or m.opened_at > v_ans)) then
        perform public.fn_ceo_improvement_close(r.id, format('Re-verified by the CEO: every %s case of %s carrying this lesson is finalised and none has opened since the answer (%s).',
                                                             r.evidence->>'case_kind', r.seat, v_ans));
        n_done := n_done + 1;
      end if;
    end if;
  end loop;

  -- 2. THEN PROPOSE. A metric behind its path on 7 or more of the last 14 days, not recovered (the last 7 days all
  -- on path), and with no improvement already open for it: the plan for it is not working.
  for r in select d.metric_key, d.owner_seat, count(*) filter (where d.status = 'miss') as misses,
                  min(d.actual) filter (where d.status = 'miss') as low, max(d.expected) as expected
             from public.target_daily_verdict d
            where d.contract_id = c_id and d.day > current_date - 14
            group by 1, 2
           having count(*) filter (where d.status = 'miss') >= 7
              and not (count(*) filter (where d.day > current_date - 7 and d.status in ('on_track', 'within_tolerance')) = 7
                       and count(*) filter (where d.day > current_date - 7) = 7) loop
    exit when clock_timestamp() - v_t0 > interval '30 seconds';
    continue when exists (select 1 from public.ceo_improvement i where i.source_kind = 'recurring_miss'
                             and i.status in ('open', 'assigned') and i.evidence->>'metric' = r.metric_key);
    v := public.fn_ceo_improvement_open('recurring_miss', r.metric_key || ':' || to_char(current_date, 'YYYY-MM'), r.owner_seat,
      format('%s has been behind its path on %s of the last 14 days. Change how the seat moves it, not the target: name the step that is not converting and fix that step.', r.metric_key, r.misses),
      jsonb_build_object('metric', r.metric_key, 'misses_14d', r.misses, 'lowest_actual', r.low, 'expected', r.expected));
    n_new := n_new + (v is not null)::int;
  end loop;

  -- a lesson a seat wrote down in the last 30 days becomes ONE change to its routine: keyed on the
  -- lesson, not on the case, so the tenth case with the same lesson finds the first improvement.
  for r in select m.seat, m.case_kind, m.lessons[1] as lesson, max(m.id) as last_case, count(*) as cases
             from public.seat_case_memory m
            where cardinality(m.lessons) > 0 and coalesce(m.updated_at, m.opened_at) > now() - interval '30 days'
              and exists (select 1 from public.org_role o where o.role_id = m.seat and o.status = 'active')
            group by 1, 2, 3 loop
    exit when clock_timestamp() - v_t0 > interval '30 seconds';
    v := public.fn_ceo_improvement_open('lesson', 'lesson:' || r.seat || ':' || md5(r.case_kind || '|' || r.lesson), r.seat,
      format('Make this lesson part of the routine, so the same case does not come back: %s', r.lesson),
      jsonb_build_object('case_memory_id', r.last_case, 'case_kind', r.case_kind, 'lesson', r.lesson, 'cases', r.cases));
    n_new := n_new + (v is not null)::int;
  end loop;

  -- an open finding seen three or more times is a process fault, not a one-off
  for r in select f.issue_key, f.title, f.seen_count, coalesce(nullif(f.evidence->>'owner_seat', ''), f.raised_by) as seat
             from public.it_engineer_finding f where f.closed_at is null and f.seen_count >= 3 loop
    exit when clock_timestamp() - v_t0 > interval '30 seconds';
    if exists (select 1 from public.org_role o where o.role_id = r.seat and o.status = 'active') then
      v := public.fn_ceo_improvement_open('recurring_finding', r.issue_key, r.seat,
        format('Remove the cause of a finding seen %s times: %s', r.seen_count, left(r.title, 300)),
        jsonb_build_object('issue_key', r.issue_key, 'seen_count', r.seen_count));
      n_new := n_new + (v is not null)::int;
    end if;
  end loop;

  exit when n_new + n_done = v_before or v_pass >= 50 or clock_timestamp() - v_t0 > interval '30 seconds';
  end loop;

  return jsonb_build_object('proposed', n_new, 'closed', n_done, 'passes', v_pass,
    'stopped_at_budget', clock_timestamp() - v_t0 > interval '30 seconds',
    'open', (select count(*) from public.ceo_improvement where status in ('open', 'assigned')));
end $function$;
