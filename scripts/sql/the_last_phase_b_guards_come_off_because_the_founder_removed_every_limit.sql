-- THE LAST PHASE B GUARDS COME OFF
--
-- Founder ruling, 7 Sep 2026, in his words: "phase A to D where steps to make sure the structure
-- was fine. their freezes or implied limits should be removed totally. i dont want any limits in
-- the workflow" and "the only thing on hold open router. any other limit or freeze or gates that is
-- affecting us should be removed. otherwise we will never be able to finish this code".
--
-- The z90_phase_b_freeze digest guard was already removed on 2 Sep. What survived it were three
-- statement guards that refuse a change to workflow ownership, step ownership and handoff
-- accountability unless a Phase B change reason is set in the same transaction. Those are the exact
-- edits the live organisation now needs -- roles have been merged and parked since the register was
-- written -- so they are limits on the workflow, and they come off.
--
-- WHAT IS NOT REMOVED, deliberately: the append-only triggers on org_phase_baseline and
-- phase_b_change_request. Those do not refuse any workflow change; they only stop history being
-- rewritten after the fact. A record of what was decided is not a limit on what may be decided.
-- The OpenRouter hold is also untouched -- the founder named it as the one thing still on hold.
drop trigger if exists a10_phase_b_workflow_owner_guard on public.phase_b_workflow;
drop trigger if exists a10_phase_b_owner_guard on public.phase_b_workflow_step;
drop trigger if exists a10_phase_b_handoff_guard on public.phase_b_handoff;
drop function if exists public.fn_phase_b_workflow_owner_guard();
drop function if exists public.fn_phase_b_owner_guard();
drop function if exists public.fn_phase_b_handoff_guard();
