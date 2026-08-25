-- Q06 DOWN. RE-GRANT PUBLIC ON trg_customer_registered_kernel.
--
-- NO TRANSACTION CONTROL. Two statements.
--
-- This restores the ACL Postgres gave the function when phase_d_q03 created it: EXECUTE to PUBLIC.
--
-- APPLYING THIS RE-OPENS THE SURFACE and turns
-- scripts/checks/anon_cannot_execute_security_definer.test.mjs red again on two assertions. It
-- exists so Q06 is reversible, not because reverting is advisable.

REVOKE EXECUTE ON FUNCTION public.trg_customer_registered_kernel() FROM service_role;
GRANT EXECUTE ON FUNCTION public.trg_customer_registered_kernel() TO PUBLIC;
