-- THE CEO QUEUE IS WORKED: EVERY PENDING ITEM IS CLOSED WHEN ITS SUBJECT IS SETTLED, OR FLAGGED OVERDUE ONCE.
-- Seat: ceo (written by it_engineer). 19 Oct 2026.
--
-- MEASURED BEFORE THIS FILE (production, 19 Oct 2026): 130 agent_actions agent='ceo' status='pending'.
--   * 105 handoff: 104 it.finding from it_engineer + 1 deliberation.review from marketing. Every one already carries
--     the CEO's reply (detail.replied_at, awaiting the originator). The worker exists: fn_it_loop_reverify closes an
--     it.finding handoff when its finding clears. It is stuck in two places:
--       - 75 findings still open, each escalated once to a support_ceo_report the CEO 'accepted' (oldest 22 Sep);
--         nothing escalates a second time, so the item sits with no clock.
--       - 18 findings cleared, held at detail.awaiting_learning because the it_incident lacks cause/fix/regression
--         check; the loop "waits for a human" and nothing names the wait.
--       - 11 filed 18 Oct, inside their reply window (normal).
--     27 of the 104 were filed 15-18 Oct (the seat-duty outage #1431 fixed); 77 predate it, so the outage is not the
--     cause.
--   * 25 held_question (CEO internal surfaces: experiment_approval, knowledge_refresh, management_review,
--     marketing_month_plan, target_forecast, learning.distil; 25 Sep - 10 Oct). Filed by fn_reason_held_escalate; NO
--     routine reads agent_actions kind held_question. 14 of their questions were since applied, 5 expired, 6 failed.
--   * agent_actions.escalated: no routine ACTS on it (only fn_ops_dashboard / fn_os_list display it). The CEO's acting
--     list is ceo_task, read by fn_ceo_daily_run and fn_ceo_week_plan_vs_actual.
--   CAUSE: held_question has no worker at all; it.finding handoffs have a worker that escalates once and then never
--   flags the wait again. Not a dead duty.
--
-- WHY A DISMISSAL CANNOT LOSE A QUESTION: fn_reason_hold dedupes on dedupe_key and keeps a failed/expired row closed,
-- so an age-based dismissal could leave a period that is never re-asked. This file therefore dismisses ONLY a question
-- superseded by a LATER question for the SAME item (same surface, same dedupe_key stem, a different period) whose
-- status is 'applied' ('reasoned' or anything else does not count; the table allows held, reasoned, applied, failed, expired); a key with no recognisable period is never dismissed. Measured 19 Oct 2026 on the 11 unapplied:
-- every dedupe_key is period-scoped (ceo_exp_approve:<exp>:<iter>, krefresh:<quarter>:<item>, ceo_mreview:<week>,
-- ceo_forecast:<week>). 7 have a later applied question for the same item - including ceo.management_review and
-- ceo.target_forecast, whose duties were dead 15-18 Oct and filed fresh questions (ceo_mreview / ceo_forecast) on 15 Oct
-- that were applied. 4 do not: two knowledge items (failure-modes-and-trade-offs, purpose-and-trigger)
-- failed in both the 2026-07-01 and 2026-10-01 quarters with no applied refresh since:
-- those stay pending and are flagged overdue instead.
--
-- WHAT THIS ADDS: fn_ceo_queue_work(), the CEO duty ceo.queue_work, every hour. For agent='ceo', status='pending':
--   0. #1462's support handover kind is NEVER touched (not closed, not flagged): #1462's fn_ceo_support_handover_duty
--      sends the customer the reply and closes it, so it can never close before the customer is answered.
--   1. held_question / held_question_expired (keyed on the held question id in target_id): its question
--      applied -> 'done'; superseded by a later applied question for the same item -> 'dismissed'.
--   2. any pending item older than 7 days that step 1 did not settle -> escalated=true with escalation_reason, ONCE,
--      and one ceo_task a day ('CEO queue overdue <date>') listing them. The worker closes its own lists: an earlier day's once today's carries it, and any list none of whose
--      items is still pending. Never the
--      founder: rulings 1254 and 8 Sep keep him for what only he can do, and nothing here is that.
--   It never closes an it.finding handoff: only fn_it_loop_reverify may, so the learning gate (z62) stands.
--
-- Prevented by: scripts/sql/the_ceo_queue_is_worked_closed_or_flagged_overdue_probe.sql (aborted transaction) and
-- scripts/checks/the_ceo_queue_worker_never_touches_a_support_handover.test.mjs.

-- The item a dedupe_key names, without its period: ISO-date segments removed (krefresh:<quarter>:<item>,
-- ceo_mreview:<week>, ceo_forecast:<week>), else the trailing numeric iteration (ceo_exp_approve:<exp>:<iter>).
create or replace function public.fn_ceo_queue_dedupe_stem(p_key text)
returns text language sql immutable set search_path to 'public', 'pg_temp' as $fn$
  select case when p_key ~ ':[0-9]{4}-[0-9]{2}-[0-9]{2}' then regexp_replace(p_key, ':[0-9]{4}-[0-9]{2}-[0-9]{2}', '', 'g')
              when p_key ~ ':[0-9]+$' then regexp_replace(p_key, ':[0-9]+$', '') end
$fn$;
revoke execute on function public.fn_ceo_queue_dedupe_stem(text) from public, anon, authenticated;
grant execute on function public.fn_ceo_queue_dedupe_stem(text) to service_role;

create or replace function public.fn_ceo_queue_work()
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare n_done int; n_dismissed int; n_overdue int; n_task_closed int; v_task bigint; v_title text; v_list text;
begin
  if not pg_try_advisory_xact_lock(hashtext('fn_ceo_queue_work')) then
    return jsonb_build_object('skipped', 'another run is going');
  end if;

  with q as (
    select a.id, h.id hid, h.status hs, h.surface, h.dedupe_key dkey, public.fn_ceo_queue_dedupe_stem(h.dedupe_key) stem
      from public.agent_actions a
      join public.reasoning_held_question h on h.id::text = a.target_id
     where a.agent = 'ceo' and a.status = 'pending'
       and a.kind in ('held_question', 'held_question_expired')
  ), done as (
    update public.agent_actions a
       set status = 'done', decided_at = now(), decided_by = 'ceo',
           evidence = coalesce(a.evidence, '{}'::jsonb) || jsonb_build_object('verdict', 'its question was ' || q.hs, 'closed_by', 'fn_ceo_queue_work')
      from q where a.id = q.id and q.hs = 'applied'
    returning a.id
  ), dis as (
    update public.agent_actions a
       set status = 'dismissed', decided_at = now(), decided_by = 'ceo',
           evidence = coalesce(a.evidence, '{}'::jsonb) || jsonb_build_object(
             'verdict', 'superseded: held question ' || s.sid || ' on ' || q.surface || ' was applied after this one (' || q.hs || ')',
             'superseded_by', s.sid, 'closed_by', 'fn_ceo_queue_work')
      from q
      cross join lateral (select max(n.id) sid from public.reasoning_held_question n
                           where n.surface = q.surface and n.id > q.hid and n.status = 'applied'
                             and n.dedupe_key <> q.dkey and public.fn_ceo_queue_dedupe_stem(n.dedupe_key) = q.stem) s
     where a.id = q.id and q.hs <> 'applied' and q.stem is not null and s.sid is not null
    returning a.id
  )
  select (select count(*) from done), (select count(*) from dis) into n_done, n_dismissed;

  update public.agent_actions a
     set escalated = true,
         escalation_reason = left('Overdue: pending with the CEO since ' || to_char(a.created_at at time zone 'Asia/Dubai', 'DD Mon')
           || case when a.detail ? 'awaiting_learning' then '; the finding cleared but its incident has no cause/fix/regression check'
                   when a.detail ? 'escalated_report_id' then '; the finding is still open after the CEO accepted report '
                        || (a.detail->>'escalated_report_id')
                   when a.detail ? 'awaiting' then '; awaiting ' || (a.detail->>'awaiting')
                   else '' end, 500)
   where a.agent = 'ceo' and a.status = 'pending' and not coalesce(a.escalated, false)
     and a.kind in ('handoff', 'held_question', 'held_question_expired')  -- named kinds only: #1462 owns its handover kind
     and a.created_at < now() - interval '7 days';
  get diagnostics n_overdue = row_count;

  -- The flag alone is read by nothing that acts: put the overdue list on the CEO's own task list, once a day.
  v_title := 'CEO queue overdue ' || to_char(now() at time zone 'Asia/Dubai', 'YYYY-MM-DD');
  -- This worker closes its own tasks (fn_ceo_daily_run closes only what it opened): an earlier day's list is carried
  -- into today's; any list none of whose items is still pending is done.
  update public.ceo_task t
     set state = 'done', closed_at = now(),
         evidence = case when t.title <> v_title then 'superseded by ' || v_title || ' (fn_ceo_queue_work)'
                         else 'none of its items is still pending (fn_ceo_queue_work)' end
   where t.title like 'CEO queue overdue %' and t.state = 'open'
     and (t.title <> v_title
          or not exists (select 1 from regexp_matches(t.detail, '(?:^|\n)#([0-9]+) ', 'g') m
                          join public.agent_actions a on a.id = m[1]::bigint where a.status = 'pending'));
  get diagnostics n_task_closed = row_count;
  select string_agg('#' || a.id || ' ' || a.kind || ': ' || a.escalation_reason, E'\n' order by a.id) into v_list
    from (select * from public.agent_actions
           where agent = 'ceo' and status = 'pending' and escalated and kind in ('handoff', 'held_question', 'held_question_expired')
           order by id limit 60) a;
  if v_list is not null and not exists (select 1 from public.ceo_task where title = v_title) then
    v_task := public.fn_ceo_task_open(v_title,
      'Pending CEO queue items older than 7 days (first 60). Each is an open IT finding, a cleared finding whose '
      || 'incident lacks cause/fix/regression check, or an answer still awaited. Decide the remedy or record why it waits.'
      || E'\n' || v_list);
  end if;

  return jsonb_build_object('done', n_done, 'dismissed', n_dismissed, 'flagged_overdue', n_overdue, 'ceo_task', v_task,
                            'ceo_tasks_closed', n_task_closed);
end
$fn$;

revoke execute on function public.fn_ceo_queue_work() from public, anon, authenticated;
grant execute on function public.fn_ceo_queue_work() to service_role;

insert into public.seat_duty (duty, owner_seat, every, routine, what, owner_file) values
  ('ceo.queue_work', 'ceo', interval '1 hour', 'fn_ceo_queue_work',
   'Closes CEO queue items whose held question settled or was superseded, flags anything older than 7 days overdue once and lists it on a daily ceo_task.',
   'scripts/sql/the_ceo_queue_is_worked_closed_or_flagged_overdue.sql')
on conflict (duty) do update set owner_seat = excluded.owner_seat, every = excluded.every, routine = excluded.routine,
  what = excluded.what, owner_file = excluded.owner_file;
