-- ONE SLOW DUTY NEVER WEDGES THE SEAT DUTY TICK (it_engineer, 18 Oct 2026). Assigned: it_engineer.
--
-- MEASURED (production, 18 Oct 2026, read-only plus one rolled-back timing probe):
--   * public.seat_duty: max(last_started_at) = max(last_ok_at) = 2026-10-15 03:45:40Z for all 84 enabled duties,
--     every seat (accountant 15 of 15 last ok 14-15 Oct). 0 open seat_duty:* findings although fn_seat_duty_health
--     returns 65 problems: the tick has not COMMITTED once since 15 Oct 03:45.
--   * edge_logs: POST /rest/v1/rpc/fn_seat_duties_tick -> 500 on every resilience_ping run (16:00, 16:30, 17:00,
--     17:30Z ...); postgres_logs at 17:30:32.357 "canceling statement due to statement timeout" (8 s, PostgREST).
--   * The tick runs the 8 most overdue duties before its 4 s budget applies. Timed one by one (rolled back):
--     fn_ceo_improvement_sweep 9 252 ms (ceo.improvement, weekly, last ok 8 Oct - due 15 Oct ~04:00, the hour the
--     tick stopped), fn_it_engineer_knowledge_recall_exam 4 092 ms, the other six < 50 ms. The sweep alone is past
--     8 s, the whole tick rolls back - last_started_at with it - so the same duty is first again next tick. Wedged.
--   * CI red "every_alarm_is_quiet_on_a_healthy_day" (14 Sep 01:00Z replay) is this, not a replay artefact:
--     fn_seat_duty_health is a separate routine on the real clock, and the duties are genuinely 4 days overdue.
--
-- FIX
--   1. fn_seat_duties_tick: the 3 s budget applies after the FIRST duty, not after the first p_limit. A tick always
--      runs at least one duty (the most overdue) and never starts a second past 3 s, so only one duty that alone
--      exceeds ~7 s can still time it out.
--   2. fn_ceo_improvement_sweep: stops proposing/closing after 3 s and returns; the rest is done next run (each
--      pass is idempotent - on conflict do nothing, close by status). Measured 6.6-9.3 s with a 1-week backlog.
--   CREATE OR REPLACE keeps the existing grants (postgres, service_role only); search_path stays pinned.
--
-- Prevented by: scripts/checks/every_alarm_is_quiet_on_a_healthy_day.test.mjs (fn_seat_duties_tick replay goes
-- quiet once the duties run again) and the probe one_slow_duty_never_wedges_the_seat_duty_tick_probe.sql.
-- Apply at merge:  node scripts/apply_sql.mjs scripts/sql/one_slow_duty_never_wedges_the_seat_duty_tick.sql --apply

create or replace function public.fn_seat_duties_tick(p_limit integer default 8)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp'
as $function$
declare d public.seat_duty; v_res jsonb; v_out jsonb := '[]'::jsonb; v_health jsonb; p jsonb;
        v_t0 timestamptz := clock_timestamp(); v_n int := 0;
