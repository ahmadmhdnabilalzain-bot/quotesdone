-- THE EMPLOYEE'S WHOLE EMPLOYMENT CONTEXT WAS READABLE WITH THE ANON KEY.
--
-- Found in the end-of-session sweep on 11 Aug 2026, by asking has_function_privilege() directly
-- rather than trusting that a revoke had happened:
--
--   fn_agent_context_capped(text, integer)         anon=false  authenticated=false   locked
--   fn_agent_context_capped(text, integer, text)   anon=TRUE   authenticated=TRUE    OPEN
--
-- It is SECURITY DEFINER and it returns identity, the company genome, the live risk register, the
-- employee record, authority limits and LAYER 3 live operational state. With the publishable key
-- and one RPC call, any visitor could read all of it for any agent_key.
--
-- THE CAUSE IS THE TRAP THIS REPOSITORY ALREADY WRITES DOWN. A new SIGNATURE is a new function, so
-- adding the 3-argument overload was a CREATE, and CREATE grants EXECUTE to PUBLIC. The 2-argument
-- original had been revoked when it was created; the overload inherited nothing and nobody revoked
-- it. CREATE OR REPLACE preserves the ACL, which is why every later edit to this function kept the
-- hole exactly as it was.
--
-- REVOKE FROM PUBLIC, NOT FROM ANON. `revoke ... from anon` is a silent no-op when the grant is held
-- through PUBLIC — the second trap in the same list, and the reason this line names public.

revoke execute on function public.fn_agent_context_capped(text, integer, text) from public;

-- The same question, asked of every SECURITY DEFINER routine that assembles or exposes an agent's
-- context, because one overload being open makes "the others are fine" a guess:
revoke execute on function public.fn_agent_context(text, integer, text) from public;
revoke execute on function public.fn_agent_context(text, integer) from public;
