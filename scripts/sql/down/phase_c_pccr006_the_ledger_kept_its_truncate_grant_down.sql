-- DOWN. RE-GRANT TRUNCATE ON THE GOVERNANCE LEDGER.
--
-- NO TRANSACTION CONTROL. One statement.
--
-- APPLYING THIS RE-OPENS THE OTHER DOOR on public.phase_c_governance_decision: the append-only
-- ledger PCCR-006 created becomes emptiable by one statement, and
-- fn_kernel_truncate_protection_state :: enforcing_tables_still_granting_truncate goes red again.
-- It exists so the change is reversible, not because reverting is advisable.

GRANT TRUNCATE ON public.phase_c_governance_decision TO service_role;