begin
  for d in
    select sd.* from public.seat_duty sd
     where enabled
       -- ONE PAUSE SWITCH (29 Sep 2026): a duty public.duty_pause names is not started.
       and not exists (select 1 from public.duty_pause dp where dp.duty = sd.duty)
       -- two minutes of tolerance, the same reasoning as fn_resilience_tick_plan: a tick is never exactly on the beat
       and (last_started_at is null or now() - last_started_at >= every - interval '2 minutes')
     order by last_started_at + every nulls first, duty   -- the most overdue first
     limit greatest(1, least(coalesce(p_limit, 8), 60))
     for update skip locked
  loop
    -- the time budget (18 Oct 2026): after the first duty, none starts past 3 s. The whole tick is one statement
    -- under PostgREST's 8 s timeout; on 15 Oct the first-8-always-run rule let a 9 s duty roll every tick back.
    exit when v_n >= 1 and clock_timestamp() - v_t0 > interval '3 seconds';
    v_n := v_n + 1;
    update public.seat_duty set last_started_at = now() where duty = d.duty;
    begin
      if not public.fn_seat_duty_routine_exists(d.routine) then
        raise exception 'routine public.%() does not exist', d.routine;
      end if;
      execute format('select public.%I()', d.routine) into v_res;
      update public.seat_duty set last_ok_at = now(), last_result = v_res, last_error = null, failures = 0 where duty = d.duty;
      v_out := v_out || jsonb_build_object('duty', d.duty, 'ok', true);
    exception when others then
      update public.seat_duty set last_error = left(sqlerrm, 1000), failures = failures + 1 where duty = d.duty;
      v_out := v_out || jsonb_build_object('duty', d.duty, 'ok', false, 'error', left(sqlerrm, 300));
    end;
  end loop;

  -- The check, every tick: each problem is a finding; a duty that recovered closes its own.
  v_health := public.fn_seat_duty_health();
  for p in select * from jsonb_array_elements(v_health) loop
    -- a paused duty is overdue on purpose; it is not a finding while the pause stands
    continue when exists (select 1 from public.duty_pause dp where dp.duty = p->>'duty');
    perform public.fn_it_engineer_finding_upsert(
      'seat_duty:' || (p->>'duty'),
      'Seat duty ' || (p->>'duty') || ' is not being done: ' || (p->>'problem'),
      'public.seat_duty / ' || coalesce(p->>'routine', '?'), 'agent_facing', 1, p,
      '{}'::text[], array['why the routine fails or is not reached'], 'it_engineer');
  end loop;
  update public.it_engineer_finding f
     set closed_at = now(), close_note = 'the duty is no longer overdue or failing: it ran on its clock again, or it was disabled or paused (fn_seat_duties_tick)'
   where f.issue_key like 'seat_duty:%' and f.closed_at is null
     and (not exists (select 1 from jsonb_array_elements(v_health) h where 'seat_duty:' || (h->>'duty') = f.issue_key)
          or exists (select 1 from public.duty_pause dp where 'seat_duty:' || dp.duty = f.issue_key));
  return jsonb_build_object('ran', v_out, 'problems', jsonb_array_length(v_health));
end $function$;

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
  -- ponytail: 10 passes and 3 s bound the loop (it runs inside the seat duty tick's 8 s statement, 18 Oct 2026:
  -- 9.3 s unbounded); what is left finishes on the next run, every step being idempotent.
  loop
  v_pass := v_pass + 1;
  v_before := n_new + n_done;

  -- 1. CLOSE FIRST. Tracked to done: the CEO is the originator, re-verifies, and is the one who closes.
  for r in select i.*, coalesce(i.evidence->>'lesson',
                                (select m.lessons[1] from public.seat_case_memory m where m.id = (i.evidence->>'case_memory_id')::bigint)) as lesson
             from public.ceo_improvement i where i.status in ('open', 'assigned') loop
    exit when clock_timestamp() - v_t0 > interval '3 seconds';
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
    exit when clock_timestamp() - v_t0 > interval '3 seconds';
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
    exit when clock_timestamp() - v_t0 > interval '3 seconds';
    v := public.fn_ceo_improvement_open('lesson', 'lesson:' || r.seat || ':' || md5(r.case_kind || '|' || r.lesson), r.seat,
      format('Make this lesson part of the routine, so the same case does not come back: %s', r.lesson),
      jsonb_build_object('case_memory_id', r.last_case, 'case_kind', r.case_kind, 'lesson', r.lesson, 'cases', r.cases));
    n_new := n_new + (v is not null)::int;
  end loop;

  -- an open finding seen three or more times is a process fault, not a one-off
  for r in select f.issue_key, f.title, f.seen_count, coalesce(nullif(f.evidence->>'owner_seat', ''), f.raised_by) as seat
             from public.it_engineer_finding f where f.closed_at is null and f.seen_count >= 3 loop
    exit when clock_timestamp() - v_t0 > interval '3 seconds';
    if exists (select 1 from public.org_role o where o.role_id = r.seat and o.status = 'active') then
      v := public.fn_ceo_improvement_open('recurring_finding', r.issue_key, r.seat,
        format('Remove the cause of a finding seen %s times: %s', r.seen_count, left(r.title, 300)),
        jsonb_build_object('issue_key', r.issue_key, 'seen_count', r.seen_count));
      n_new := n_new + (v is not null)::int;
    end if;
  end loop;

  exit when n_new + n_done = v_before or v_pass >= 10 or clock_timestamp() - v_t0 > interval '3 seconds';
  end loop;

  return jsonb_build_object('proposed', n_new, 'closed', n_done, 'passes', v_pass,
    'stopped_at_budget', clock_timestamp() - v_t0 > interval '3 seconds',
    'open', (select count(*) from public.ceo_improvement where status in ('open', 'assigned')));
end $function$;
