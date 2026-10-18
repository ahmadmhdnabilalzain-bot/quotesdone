-- THE CEO IMPROVEMENT SWEEP CLOSES BEFORE IT PROPOSES, AND SETTLES IN ONE RUN. Seat: ceo. 30 Sep 2026.
--
-- MEASURED (30 Sep 2026, live bodies, highest MANIFEST keys):
--   * fn_ceo_improvement_sweep proposed first and closed last. fn_ceo_improvement_open caps lessons and recurring
--     findings at 20 open per seat, so the slots a run's closures freed were only filled by the NEXT run: in the
--     year-one probe run 1 proposed 19 and closed 99, run 2 proposed 14 more. Nothing was duplicated -- the
--     (source_kind, source_ref) key held -- but the sweep did not settle, and "a second run proposes nothing" failed.
--   * recurring_miss is keyed metric:YYYY-MM, so on the 1st of a month a metric still behind got a SECOND open
--     improvement beside last month's, and a metric that had recovered (7 days on path) but still showed 7 misses in
--     the 14-day window was proposed again the moment its first improvement closed.
--   * the weekly review's "missed 5, opened 2" was not an under-count: 3 of the 5 missed targets already had their
--     open improvement from the 28 Sep week (ids 9700-9702), and the review correctly skips those. It did not SAY so,
--     so missed <> opened read as a loss. It now returns 'carried', and missed = opened + carried.
--
-- THE FIX:
--   1. the sweep closes first, then proposes, and repeats until a pass changes nothing (a closure can finalise the
--      cases another lesson waits on) -- one run settles; a second run proposes nothing unless a verdict, a lesson
--      or a finding actually changed;
--   2. one OPEN improvement per metric (recurring_miss) and per seat+target (weekly_review), enforced by a partial
--      unique index on the target itself, whatever period the source_ref carries; fn_ceo_improvement_open skips on
--      ANY unique key. (The month in a recurring_miss ref still means a metric that recovers and falls behind again
--      in the same month waits for the next month's key -- unchanged from before.)
--   3. a metric on its path for the last 7 days is recovered and is not proposed;
--   4. fn_ceo_weekly_review returns 'carried' (missed targets whose improvement was already open), so
--      missed = opened + carried is the invariant its probe asserts.
--   The CEO decision cycle is untouched: reasons, revise and resubmit, the 4-round guard live in other routines.
--
-- Prevented by: scripts/sql/the_ceo_improvement_sweep_closes_before_it_proposes_and_settles_in_one_run_probe.sql
--   and scripts/checks/the_ceo_year_one_plan_follows_the_founder_targets.test.mjs (second run proposes 0 anywhere).

-- The old body may have opened a second improvement for a metric or target before this lands (a month turning over
-- between merge and apply): keep the first, drop the later ones, so the indexes below can be built.
update public.ceo_improvement i set status = 'dropped', closed_at = now(),
       done_evidence = format('Superseded by improvement #%s: one open improvement per target (30 Sep 2026).', k.keep)
  from (select id, min(id) over (partition by source_kind, case when source_kind = 'weekly_review' then seat end, coalesce(evidence->>'metric', evidence->>'target')) as keep
          from public.ceo_improvement
         where source_kind in ('recurring_miss', 'weekly_review') and status in ('open', 'assigned')) k
 where i.id = k.id and k.id <> k.keep;

create unique index if not exists ceo_improvement_one_open_per_metric
  on public.ceo_improvement ((evidence->>'metric'))
  where source_kind = 'recurring_miss' and status in ('open', 'assigned');

create unique index if not exists ceo_improvement_one_open_weekly_per_target
  on public.ceo_improvement (seat, (evidence->>'target'))
  where source_kind = 'weekly_review' and status in ('open', 'assigned');

create or replace function public.fn_ceo_improvement_open(p_kind text, p_ref text, p_seat text, p_proposal text, p_evidence jsonb)
returns bigint language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_id bigint; v_task bigint; v_hid bigint;
begin
  if p_kind in ('lesson', 'recurring_finding')
     and (select count(*) from public.ceo_improvement where seat = p_seat and status in ('open', 'assigned')) >= 20 then
    return null;   -- capped: the sweep closes before it proposes, so a slot freed this run is filled this run
  end if;
  insert into public.ceo_improvement (source_kind, source_ref, seat, proposal, evidence)
  values (p_kind, p_ref, p_seat, p_proposal, coalesce(p_evidence, '{}'::jsonb))
  on conflict do nothing returning id into v_id;   -- any unique key: the same ref, or one already open for the target
  if v_id is null then return null; end if;
  v_task := public.fn_ceo_task_open(format('Improvement #%s for %s: %s', v_id, p_seat, left(p_proposal, 200)),
                                    format(E'%s\nSource: %s %s.\nEvidence: %s', p_proposal, p_kind, p_ref, coalesce(p_evidence, '{}'::jsonb)));
  if p_seat <> 'ceo' then
    v_hid := public.fn_seat_handoff('ceo', p_seat, 'ceo.improvement', 'ceo_improvement', v_id::text,
      jsonb_build_object('improvement_id', v_id, 'task_id', v_task, 'proposal', p_proposal, 'source', p_kind, 'evidence', p_evidence));
  end if;
  update public.ceo_improvement set status = 'assigned', task_id = v_task, handoff_id = v_hid where id = v_id;
  return v_id;
end $fn$;

create or replace function public.fn_ceo_improvement_sweep()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare r record; n_new int := 0; n_done int := 0; c_id bigint; v bigint; v_ans timestamptz;
  v_pass int := 0; v_before int;
begin
  select id into c_id from public.target_contract where contract_key = 'FOUNDER_TARGETS_YEAR_ONE_TO_2027_09_30' and status = 'active';

  -- Close, then propose, and repeat until a pass changes nothing. Closing one improvement completes its handoff,
  -- which can finalise the cases another lesson waits on, and frees a capped slot; a single close-then-propose
  -- still left 11 closes and 11 proposals for the next run (measured 30 Sep 2026). The last pass is the proof.
  -- ponytail: 10 passes bound the loop; a chain longer than that finishes on the next run.
  loop
  v_pass := v_pass + 1;
  v_before := n_new + n_done;

  -- 1. CLOSE FIRST. Tracked to done: the CEO is the originator, re-verifies, and is the one who closes.
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

  exit when n_new + n_done = v_before or v_pass >= 10;
  end loop;

  return jsonb_build_object('proposed', n_new, 'closed', n_done, 'passes', v_pass,
    'open', (select count(*) from public.ceo_improvement where status in ('open', 'assigned')));
end $fn$;

-- The weekly review says what it carried: a missed target whose improvement is already open is counted, not lost.
-- Body otherwise as the_ceo_weekly_review_acts_on_every_missed_target.sql.
create or replace function public.fn_ceo_weekly_review(p_week date, p_at timestamptz default now())
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_targets jsonb; t jsonb; i record; v_id bigint; v_task bigint;
  v_open bigint[] := '{}'; v_esc bigint[] := '{}'; v_closed bigint[] := '{}'; v_carried bigint[] := '{}'; v_row public.ceo_weekly_review;
  v_today date := (p_at at time zone 'Asia/Dubai')::date;
begin
  select * into v_row from public.ceo_weekly_review where week = p_week;
  if found then return jsonb_build_object('week', p_week, 'already', true, 'id', v_row.id); end if;

  v_targets := public.fn_ceo_weekly_review_measure(p_at);

  -- 1. CLOSE: the check of each open action, re-read on the same measure
  for i in select * from public.ceo_improvement where source_kind = 'weekly_review' and status in ('open', 'assigned') loop
    select x into t from jsonb_array_elements(v_targets) x
     where x->>'key' = i.evidence->>'target' and x->>'seat' = i.seat limit 1;
    if t is not null and ((t->>'met')::boolean
        or (t->>'key' = 'supply' and (t->>'value')::numeric < (i.evidence->>'value')::numeric)) then
      perform public.fn_ceo_improvement_close(i.id, format('Weekly review of %s: %s. %s', p_week, t->>'actual', i.close_check));
      v_closed := v_closed || i.id;
    end if;
  end loop;

  -- 2. ESCALATE: still open past its due date
  for i in select * from public.ceo_improvement where source_kind = 'weekly_review' and status in ('open', 'assigned')
                                                     and due_on is not null and due_on <= v_today loop
    v_task := public.fn_ceo_task_open(
      format('ESCALATED x%s: %s missed the due date of improvement #%s', i.escalations + 1, i.seat, i.id),
      format(E'%s\nWas due %s. Now due %s. %s\nMeasured this week: %s',
             coalesce(i.evidence->>'action', i.proposal), i.due_on, v_today + 7, i.close_check,
             coalesce((select x->>'actual' from jsonb_array_elements(v_targets) x where x->>'key' = i.evidence->>'target' and x->>'seat' = i.seat limit 1), 'not measured')));
    update public.ceo_improvement set escalations = escalations + 1, last_escalated_at = p_at, due_on = v_today + 7,
           evidence = evidence || jsonb_build_object('escalation_tasks', coalesce(evidence->'escalation_tasks', '[]'::jsonb) || to_jsonb(v_task))
     where id = i.id;
    v_esc := v_esc || i.id;
  end loop;

  -- 3. OPEN: one action per missed target that has none open; one already open is CARRIED, and counted
  for t in select x from jsonb_array_elements(v_targets) x where not (x->>'met')::boolean loop
    select id into v_id from public.ceo_improvement where source_kind = 'weekly_review' and status in ('open', 'assigned')
       and seat = t->>'seat' and evidence->>'target' = t->>'key' limit 1;
    if v_id is not null then v_carried := v_carried || v_id; continue; end if;
    v_id := public.fn_ceo_improvement_open('weekly_review', (t->>'key') || ':' || (t->>'seat') || ':' || p_week, t->>'seat',
      format('Weekly review %s, %s missed (%s; target %s). Action: %s Due %s. %s',
             to_char(p_week, 'DD Mon YYYY'), t->>'label', t->>'actual', t->>'target', t->>'action', to_char(p_week + 7, 'DD Mon YYYY'), t->>'close_check'),
      jsonb_build_object('target', t->>'key', 'value', t->'value', 'week', p_week, 'actual', t->>'actual', 'action', t->>'action', 'detail', t->'detail'));
    if v_id is not null then
      update public.ceo_improvement set due_on = p_week + 7, close_check = t->>'close_check' where id = v_id;
      v_open := v_open || v_id;
    end if;
  end loop;

  insert into public.ceo_weekly_review (week, targets, opened, escalated, closed)
  values (p_week, v_targets, v_open, v_esc, v_closed) returning * into v_row;
  update public.ceo_weekly_review set pdf_blocks = public.fn_ceo_weekly_review_pdf_blocks(v_row.id) where id = v_row.id;
  return jsonb_build_object('ok', true, 'week', p_week, 'id', v_row.id, 'opened', cardinality(v_open),
    'escalated', cardinality(v_esc), 'closed', cardinality(v_closed), 'carried', cardinality(v_carried),
    'carried_ids', to_jsonb(v_carried),
    'missed', (select count(*) from jsonb_array_elements(v_targets) x where not (x->>'met')::boolean));
end $fn$;
