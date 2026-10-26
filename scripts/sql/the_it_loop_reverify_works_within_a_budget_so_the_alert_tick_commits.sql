-- THE IT LOOP'S RE-VERIFY WORKS WITHIN A BUDGET, SO THE ALERT TICK COMMITS AGAIN (it_engineer, 27 Oct 2026).
-- Assigned: it_engineer.
--
-- MEASURED 27 Oct 2026 (22:36 UTC on 26 Oct by the database clock), production, in rolled-back transactions:
--   * it_engineer_scanner 'it_engineer_alert_tick' last beat 19 Oct 18:46 UTC, 'it_ceo_silence_watch' 19 Oct
--     18:01 UTC: the alert tick has not completed for a week.
--   * fn_it_loop_tick, timed section by section: fn_it_loop_reverify 51.89 s; every other section together < 2 s
--     (silence watch 1.57, originators 0.14, sales sweep 0.08, the rest 0.00).
--   * fn_it_loop_reverify alone: 59.8 s over 973 pending it.finding handoffs: closed 411, waiting 544,
--     escalated 18, learned from the playbook 42.
-- resilience_ping calls fn_it_engineer_alert_tick over PostgREST, whose statement_timeout is 8 s, so every tick
-- is cancelled and ROLLED BACK: the 411 closes and 18 escalations are redone, and lost, every tick, and the open
-- step never runs (a rolled-back probe of the tick opened 0 with 186 findings left). This is the 18 Oct failure
-- (the_it_alert_tick_opens_its_backlog_within_budget_and_escalates_first.sql) moved from the open step to
-- reverify: that file bounded the open step and put reverify first, measuring reverify at 0.81 s; the backlog it
-- now walks is ~1,000 handoffs.
--
-- THE FIX, the same shape as the open step's: reverify walks its handoffs oldest first until 1 s after it began
-- (its own clock, not the statement's, so a caller that did other work first still gets its 1 s), then counts the
-- rest as left_for_next_tick. What it closed or escalated within the budget now commits with the tick, so the
-- backlog drains a tick at a time (about 8 closes a tick at ~120 ms each, ~96 ticks a day) instead of never.
-- Nothing else in the body changes. Measured with a 2 s budget the whole alert tick took 6,179 ms in its worst
-- hour (silence watch due), over the 6 s the check allows; 1 s keeps the 2 s of headroom under PostgREST's 8 s.
-- ponytail: a time budget, not a cheaper close. If closes ever arrive faster than ~8 a tick, make
-- fn_seat_handoff_complete cheaper rather than raising the budget.
--
-- CREATE OR REPLACE keeps the live ACL (postgres and service_role only, read 27 Oct 2026); no revoke needed.
-- Body: production's, read 27 Oct 2026 with pg_get_functiondef (canonical file every_handoff_is_answered_within_its_window.sql).
-- Prevented by: scripts/checks/it_engineer_loop_is_closed.test.mjs ('the alert tick fits the 8 s statement timeout
-- and escalates before it opens'), which now replays a pending fn_it_loop_reverify too, and
-- scripts/checks/the_accountant_closes_every_loop_it_opens.test.mjs ('one fn_it_loop_tick opens the handoff for
-- the oldest open finding'): both fail on production as it is (tick cancelled at 8 s / opened 0).

CREATE OR REPLACE FUNCTION public.fn_it_loop_reverify()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  h public.agent_actions; f public.it_engineer_finding; v_window interval; v_rep jsonb; v_cleared boolean;
  n_closed int := 0; n_esc int := 0; n_wait int := 0; n_playbook int := 0; v_class text; n_reports int := 0;
  -- 27 Oct 2026: the walk stops 1 s after it began; the rest waits for the next tick (see the file header)
  v_until timestamptz := clock_timestamp() + interval '1 second'; n_left int := 0;
begin
  select max(reply_within) into v_window from public.seat_handoff_kind where type = 'it.finding' and from_seat = 'it_engineer';
  -- Review finding, 18 Sep 2026: with no such row v_window is null, `now() > created_at + null` is
  -- null, and EVERY handoff fell quietly into 'waiting' -- the loop would never escalate again and
  -- would say nothing about why. A missing conversation row is a configuration fault, not a default.
  if v_window is null then
    raise exception 'fn_it_loop_reverify: seat_handoff_kind names no reply window for it.finding from it_engineer';
  end if;
  -- 22 Sep 2026: a handoff closed anywhere but the close branch below -- fn_it_attach_learning is the
  -- one other door -- left its CEO report 'accepted' for good. The report follows its handoff here.
  update public.support_ceo_report r
     set status = 'completed', completed_at = now(),
         completion_note = 'IT engineer re-verified: handoff ' || a.id || ' is closed ('
           || coalesce(a.evidence->>'verdict', 'learning recorded by ' || coalesce(a.evidence->>'learning_recorded_by', 'an unnamed recorder')) || ').'
    from public.agent_actions a
   where r.status = 'accepted' and r.idempotency_key ~ '^it_loop:[0-9]+$'
     and a.id = substr(r.idempotency_key, 9)::bigint and a.kind = 'handoff' and a.status = 'done';
  get diagnostics n_reports = row_count;

  for h in select * from public.agent_actions
            where kind = 'handoff' and detail->>'type' = 'it.finding' and detail->>'from' = 'it_engineer'
              and status in ('pending', 'failed') order by id loop
    if clock_timestamp() > v_until then n_left := n_left + 1; continue; end if;
    select * into f from public.it_engineer_finding where issue_key = h.detail->>'issue_key';
    -- The occurrence this loop tracked is over when the finding is closed, or when it has since
    -- closed and reopened (a later started_at is a different occurrence with its own loop).
    v_cleared := f.issue_key is null or f.closed_at is not null
                 or f.started_at > (h.detail->>'occurrence_started_at')::timestamptz;

    if v_cleared then
      -- A new bug that has cleared needs what was learned (trigger z62). Where the playbook already
      -- covers this failure class, the IT engineer records it from there and closes now; where it
      -- does not, the handoff waits for a human, which is what the gate is for.
      v_class := public.fn_it_learning_from_playbook(h.id);
      if v_class is not null then n_playbook := n_playbook + 1; end if;
    end if;

    if v_cleared and exists (select 1 from public.it_incident i where i.handoff_id = h.id
                              and (coalesce(btrim(i.cause), '') = '' or coalesce(btrim(i.fix), '') = ''
                                   or coalesce(btrim(i.regression_check), '') = ''
                                   or (i.playbook_class is null and coalesce(btrim(i.not_automatable_reason), '') = ''))) then
      if not (h.detail ? 'awaiting_learning') then
        update public.agent_actions set detail = detail || jsonb_build_object('awaiting_learning', now()) where id = h.id;
        update public.it_incident set ended_at = coalesce(f.closed_at, now()), updated_at = now() where handoff_id = h.id and ended_at is null;
      end if;
      n_wait := n_wait + 1;
    elsif v_cleared then
      update public.it_incident set ended_at = coalesce(ended_at, f.closed_at, now()), updated_at = now() where handoff_id = h.id;
      perform set_config('qd.handoff_closer', 'it_engineer', true);
      perform public.fn_seat_handoff_complete(h.id, coalesce(h.evidence, '{}'::jsonb) || jsonb_build_object(
        'verified_by', 'it_engineer', 'verified_at', now(),
        'verdict', coalesce(f.close_note, 'the finding is no longer open'),
        'learning_from_playbook', v_class,
        'reply_before_close', h.detail ? 'replied_at'));
      perform set_config('qd.handoff_closer', '', true);
      update public.support_ceo_report
         set status = 'completed', completed_at = now(),
             completion_note = 'IT engineer re-verified: ' || coalesce(f.close_note, 'the finding is no longer open') || ' (handoff ' || h.id || ').'
       where idempotency_key = 'it_loop:' || h.id and status = 'accepted';
      n_closed := n_closed + 1;
    -- 19 Oct 2026: an info finding (affected 0, title 'info:...') is a note, not a fault. Once its handoff is
    -- answered the note has been read: the finding and the handoff close here, so nothing stays open unwatched.
    elsif coalesce(f.affected, 1) = 0 and coalesce(f.title, '') ilike 'info:%' and h.detail ? 'replied_at' then
      perform public.fn_it_engineer_finding_close(f.issue_key, 'info finding: the owning seat answered handoff ' || h.id);
      perform set_config('qd.handoff_closer', 'it_engineer', true);
      perform public.fn_seat_handoff_complete(h.id, coalesce(h.evidence, '{}'::jsonb) || jsonb_build_object(
        'verified_by', 'it_engineer', 'verified_at', now(), 'verdict', 'info finding answered and closed'));
      perform set_config('qd.handoff_closer', '', true);
      n_closed := n_closed + 1;
    -- An unanswered info finding waits for its reply; it never escalates.
    elsif not (h.detail ? 'escalated_report_id') and now() > h.created_at + v_window
          and not (coalesce(f.affected, 1) = 0 and coalesce(f.title, '') ilike 'info:%') then
      v_rep := public.fn_support_report_to_ceo(
        'it_loop:' || h.id,
        case when h.detail->>'severity' = 'critical' then 'critical' else 'serious' end,
        'Still broken after ' || h.agent || '''s reply window: ' || left(coalesce(h.detail->>'title', h.detail->>'issue_key'), 160),
        jsonb_build_object('handoff_id', h.id, 'issue_key', h.detail->>'issue_key', 'seat', h.agent,
                           'reply', h.evidence, 'finding', to_jsonb(f)),
        jsonb_build_array(jsonb_build_object('action', 'handed to ' || h.agent, 'handoff_id', h.id,
                                             'at', h.created_at, 'replied_at', h.detail->>'replied_at')),
        'Decide the remedy, or record that this is a new bug for the founder. The IT engineer keeps re-checking and closes the loop only when the finding is gone.',
        p_review_in => interval '2 hours', p_source_agent => 'it_engineer');
      if not coalesce((v_rep->>'ok')::boolean, false) then
        raise exception 'fn_it_loop_reverify: the CEO report for handoff % was refused: %', h.id, v_rep->>'reason';
      end if;
      update public.agent_actions
         set detail = detail || jsonb_build_object('escalated_report_id', (v_rep->>'report_id')::bigint, 'escalated_at', now())
       where id = h.id;
      perform public.fn_ceo_it_escalation_decide((v_rep->>'report_id')::bigint);
      n_esc := n_esc + 1;
    else
      n_wait := n_wait + 1;
    end if;
  end loop;
  return jsonb_build_object('closed', n_closed, 'escalated', n_esc, 'waiting', n_wait, 'learned_from_playbook', n_playbook,
                            'reports_completed', n_reports, 'left_for_next_tick', n_left);
end $function$
;
