-- F27 - the verifier needs no grant of its own
--
-- F21 granted `authenticated` EXECUTE on three routines so that route A -- the founder's own bearer
-- token reaching PostgREST, where auth.uid() resolves -- could work at all. Two of the three are
-- called from a browser session through os_api and need it. The third does not:
--
--     public.fn_phase_c_require_founder(text)
--
-- Nothing calls it from outside the database. Its four callers are all SECURITY DEFINER routines --
-- fn_kernel_cancel, fn_founder_command_clarify, fn_founder_command_control and
-- fn_phase_c_refund_decision_guard -- and a SECURITY DEFINER routine executes it as its owner, not
-- as the caller. I granted it so a founder session could ask "am I the founder?" without a mutation.
-- That is a convenience nobody asked for, and it widens the pinned set that
-- anon_cannot_execute_security_definer.test.mjs exists to hold at exactly two.
--
-- auth.uid() still resolves inside the routine when a bearer token reached PostgREST, because the
-- CALLER of the outer routine is what PostgREST authenticated; the grant on the inner one is
-- irrelevant to that. So this removes a door and changes no behaviour.

REVOKE ALL ON FUNCTION public.fn_phase_c_require_founder(text) FROM anon, authenticated;
