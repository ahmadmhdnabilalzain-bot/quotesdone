-- A MONTH DIRECTIVE IS LATE BY ITS MONTH END, NOT BY ITS ONE-DAY REPLY WINDOW.
--
-- Seat: it_engineer. 7 Oct 2026. Wiring audit (PR #1278), item 3.
--
-- THE DESIGN. ceo.month_directive (the_ceo_runs_the_company_on_the_founders_year_one_targets.sql) gives each
-- seat its month on the 1st: seat_handoff_kind.reply_within = 1 day is the clock for the seat to ANSWER, and the
-- seat answers in the same second (replied_at = created_at, measured on all five October rows 126710-126714).
-- The CEO then CLOSES it at detail.due_at, the month end (31 Oct 20:00Z), met or missed (originator_closes).
--
-- THE FALSE ALARM, MEASURED 7 Oct 2026 01:40Z. Two monitors still time every pending handoff from created_at +
-- reply_within, whether or not it was answered and whatever its own due_at says:
--   fn_ceo_seat_audit   -- counts 'handoffs_late' per seat: all five October month directives counted late
--                          (one each for accountant, customer_support, it_engineer, marketing, sales_engineer),
--                          plus the 1 Oct ceo.directive to sales_engineer (due_at 8 Oct).
--   fn_ceo_directive_run -- writes the same predicate into every seat_health directive's close condition, so a
--                          seat holding its month directive can never satisfy "no handoff past its window".
-- fn_it_handoff_sla_items already reads due_at (since 5 Oct) and is unchanged here.
--
-- THE FIX. One predicate, fn_handoff_is_late(detail, created_at, reply_within, at), used by both:
--   unanswered -> late after created_at + reply_within (unchanged);
--   answered   -> late after detail.due_at when the handoff carries one, otherwise after created_at + reply_within
--                 (unchanged for every type that has no due_at, e.g. it.finding).
-- Measured with this predicate on the same rows: month directives late 5 -> 0, the ceo.directive 1 -> 0; every
-- other pending handoff counts exactly as before (it.finding 375, ceo.root_cause 3, deliberation.review 1,
-- support.human_requested 1).
--
-- Prevented by: scripts/checks/a_month_directive_is_late_by_its_month_end_not_its_reply_window.test.mjs
--   node scripts/apply_sql.mjs scripts/sql/a_month_directive_is_late_by_its_month_end_not_its_reply_window.sql --apply --ddl

create or replace function public.fn_handoff_is_late(p_detail jsonb, p_created_at timestamptz, p_window interval, p_at timestamptz default now())
returns boolean language sql stable set search_path to 'public', 'pg_temp' as $fn$
  select case when p_detail ? 'replied_at'
              then coalesce((p_detail->>'due_at')::timestamptz, p_created_at + p_window) < p_at
              else p_created_at + p_window < p_at end
$fn$;
revoke execute on function public.fn_handoff_is_late(jsonb, timestamptz, interval, timestamptz) from public, anon, authenticated;

create or replace function public.fn_ceo_directive_run(p_at timestamptz default now())
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare r record; d public.ceo_directive; v bigint; v_ok boolean; v_err text; v_new bigint; v_dec bigint; v_task bigint;
  n_issued int := 0; n_met int := 0; n_esc int := 0; n_missed int := 0; v_q date;
  v_late text := $q$exists (select 1 from public.agent_actions a
      join public.seat_handoff_kind k on k.type = a.detail->>'type' and k.from_seat = a.detail->>'from' and k.to_seat = a.agent
     where a.kind = 'handoff' and a.agent = %1$L and a.status = 'pending' and public.fn_handoff_is_late(a.detail, a.created_at, k.reply_within))$q$;
begin
  -- 1. target misses on the year-one plan
  for r in select e->>'metric' as metric, e->>'owner_seat' as seat, e->>'actual' as actual, e->>'expected' as expected
             from jsonb_array_elements(coalesce(public.fn_ceo_year_plan_status(p_at)->'metrics', '[]'::jsonb)) e
            where e->>'status' = 'miss' and e->>'owner_seat' is not null loop
    v := public.fn_ceo_directive_issue(r.seat, 'target_miss', r.metric || ':' || to_char(p_at at time zone 'Asia/Dubai', 'YYYY-MM'),
      format('Bring %s back to its path: it reads %s against %s. Name the step that is not converting and change that step.', r.metric, coalesce(r.actual, '?'), r.expected),
      format('%s is no longer a miss on the year-one plan.', r.metric),
      format($q$not exists (select 1 from jsonb_array_elements(coalesce(public.fn_ceo_year_plan_status(now())->'metrics', '[]'::jsonb)) e where e->>'metric' = %L and e->>'status' = 'miss')$q$, r.metric),
      p_at + interval '7 days', jsonb_build_object('metric', r.metric, 'actual', r.actual, 'expected', r.expected));
    n_issued := n_issued + (v is not null)::int;
  end loop;

  -- 2. late deliverables: the month marketing plan
  for r in select i.id, (i.evidence->>'plan_month')::date as m, (i.evidence->>'deadline')::date as due_was, (i.evidence->>'due_on')::date as due_on
             from public.ceo_improvement i where i.source_kind = 'marketing_plan_late' and i.status in ('open', 'assigned') loop
    v := public.fn_ceo_directive_issue('marketing', 'late_deliverable', 'marketing_month_plan:' || r.m,
      format('Send the CEO the marketing plan for %s. It was due on %s; the month does not start unplanned.', to_char(r.m, 'FMMonth YYYY'), to_char(r.due_was, 'DD Mon')),
      format('marketing_month_plan for %s exists and has left draft, or improvement #%s is closed.', r.m, r.id),
      format($q$exists (select 1 from public.marketing_month_plan p where p.month = %L::date and p.status <> 'draft') or exists (select 1 from public.ceo_improvement i where i.id = %s and i.status = 'done')$q$, r.m, r.id),
      greatest(coalesce(r.due_on::timestamp at time zone 'Asia/Dubai', p_at), p_at) + interval '1 day',
      jsonb_build_object('improvement_id', r.id, 'plan_month', r.m, 'due_was', r.due_was));
    n_issued := n_issued + (v is not null)::int;
  end loop;

  -- 3. stuck handoffs: pending past twice the kind's reply window (a day when none is set), as the daily run reads them
  for r in select a.id, a.agent as seat, a.detail->>'type' as type, a.detail->>'from' as from_seat, a.created_at
             from public.agent_actions a
             left join public.seat_handoff_kind k on k.type = a.detail->>'type' and k.from_seat = a.detail->>'from' and k.to_seat = a.agent
            where a.kind = 'handoff' and a.status = 'pending' and a.detail->>'replied_at' is null
              and a.created_at < p_at - coalesce(k.reply_within * 2, interval '1 day') loop
    v := public.fn_ceo_directive_issue(r.seat, 'stuck_handoff', 'agent_actions:' || r.id,
      format('Answer handoff #%s (%s from %s), waiting since %s.', r.id, r.type, r.from_seat, to_char(r.created_at at time zone 'Asia/Dubai', 'DD Mon HH24:MI')),
      format('handoff #%s is answered (replied_at set) or no longer pending.', r.id),
      format($q$exists (select 1 from public.agent_actions a where a.id = %s and (a.status <> 'pending' or a.detail ? 'replied_at'))$q$, r.id),
      p_at + interval '1 day', jsonb_build_object('handoff_id', r.id, 'type', r.type, 'from', r.from_seat, 'since', r.created_at));
    n_issued := n_issued + (v is not null)::int;
  end loop;

  -- 4. the latest seat audit's below-bar seats
  select max(quarter) into v_q from public.ceo_seat_audit;
  for r in select a.seat, a.shortfalls, a.improvement_id from public.ceo_seat_audit a where a.quarter = v_q and a.below_bar loop
    v := public.fn_ceo_directive_issue(r.seat, 'seat_audit', v_q || ':' || r.seat,
      format('Get back to the senior bar found short in the audit of the quarter starting %s: %s.', to_char(v_q, 'DD Mon YYYY'), array_to_string(r.shortfalls, '; ')),
      'no handoff to the seat is open past its reply window, and none of its duties is failing or overdue.',
      format('not ' || v_late || $q$ and not exists (select 1 from jsonb_array_elements(public.fn_seat_duty_health()) h where h->>'owner_seat' = %1$L)$q$, r.seat),
      p_at + interval '14 days', jsonb_build_object('quarter', v_q, 'improvement_id', r.improvement_id, 'shortfalls', r.shortfalls));
    n_issued := n_issued + (v is not null)::int;
  end loop;

  -- the close loop: each open directive is re-checked on its own predicate
  for d in select * from public.ceo_directive where status = 'open' order by id loop
    v_err := null;
    begin
      execute 'select coalesce((' || d.done_sql || ')::boolean, false)' into v_ok;
    exception when others then v_ok := false; v_err := left(sqlerrm, 300);
    end;
    if v_ok then
      update public.ceo_directive set status = 'met', closed_at = p_at,
             evidence = evidence || jsonb_build_object('closed', jsonb_build_object('checked_at', p_at, 'predicate', d.done_sql, 'result', true))
       where id = d.id;
      n_met := n_met + 1;
    elsif p_at > d.deadline and d.escalated_from is null then
      update public.ceo_directive set status = 'escalated', closed_at = p_at,
             evidence = evidence || jsonb_build_object('escalated', jsonb_build_object('checked_at', p_at, 'result', false, 'error', v_err))
       where id = d.id;
      insert into public.ceo_directive (seat, source_kind, source_ref, instruction, done_when, done_sql, deadline, escalated_from, evidence)
      values (d.seat, d.source_kind, d.source_ref, 'RE-ISSUED after the deadline of ' || to_char(d.deadline at time zone 'Asia/Dubai', 'DD Mon') || ' passed: ' || d.instruction,
              d.done_when, d.done_sql, p_at + (d.deadline - d.issued_at), d.id, d.evidence)
      returning id into v_new;
      insert into public.ceo_decision_log (decision_key, the_decision, evidence, reading_before, outcome, dedupe_key)
      values ('directive_escalation',
              format('Directive #%s to %s passed its deadline unmet; re-issued once as #%s, due %s.', d.id, d.seat, v_new,
                     to_char((p_at + (d.deadline - d.issued_at)) at time zone 'Asia/Dubai', 'DD Mon')),
              jsonb_build_object('directive_id', d.id, 'reissue_id', v_new, 'seat', d.seat, 'done_when', d.done_when, 'deadline', d.deadline, 'predicate_error', v_err),
              'done-condition false at ' || p_at, 'decided', 'ceo_directive_escalation:' || d.id)
      on conflict do nothing returning id into v_dec;
      update public.ceo_directive set evidence = evidence || jsonb_build_object('decision_log_id', v_dec) where id = d.id;
      n_esc := n_esc + 1;
    elsif p_at > d.deadline then
      v_task := public.fn_ceo_task_open(format('Directive #%s to %s missed after re-issue', d.id, d.seat),
        format(E'%s\nDone when: %s\nFirst issued as #%s. The CEO decides the next step itself; it is not re-issued again.', d.instruction, d.done_when, d.escalated_from));
      update public.ceo_directive set status = 'missed', closed_at = p_at,
             evidence = evidence || jsonb_build_object('missed', jsonb_build_object('checked_at', p_at, 'result', false, 'error', v_err, 'task_id', v_task))
       where id = d.id;
      n_missed := n_missed + 1;
    end if;
  end loop;

  return jsonb_build_object('issued', n_issued, 'met', n_met, 'escalated', n_esc, 'missed', n_missed,
    'open', (select count(*) from public.ceo_directive where status = 'open'));
end $fn$;
revoke execute on function public.fn_ceo_directive_run(timestamptz) from public, anon, authenticated;

create or replace function public.fn_ceo_seat_audit(p_at timestamptz default now())
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_q date := date_trunc('quarter', p_at at time zone 'Asia/Dubai')::date; v_health jsonb := public.fn_seat_duty_health();
  s record; v_n int; v_ok int; v_rate numeric; v_duties int; v_failing int; v_late int; v_missed int;
  v_short text[]; v_m jsonb; v_id bigint; n_below int := 0; n_closed int := 0; r record;
begin
  if exists (select 1 from public.ceo_seat_audit where quarter = v_q) then
    return jsonb_build_object('quarter', v_q, 'already', true);
  end if;

  for s in select role_id from public.org_role where status = 'active' and role_id <> 'ceo' order by role_id loop
    select count(*), count(*) filter (where verdict = 'correct') into v_n, v_ok
      from public.seat_knowledge_exam where seat = s.role_id and graded_at > p_at - interval '90 days';
    v_rate := case when v_n >= 5 then round(v_ok::numeric / v_n, 3) end;
    select count(*) into v_duties from public.seat_duty where owner_seat = s.role_id and enabled;
    select count(*) into v_failing from jsonb_array_elements(v_health) h where h->>'owner_seat' = s.role_id;
    select count(*) into v_late from public.agent_actions a
      join public.seat_handoff_kind k on k.type = a.detail->>'type' and k.from_seat = a.detail->>'from' and k.to_seat = a.agent
     where a.kind = 'handoff' and a.agent = s.role_id and a.status = 'pending' and public.fn_handoff_is_late(a.detail, a.created_at, k.reply_within, p_at);
    select count(*) into v_missed from public.ceo_seat_directive
     where seat = s.role_id and status = 'missed' and month >= (v_q - interval '3 months')::date;

    v_short := '{}';
    if v_rate is not null and v_rate < 0.80 then
      v_short := v_short || format('knowledge %s%% correct on %s graded items in 90 days: retrain on the items missed (IT refiled each one for re-research) until the rate is back over 80%%', round(v_rate * 100), v_n);
    end if;
    if v_failing > 0 then
      v_short := v_short || format('%s of %s duties failing or overdue now: repair each until it runs on its clock', v_failing, v_duties);
    end if;
    if v_late > 0 then
      v_short := v_short || format('%s handoffs open past their reply window: answer each, and say why it was late', v_late);
    end if;
    if v_missed >= 2 then
      v_short := v_short || format('%s monthly targets missed in the last quarter: name the step that did not convert and change it', v_missed);
    end if;
    v_m := jsonb_build_object('knowledge_graded_90d', v_n, 'knowledge_correct_90d', v_ok, 'knowledge_rate', v_rate,
      'duties', v_duties, 'duties_failing', v_failing, 'handoffs_late', v_late, 'months_missed', v_missed);

    v_id := null;
    if cardinality(v_short) > 0 then
      v_id := public.fn_ceo_improvement_open('seat_audit', v_q || ':' || s.role_id, s.role_id,
        format('Quarterly audit of %s for the quarter starting %s: below the senior bar. ', s.role_id, to_char(v_q, 'DD Mon YYYY'))
          || array_to_string(v_short, '; ') || '. Due before the next quarterly audit.',
        v_m || jsonb_build_object('quarter', v_q));
      n_below := n_below + 1;
    end if;
    insert into public.ceo_seat_audit (quarter, seat, measures, shortfalls, below_bar, improvement_id)
    values (v_q, s.role_id, v_m, v_short, cardinality(v_short) > 0, v_id);
  end loop;

  -- last quarter's audit improvements close when the seat is back at the bar this quarter
  for r in select i.id, i.seat from public.ceo_improvement i
            where i.source_kind = 'seat_audit' and i.status in ('open', 'assigned') and (i.evidence->>'quarter')::date < v_q loop
    if exists (select 1 from public.ceo_seat_audit a where a.quarter = v_q and a.seat = r.seat and not a.below_bar) then
      perform public.fn_ceo_improvement_close(r.id, format('%s is back at the bar in the audit of the quarter starting %s.', r.seat, v_q));
      n_closed := n_closed + 1;
    end if;
  end loop;
  return jsonb_build_object('quarter', v_q, 'seats', (select count(*) from public.ceo_seat_audit where quarter = v_q),
                            'below_bar', n_below, 'closed', n_closed);
end $fn$;
revoke execute on function public.fn_ceo_seat_audit(timestamptz) from public, anon, authenticated;

-- The seven seat_health directives still open on 7 Oct (ids 12, 13, 14, 57, 58, 59, 60) carry the old predicate
-- inside their stored done_sql; they would never close while a month directive is pending. Rewritten by exact id,
-- only that predicate, only while open.
update public.ceo_directive
   set done_sql = replace(done_sql, 'and a.created_at < now() - k.reply_within)', 'and public.fn_handoff_is_late(a.detail, a.created_at, k.reply_within))')
 where id in (12, 13, 14, 57, 58, 59, 60) and status = 'open'
   and done_sql like '%and a.created_at < now() - k.reply_within)%';

-- Verdict (no exception: this file defines routines).
select case
  when exists (select 1 from public.ceo_directive where status = 'open' and done_sql like '%a.created_at < now() - k.reply_within%')
    then 'PROBE FAILED: an open directive still carries the reply-window predicate'
  when (select count(*) from public.agent_actions a
          join public.seat_handoff_kind k on k.type = a.detail->>'type' and k.from_seat = a.detail->>'from' and k.to_seat = a.agent
         where a.kind = 'handoff' and a.status = 'pending' and a.detail->>'type' = 'ceo.month_directive'
           and (a.detail->>'due_at')::timestamptz > now()
           and public.fn_handoff_is_late(a.detail, a.created_at, k.reply_within)) > 0
    then 'PROBE FAILED: a month directive before its month end still counts late'
  when not public.fn_handoff_is_late('{}'::jsonb, now() - interval '2 days', interval '1 day')
    then 'PROBE FAILED: an unanswered handoff past its window is not late'
  when not public.fn_handoff_is_late(jsonb_build_object('replied_at', now() - interval '3 days', 'due_at', now() - interval '1 hour'), now() - interval '3 days', interval '1 day')
    then 'PROBE FAILED: an answered handoff past its due_at is not late'
  else 'PROBE OK' end as verdict;
