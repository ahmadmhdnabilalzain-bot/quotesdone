-- SECTION 24 — "Before any major decision each advisor gives an independent recommendation."
--
-- WHY THE CHECK WAS STILL MISSING, MEASURED 11 Aug 2026. Not a wiring gap. fn_decide already ends
-- with a fn_board_review(problem, decision_record_id) call, keyed to the record so the link is an id
-- and not the text match the scorer falls back on. Probed on production in an aborted transaction:
--   PROBE decision_record=47 opinions=7 distinct_advisors=7 with_subject_ref=7
-- The mechanism is correct and complete. It had simply never been exercised: the wiring landed on
-- 11 Aug, the newest board_opinion is dated 28 Jul, and no fn_decide call has run since. So all 11
-- decision_record rows in the 30-day window predate the board entirely — "0 of 11" was measuring the
-- age of the rows, not the health of the mechanism.
--
-- WHAT THIS DOES, AND THE ONE ROW IT DELIBERATELY WILL NOT TOUCH.
-- Of the 11, ten were never carried out: seven sit at status='proposed' with gate_verdict null, and
-- three were refused by the gate (blocked_by_gate). For those ten the decision is still open, so the
-- board advising on them now is genuinely advice BEFORE the decision, which is what the spec asks
-- for. They are reviewed.
--
-- decision_record id 42 is status='executed', gate_verdict='passed'. That decision was taken. An
-- opinion recorded against it today would be read by the scorer as "the board advised before this
-- decision", and that would be false. It is left unreviewed, s24 therefore stays MISSING until 42
-- ages out of the 30-day window on 5 September, and that is the correct verdict rather than a green
-- one. A check that passes because the data was arranged to make it pass is worse than no check.
--
-- fn_challenge underneath is pure SQL over challenge_heuristic, institutional_memory and live
-- counts, so this costs no model call and invents no opinion: every stance, confidence and
-- alternative is derived from a stored rule or a measured number.
--
-- Idempotent: a decision that already carries an opinion from every active advisor is skipped, so
-- re-running this never duplicates a review.
do $$
declare r record; v_n int := 0; v_skipped int := 0; v_adv int;
begin
  select count(*) into v_adv from public.board_advisor where coalesce(active, true);

  for r in
    select d.id, d.problem, d.status
      from public.decision_record d
     where d.created_at > now() - interval '30 days'
       -- never carried out: still open, or refused by the gate. An executed decision is excluded.
       and coalesce(d.status, '') <> 'executed'
       and (select count(distinct o.advisor_key) from public.board_opinion o
             where o.subject_ref = d.id::text) < v_adv
     order by d.id
  loop
    begin
      perform public.fn_board_review(coalesce(r.problem, 'decision_record ' || r.id), r.id::text);
      v_n := v_n + 1;
    exception when others then
      -- One advisor failing must not lose the rest of the board.
      raise warning 'fn_board_review failed for decision_record % : %', r.id, sqlerrm;
      v_skipped := v_skipped + 1;
    end;
  end loop;

  raise notice 'board reviewed % open decision(s), % failed, % active advisor(s)', v_n, v_skipped, v_adv;
end $$;
