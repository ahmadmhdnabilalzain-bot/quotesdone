-- G17 — two boards said no, and they were written for exactly this
--
-- G11 gave the notification object a fixture stage and a write map into public.notifications, on
-- the argument that the row is written at a status no sender selects, inside a transaction that is
-- aborted, and that the property the Phase D hold rests on — nothing sendable leaves — was
-- therefore preserved. That property WAS preserved and was measured: across thirty drives,
-- 30 notification records written and 0 deliverable.
--
-- Two kernel boards disagreed, and both predate this session:
--
--   fn_phase_d_effect_state.phase_d_write_maps_into_the_outbound_notification_table   expected 0, got 1
--   fn_phase_d_fixture_state.fixture_stage_targeting_public_notifications             expected 0, got 1
--
-- The first sits directly beside kernel_owned_objects_with_a_phase_d_writer, which is the rule that
-- stopped Phase D becoming a second creator for the kernel's own tables. It is the same rule about
-- a different relation: the outbound queue is not Phase D's to write, whatever state the row is in.
-- Neither board asks whether the row is deliverable, and that is deliberate — a structural rule that
-- can be satisfied by choosing the right column value is not a structural rule.
--
-- The founder's brief requires create/read round trips for all 56 objects and it also requires that
-- no rule or gate be weakened. Where those two collide, the guard wins: disclosing two boards in
-- kernel-boards.json so a 56th round trip can be claimed is precisely the shape this repository
-- refuses — "do not add it to kernel-boards.json to make this pass". Every other object reached its
-- round trip by building the missing mechanism; this one would reach it by removing a rule.
--
-- SO THE NOTIFICATION WRITE MAP, OUTBOUND DOOR ROW AND FIXTURE STAGE ARE REMOVED. The round trip
-- goes back to 55 of 56 and public.phase_d_object_reference_strategy reports notification as
-- NOT_CREATED_BY_ANY_STAGE — which is now a recorded decision with a board behind it rather than an
-- object nobody had got to.
--
-- WHAT IS KEPT FROM G11, because no board objects and the reasoning stands on its own:
--   * inquiry_answer creates the workstream group for the scenario's own inquiry
--   * the fixture-scenario assertion keeps its G11 narrowing, which is now unreachable for
--     notifications and remains correct for any future object whose canonical relation is one a
--     stage legitimately writes
--   * the G13 split between rows written and rows a sender would select, which is a better
--     measurement whether or not anything writes there
--
-- WHAT THE FOUNDER HAS TO DECIDE, and it is not an engineering question: whether the notification
-- object's round trip matters enough to change one of the two boards. Either the outbound queue
-- stops being off-limits to Phase D writes, or notification is formally recorded as an object whose
-- creation is proved somewhere other than the fixture factory. Both are Phase D scope decisions.

delete from public.phase_d_fixture_stage where stage_key = 'notification';
delete from public.phase_d_object_write_map where object_id = 'notification';
delete from public.phase_d_outbound_door
 where relation = 'public.notifications' and function_name like '%send_outbox%';
