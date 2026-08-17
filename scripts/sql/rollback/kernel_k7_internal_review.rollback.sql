-- ROLLBACK for kernel_k7_internal_review.sql
--
-- Drops the kernel review service and its independence test. It changes no data: K7 added no
-- columns, no triggers and no rows, and the pre-existing checks
-- (fn_phase_c_reviewer_independent, fn_pick_reviewer, trg_review_chain_no_self_review) were left
-- untouched, so removing these three routines returns the estate exactly to its pre-K7 behaviour.
--
-- Note what is LOST by running it: fn_kernel_reviewer_independent is the only test that asks BOTH
-- identity vocabularies. 149 of 180 canonical roles resolve differently under fn_org_agent_resolve
-- and fn_phase_c_resolve_actor; after this rollback, independence is decided by whichever resolver
-- the caller happens to use.

begin;

drop function if exists public.fn_kernel_review_integrity();
drop function if exists public.fn_kernel_review_decide(jsonb);
drop function if exists public.fn_kernel_reviewer_independent(text, text);

commit;
