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
--   CAUSE: held_question has no worker at all; it.finding handoffs have a worker that escalates once and then never
--   flags the wait again. Not a dead duty.
--
-- WHAT THIS ADDS: fn_ceo_queue_work(), the CEO duty ceo.queue_work, every hour. For agent='ceo', status='pending':
--   1. held_question / held_question_expired / support_question_handover (#1462 files the last one; keyed on the held
--      question id in target_id): its question applied/answered/closed -> 'done'. A CEO internal duty question
--      (surface ceo.* or learning.*) still unapplied after 7 days -> 'dismissed': the duty re-files on its next run.
--   2. any pending item older than 7 days that step 1 did not settle -> escalated=true with escalation_reason, ONCE
--      (the overdue alert; the CEO daily run and seat audit read escalated). Never the founder: rulings 1254 and
--      8 Sep keep him for what only he can do, and nothing here is that.
--   It never closes an it.finding handoff: only fn_it_loop_reverify may, so the learning gate (z62) stands.
--
-- Prevented by: scripts/sql/the_ceo_queue_is_worked_closed_or_flagged_overdue_probe.sql (aborted transaction).

create or replace function public.fn_ceo_queue_work()
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare n_done int; n_dismissed int; n_overdue int;
begin
  if not pg_try_advisory_xact_lock(hashtext('fn_ceo_queue_work')) then
    return jsonb_build_object('skipped', 'another run is going');
  end if;

  with q as (
    select a.id, h.status hs, h.surface, a.created_at
      from public.agent_actions a
      join public.reasoning_held_question h on h.id::text = a.target_id
     where a.agent = 'ceo' and a.status = 'pending'
       and a.kind in ('held_question', 'held_question_expired', 'support_question_handover')
  ), done as (
    update public.agent_actions a
       set status = 'done', decided_at = now(), decided_by = 'ceo',
           evidence = coalesce(a.evidence, '{}'::jsonb) || jsonb_build_object('verdict', 'its question was ' || q.hs, 'closed_by', 'fn_ceo_queue_work')
      from q where a.id = q.id and q.hs in ('applied', 'answered', 'closed')
    returning a.id
  ), dis as (
    update public.agent_actions a
       set status = 'dismissed', decided_at = now(), decided_by = 'ceo',
           evidence = coalesce(a.evidence, '{}'::jsonb) || jsonb_build_object('verdict',
             'a CEO internal duty question (' || q.surface || ', ' || q.hs || ') older than 7 days: the duty re-files on its next run',
             'closed_by', 'fn_ceo_queue_work')
      from q where a.id = q.id and q.hs not in ('applied', 'answered', 'closed')
       and (q.surface like 'ceo.%' or q.surface like 'learning.%') and q.created_at < now() - interval '7 days'
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
     and a.created_at < now() - interval '7 days';
  get diagnostics n_overdue = row_count;

  return jsonb_build_object('done', n_done, 'dismissed', n_dismissed, 'flagged_overdue', n_overdue);
end
$fn$;

revoke execute on function public.fn_ceo_queue_work() from public, anon, authenticated;
grant execute on function public.fn_ceo_queue_work() to service_role;

insert into public.seat_duty (duty, owner_seat, every, routine, what, owner_file) values
  ('ceo.queue_work', 'ceo', interval '1 hour', 'fn_ceo_queue_work',
   'Closes CEO queue items whose held question settled, dismisses stale internal-duty questions, flags anything older than 7 days overdue once.',
   'scripts/sql/the_ceo_queue_is_worked_closed_or_flagged_overdue.sql')
on conflict (duty) do update set owner_seat = excluded.owner_seat, every = excluded.every, routine = excluded.routine,
  what = excluded.what, owner_file = excluded.owner_file;
