-- F21 - the founder needs a grant to use his own token
--
-- F20 made public.fn_phase_c_require_founder resolve the founder from a VERIFIED auth subject:
-- route A is auth.uid(), route B is a subject os_api verified and bound. os_api now takes route A
-- for the two founder-command routines -- it builds a client carrying the caller's own bearer token
-- so PostgREST hands the database the subject it verified.
--
-- Route A goes through PostgREST as the `authenticated` role, and `authenticated` holds EXECUTE on
-- neither routine. Measured before this file: both grant EXECUTE to postgres and service_role only.
-- So route A would have returned 42501 for the founder himself, and the only thing that could still
-- reach these routines would be service_role -- which is exactly the credential the whole change
-- exists to stop being sufficient.
--
-- WHY GRANTING `authenticated` IS NOT A WIDENING. Before F20 these routines accepted any string
-- service_role typed; after it they refuse every caller whose verified auth subject does not resolve
-- to an enabled founder identity, with SQLSTATE 28000. A signed-in customer or supplier calling
-- fn_founder_command_control gets "not the founder: no verified auth subject on this call" -- and so
-- does anyone holding service_role, because service_role has no auth.uid() and cannot bind a subject
-- it has not verified. The grant is what makes the FOUNDER able to use the routine; the routine is
-- what makes everyone else unable to.
--
-- WHAT IS NOT GRANTED, and it is the list that matters:
--   * fn_phase_c_founder_subject_bind stays service_role-only. Route B is the server path and
--     nothing else may take it.
--   * fn_refund_decide stays service_role-only. Its founder check is a TRIGGER on public.refunds
--     (fn_phase_c_refund_decision_guard) which runs in the writer's transaction, so the server that
--     writes the refund is the one that must carry the verified subject. Granting it to
--     `authenticated` would be handing a browser a route to a money movement, and the founder's
--     standing rule -- every refund needs him, at any amount -- is not served by making the call
--     easier to reach.
--   * fn_kernel_cancel stays service_role-only for the same reason: it is called by the estate, not
--     by a browser.
--
-- fn_phase_c_require_founder itself is granted to `authenticated` so that a founder session can ask
-- "am I the founder?" without a mutation. It answers with an identity or raises 28000; it changes
-- nothing.

GRANT EXECUTE ON FUNCTION public.fn_founder_command_clarify(bigint, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_founder_command_control(bigint, text, text, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fn_phase_c_require_founder(text) TO authenticated;

-- Stated as REVOKEs so a future re-apply of an older grant file cannot quietly widen them, and so
-- the file says out loud which doors it is keeping shut. anon holds nothing here and keeps nothing.
REVOKE ALL ON FUNCTION public.fn_phase_c_founder_subject_bind(uuid) FROM anon, authenticated;
REVOKE ALL ON FUNCTION public.fn_refund_decide(bigint, boolean, text, text) FROM anon, authenticated;
REVOKE ALL ON FUNCTION public.fn_kernel_cancel(jsonb) FROM anon, authenticated;
REVOKE ALL ON FUNCTION public.fn_founder_command_clarify(bigint, text, text) FROM anon;
REVOKE ALL ON FUNCTION public.fn_founder_command_control(bigint, text, text, text, text) FROM anon;
REVOKE ALL ON FUNCTION public.fn_phase_c_require_founder(text) FROM anon;
