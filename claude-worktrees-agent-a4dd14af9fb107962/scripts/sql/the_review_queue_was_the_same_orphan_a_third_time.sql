-- THE REVIEW QUEUE WAS THE SAME ORPHAN A THIRD TIME.
--
-- After exec_reports and doc_backups were closed, one finding stayed open:
--
--   review_queue_pending  1,433 rows at status 'pending', oldest waiting 122 hours against a
--                         72-hour threshold. Severity medium, so it never reached the founder's
--                         inbox -- it sat under the two that did.
--
-- I nearly left it. It is the third instance of one fault, and the reason it looked different is
-- that its own detector note calls it "drained by review, which is not continuous" -- which is a
-- fair description of a queue with a reviewer, and a misleading one for a queue whose reviewers
-- were deleted.
--
-- MEASURED, BEFORE TOUCHING ANYTHING:
--
--   Rows        1,433 pending, created 4 Sep 06:01 - 7 Sep 13:31 2026. 23 'rejected' beside them.
--   Addressed   to 10 dept_keys: exec, product_eng, marketplace, legal, data_intel, people_ops,
--               growth, supply, finance, customer_experience. `public.departments` NO LONGER
--               EXISTS -- the founder removed departments entirely on 7 September, and org_role now
--               holds five seats (accountant, ceo, customer_support, it_engineer, sales_engineer),
--               not one of which is a department.
--   Producer    dead. ZERO rows created since 7 Sep 13:31 -- the last one landed as the purge ran,
--               and nothing has queued a review in the two days since.
--   Subjects    gone. Every row's payload names an org_task, a workflow_run, a step_run and an
--               executor. `public.org_task` was DROPPED; workflow_run, workflow_step_run and
--               org_action_executor each hold 0 rows.
--   Fixtures    14 of the 1,433 are `ZZ DEMO` rehearsal rows, which were never real work.
--
-- THE POSITIVE CONTROL, AND IT IS A REAL ONE. Every pending row carries a `decision_trace_id`
-- (1,433 of 1,433). `public.decision_trace` still holds 2 rows, so the lookup CAN return true --
-- this is not the empty-parent case where "not exists" is trivially satisfied. It returns 0: not
-- one pending row's decision trace survived. That is the check doing work, not a dead guard.
--
-- WHY THE MATCH IS ON THE TRACE AND NOT ON dept_key. Both are true of these rows, but only one of
-- them is evidence. dept_key would match every row whose department is gone -- and since the
-- departments table itself was dropped, that is EVERY row, forever, including any a future seat
-- might file under a name that happens to look departmental. The decision trace is per-row: it says
-- this specific piece of work has no surviving record behind it. If a row arrived tomorrow with a
-- live trace, this predicate would leave it alone and a dept_key predicate would not.
--
-- WHAT 'obsolete' MEANS HERE. fn_review_decide writes 'approved' and 'rejected'; those are
-- judgements a reviewer made. 'obsolete' is deliberately NEITHER, so nothing in the ledger can be
-- read as the founder having decided 1,433 items. decided_at and decided_by are stamped so an
-- auditor can see when and by what, and founder_comment is left NULL because he did not comment.
--
-- THE DETECTOR IS NOT WEAKENED. Its predicate (status = 'pending') and its 4,320-minute threshold
-- are untouched. The next genuinely pending review that sits three days fires exactly as before.

do $do$
declare
  v_before int; v_after int; v_orphaned int; v_traces int; v_rejected_before int; v_rejected_after int;
begin
  select count(*) into v_before  from public.review_queue where status = 'pending';
  select count(*) into v_traces  from public.decision_trace;
  select count(*) into v_rejected_before from public.review_queue where status = 'rejected';

  if v_before = 0 then
    raise notice 'the review queue is already clear - nothing to do';
    return;
  end if;

  -- POSITIVE CONTROL: the lookup must be able to return true, or "the trace is gone" is a statement
  -- about an empty table rather than about these rows.
  if v_traces = 0 then
    raise exception 'POSITIVE CONTROL FAILED: decision_trace is empty, so every row would test as orphaned whatever its trace';
  end if;

  select count(*) into v_orphaned
    from public.review_queue r
   where r.status = 'pending'
     and r.payload ? 'decision_trace_id'
     and not exists (select 1 from public.decision_trace d
                      where d.id::text = r.payload->>'decision_trace_id');

  if v_orphaned <> v_before then
    raise exception '% of % pending review(s) still have a live decision trace (or carry none at all); those are real work awaiting a decision, not residue',
      v_before - v_orphaned, v_before;
  end if;

  update public.review_queue r
     set status     = 'obsolete',
         decided_at = now(),
         decided_by = 'system: orphaned by the 7 Sep 2026 department removal'
   where r.status = 'pending'
     and r.payload ? 'decision_trace_id'
     and not exists (select 1 from public.decision_trace d
                      where d.id::text = r.payload->>'decision_trace_id');

  select count(*) into v_after from public.review_queue where status = 'pending';
  select count(*) into v_rejected_after from public.review_queue where status = 'rejected';

  if v_after <> 0 then
    raise exception '% pending review(s) remain', v_after;
  end if;
  -- Decisions a reviewer actually made must not have been touched by a sweep aimed at residue.
  if v_rejected_after <> v_rejected_before then
    raise exception 'the % rejected row(s) changed to % - this sweep must only touch pending residue',
      v_rejected_before, v_rejected_after;
  end if;

  raise notice 'review_queue pending % -> 0, all orphaned against a decision_trace holding % live row(s). % rejected row(s) untouched.',
    v_before, v_traces, v_rejected_after;
end
$do$;
