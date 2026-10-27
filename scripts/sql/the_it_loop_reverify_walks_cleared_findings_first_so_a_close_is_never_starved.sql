-- THE IT LOOP'S RE-VERIFY WALKS CLEARED FINDINGS FIRST, SO A CLOSE IS NEVER STARVED BY THE ESCALATION BACKLOG.
-- apply-window: any (CREATE OR REPLACE of one routine; no table lock)
--
-- Assigned: it_engineer. 27 Oct 2026.
--
-- ══ MEASURED, 27 Oct 2026 18:30-19:30 UTC, htdblwldjkcgjvmqkbeh, in rolled-back transactions ═════════════════════════
--   * fn_it_loop_reverify (the 1 s budget of #1613, the_it_loop_reverify_works_within_a_budget_so_the_alert_tick_
--     commits.sql), one call: closed 0, waiting 636, escalated 3-5, left_for_next_tick 280-282, 1,074-1,219 ms. The
--     walk itself is cheap (all 921 open handoffs read their finding and incident in 46 ms; 436 playbook look-ups in
--     61 ms); the budget goes on the escalations, ~150-200 ms each (fn_support_report_to_ceo + fn_ceo_it_escalation_
--     decide). Walking oldest first, the ~280 NEWEST handoffs are never reached while older rows still need escalating.
--   * #1613's header measured the drain on a backlog with almost nothing left to escalate; 178 it.finding handoffs now
--     sit past their window (most of them duty:delivery:request, see the_delivery_watch_returns_results_within_a_time_
--     budget_so_the_ladder_tick_commits.sql), so that measurement no longer holds.
--   * scripts/checks/the_accountant_closes_every_loop_it_opens.test.mjs, against production: "ZZFAIL: handoff 308365
--     for acct:bank:missing:po_zz_probe_1 reads pending after re-verification". The probe clears its finding and calls
--     fn_it_loop_reverify once; its handoff has the highest id, so the walk never reaches it. A real seat whose fix
--     cleared its finding waits the same way.
--
-- ══ WHAT THIS CHANGES ═══════════════════════════════════════════════════════════════════════════════════════════
--   The walk takes the handoffs whose finding has CLEARED first (the same test as v_cleared in the body: no finding,
--   a closed finding, or a later occurrence), then the rest, each group by id. Closing a cleared loop is what the loop
--   is for and cannot wait behind escalations; a still-open finding past its window is escalated in what remains of
--   the second, as before. A cleared handoff parked at awaiting_learning stays a cheap read. Nothing else in the body
--   changes: the budget, the branches, the escalation and the close are production's.
--
-- WHAT IT DOES NOT DO. It does not make an escalation cheaper and does not raise the budget (ponytail, as #1613 said:
-- make the expensive call cheaper rather than the budget larger). It does not touch the 178 overdue rows by hand.
--
-- Body: the MANIFEST-last one (the_it_loop_reverify_works_within_a_budget_so_the_alert_tick_commits.sql, line 2134;
-- the canonical engine reads 0 drift, so it is production's) with the walk's ORDER BY only. CREATE OR REPLACE keeps
-- the live ACL (postgres and service_role only), so no revoke.
-- Prevented by: scripts/checks/the_accountant_closes_every_loop_it_opens.test.mjs (its fixtures call the live routine
-- once and need their own, newest handoff closed) and scripts/checks/it_engineer_loop_is_closed.test.mjs
-- ('the walk takes cleared findings first').
-- Pending: scripts/sql/pending/the_it_loop_reverify_walks_cleared_findings_first_so_a_close_is_never_starved.txt

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

  -- 27 Oct 2026: CLEARED FINDINGS FIRST (see the file header). The key mirrors v_cleared below exactly; a row whose
  -- finding is still open (or whose occurrence cannot be read) sorts after every cleared one, then by id as before.
  for h in select a.* from public.agent_actions a
             left join public.it_engineer_finding f0 on f0.issue_key = a.detail->>'issue_key'
            where a.kind = 'handoff' and a.detail->>'type' = 'it.finding' and a.detail->>'from' = 'it_engineer'
              and a.status in ('pending', 'failed')
            order by coalesce(f0.issue_key is null or f0.closed_at is not null
                              or f0.started_at > (a.detail->>'occurrence_started_at')::timestamptz, false) desc,
                     a.id loop
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
