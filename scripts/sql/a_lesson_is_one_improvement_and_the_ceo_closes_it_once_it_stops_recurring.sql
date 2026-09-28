-- Seat: ceo. IT daily digest, 27 Sep 2026: 367 ceo.improvement handoffs to it_engineer (and 12/6/2 to
-- sales_engineer/customer_support/accountant) answered but never closed.
--
-- MEASURED 28 Sep 2026 on htdblwldjkcgjvmqkbeh:
--   * all 367 it_engineer rows were created in ONE sweep, 2026-09-24 03:45:33 (the first run of
--     fn_ceo_improvement_sweep), not one per tick. 373 'lesson' improvements, 98 distinct proposals:
--     "Fixed by: the backup_gap duty no longer finds it" alone 51 times.
--   * CAUSE 1 (creator): the lesson branch keyed the improvement on 'seat_case_memory:<id>', one per
--     CASE. The IT engineer writes a case (and the same closure lesson) every time a finding closes, so
--     one recurring issue became one improvement and one handoff per occurrence.
--   * CAUSE 2 (close path): a lesson closed only when no case of the same case_kind opened for 30 days.
--     Every IT case has case_kind 'it_finding' (410 of 410), so that condition can never hold while the
--     IT engineer is working; the handoffs were answered (replied_at set, accepted) and waited for ever.
--
-- FIX
--   * dedupe key = seat + md5(case_kind | lesson text): one improvement per distinct lesson per seat.
--   * the CEO re-verifies an ANSWERED lesson handoff on each sweep and closes it when every case that
--     carries the lesson is finalised and none has opened since the answer. A lesson that keeps
--     recurring (backup_gap) stays open: that is the one real issue it stands for.
--   * one-off cleanup below: duplicate open lesson improvements are set 'dropped' with
--     "superseded by #<keeper>", their tasks closed and their handoffs completed by the CEO with that
--     verdict. Nothing is deleted.
-- prevented by: scripts/checks/one_open_improvement_per_lesson.test.mjs

create or replace function public.fn_ceo_improvement_sweep()
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
declare r record; n_new int := 0; n_done int := 0; c_id bigint; v bigint; v_ans timestamptz;
begin
  select id into c_id from public.target_contract where contract_key = 'FOUNDER_TARGETS_YEAR_ONE_TO_2027_09_30' and status = 'active';

  -- a metric behind its path on 7 or more of the last 14 days: the plan for it is not working
  for r in select d.metric_key, d.owner_seat, count(*) filter (where d.status = 'miss') as misses,
                  min(d.actual) filter (where d.status = 'miss') as low, max(d.expected) as expected
             from public.target_daily_verdict d
            where d.contract_id = c_id and d.day > current_date - 14
            group by 1, 2 having count(*) filter (where d.status = 'miss') >= 7 loop
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
    v := public.fn_ceo_improvement_open('lesson', 'lesson:' || r.seat || ':' || md5(r.case_kind || '|' || r.lesson), r.seat,
      format('Make this lesson part of the routine, so the same case does not come back: %s', r.lesson),
      jsonb_build_object('case_memory_id', r.last_case, 'case_kind', r.case_kind, 'lesson', r.lesson, 'cases', r.cases));
    n_new := n_new + (v is not null)::int;
  end loop;

  -- an open finding seen three or more times is a process fault, not a one-off
  for r in select f.issue_key, f.title, f.seen_count, coalesce(nullif(f.evidence->>'owner_seat', ''), f.raised_by) as seat
             from public.it_engineer_finding f where f.closed_at is null and f.seen_count >= 3 loop
    if exists (select 1 from public.org_role o where o.role_id = r.seat and o.status = 'active') then
      v := public.fn_ceo_improvement_open('recurring_finding', r.issue_key, r.seat,
        format('Remove the cause of a finding seen %s times: %s', r.seen_count, left(r.title, 300)),
        jsonb_build_object('issue_key', r.issue_key, 'seen_count', r.seen_count));
      n_new := n_new + (v is not null)::int;
    end if;
  end loop;

  -- tracked to done: the CEO is the originator, re-verifies, and is the one who closes
  for r in select i.*, coalesce(i.evidence->>'lesson',
                                (select m.lessons[1] from public.seat_case_memory m where m.id = (i.evidence->>'case_memory_id')::bigint)) as lesson
             from public.ceo_improvement i where i.status in ('open', 'assigned') loop
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
  return jsonb_build_object('proposed', n_new, 'closed', n_done,
    'open', (select count(*) from public.ceo_improvement where status in ('open', 'assigned')));
end $function$;

-- ONE-OFF CLEANUP, 28 Sep 2026. Keeps the lowest id per (seat, case_kind, lesson), re-keys it to the new
-- dedupe key, and supersedes the rest. Rows are updated, never deleted.
do $cleanup$
declare r record; n_sup int := 0;
begin
  create temp table _lesson_key on commit drop as
    select i.id, i.seat, i.task_id, i.handoff_id,
           'lesson:' || i.seat || ':' || md5((i.evidence->>'case_kind') || '|' || m.lessons[1]) as k, m.lessons[1] as lesson
      from public.ceo_improvement i
      join public.seat_case_memory m on m.id = (i.evidence->>'case_memory_id')::bigint
     where i.source_kind = 'lesson' and i.status in ('open', 'assigned') and cardinality(m.lessons) > 0;

  for r in select l.*, min(l.id) over (partition by l.k) as keeper from _lesson_key l order by l.id loop
    if r.id = r.keeper then
      update public.ceo_improvement set source_ref = r.k, evidence = evidence || jsonb_build_object('lesson', r.lesson)
       where id = r.id and not exists (select 1 from public.ceo_improvement x where x.source_kind = 'lesson' and x.source_ref = r.k);
    else
      update public.ceo_improvement set status = 'dropped', closed_at = now(),
             done_evidence = format('Superseded by improvement #%s: the same lesson for the same seat (cleanup of 28 Sep 2026).', r.keeper)
       where id = r.id;
      update public.ceo_task set state = 'done', closed_at = now(),
             evidence = left(coalesce(evidence || E'\n', '') || format('Superseded by improvement #%s.', r.keeper), 8000)
       where task_id = r.task_id and state in ('open', 'working', 'blocked');
      if r.handoff_id is not null and exists (select 1 from public.agent_actions where id = r.handoff_id and status = 'pending') then
        perform set_config('qd.handoff_closer', 'ceo', true);
        perform public.fn_seat_handoff_complete(r.handoff_id, jsonb_build_object('verified_by', 'ceo', 'improvement_id', r.id,
          'verdict', 'superseded', 'superseded_by', r.keeper));
        perform set_config('qd.handoff_closer', '', true);
      end if;
      n_sup := n_sup + 1;
    end if;
  end loop;
end $cleanup$;

select case when (select count(*) from (
         select seat, source_ref from public.ceo_improvement
          where source_kind = 'lesson' and status in ('open', 'assigned') and source_ref like 'lesson:%'
          group by 1, 2 having count(*) > 1) d) = 0
         and not exists (select 1 from public.ceo_improvement where source_kind = 'lesson' and status in ('open', 'assigned')
                          and source_ref like 'seat_case_memory:%')
       then 'PROBE OK' else 'PROBE FAILED: a lesson is still held by more than one open improvement' end as verdict;
