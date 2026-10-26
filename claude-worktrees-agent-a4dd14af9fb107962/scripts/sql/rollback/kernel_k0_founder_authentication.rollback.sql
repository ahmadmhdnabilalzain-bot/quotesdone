-- ROLLBACK for kernel_k0_founder_authentication.sql
--
-- Use only if the K0 gate fails and the Command Center must be returned to its pre-K0 signatures.
--
-- WHAT THIS DOES RESTORE: the two-argument fn_founder_command_clarify and the four-argument
-- fn_founder_command_control, so a rolled-back supabase/functions/os_api/index.ts (which calls them
-- without an actor) works again.
--
-- WHAT THIS DELIBERATELY DOES NOT RESTORE: the open door. The build-mode identity row stays
-- inactive, os_open_access_log keeps its 'closed' row, and the human-only trigger stays. Reverting
-- an authentication fix by re-opening an unauthenticated path to the founder's command channel is
-- not a rollback, it is a second incident. If the door genuinely has to be reopened, that is a
-- founder decision recorded as its own migration, not a side effect of this file.
--
-- The restored bodies below are the definitions read back out of production on 17 Aug 2026 before
-- K0 was applied — byte-for-byte, minus the actor check.

begin;

-- The three/five-argument entry points go first, so there is never a moment with no clarify at all.
drop function if exists public.fn_founder_command_clarify(bigint, text, text);
drop function if exists public.fn_founder_command_control(bigint, text, text, text, text);

\echo 'RESTORE the pre-K0 bodies from git before committing this rollback:'
\echo '  git show ce46b03:scripts/sql/phase_c_34_clarification_path.sql   -- fn_founder_command_clarify(bigint,text)'
\echo '  git show ce46b03:scripts/sql/phase_c_15_cancel_writes_trace_and_selftest_cleanup.sql'
\echo '                                                                  -- fn_founder_command_control(bigint,text,text,text)'
\echo 'Apply those two files, then this transaction.'

-- fn_phase_c_require_founder is left in place. Nothing breaks if it is unused, and removing the one
-- routine that can answer "is this the founder?" is never the safe direction.

commit;
