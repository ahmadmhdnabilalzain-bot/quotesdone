-- ONE DECISION RECORD THAT WAS NEVER A DECISION: THE GO-LIVE SWITCHES ARE A FOUNDER INPUT.
--
-- decision_record 4 (chief_of_staff, 27 Jul 2026): "The three go-live switches are all false, so the
-- marketplace cannot acquire supply or demand" — recommending that invite_enabled and bd_outreach_enabled
-- be turned on. It sat at 'proposed' with approved_by null for six weeks and the OS listed it among the
-- founder's pending decisions. It is not one. The go switches are HIS inputs, recorded as such in
-- docs/FOUNDER_INPUTS.md §3 ("the company's ignition keys; the machine reads them every time it is about to
-- act and never flips them itself"): the machine does not decide to launch, and no employee determines
-- it in a lane. The record is withdrawn with that reason on the row. Nothing else in this file: the six
-- remaining proposed decisions are routed by fn_decision_record_route (the mechanism), not by hand.
--
--   node scripts/apply_sql.mjs scripts/sql/held_rows_go_to_their_owners_data.sql --apply --ddl
update public.decision_record
   set status = 'withdrawn',
       decided_at = now(),
       actual_outcome = 'Withdrawn 5 Sep 2026: the go-live switches (invite_enabled, marketing_golive, '
                        || 'meta_autospend_golive) are founder inputs recorded in docs/FOUNDER_INPUTS.md section 3, '
                        || 'flipped by him and read by the machine, never decided by it. This was a founder-initiated '
                        || 'fact mis-filed as a decision awaiting him; nothing waits on him except a Stripe refund.'
 where id = 4 and status = 'proposed' and approved_by is null
   and problem like 'The three go-live switches%';

-- The routing sweep ran a minute before the withdrawal above and had already opened org_task 573103 for
-- record 4 ("Decision requested: The three go-live switches are all false ..."). A task for a withdrawn
-- non-decision is cancelled with the same reason; nothing is determined on it.
update public.org_tasks
   set status = 'cancelled', updated_at = now(),
       result = coalesce(result, '{}'::jsonb) || jsonb_build_object('cancelled', jsonb_build_object(
         'at', now(), 'by', 'held_rows_go_to_their_owners_data.sql',
         'reason', 'decision_record 4 was withdrawn: the go-live switches are founder inputs (docs/FOUNDER_INPUTS.md section 3), not a decision for any employee or for him'))
 where detail like '[decision_record:4] %' and status in ('assigned', 'in_progress', 'blocked', 'proposed');
