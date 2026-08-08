-- AUDIT 3 Aug 2026 — close the Supabase advisor finding on fn_supplier_matchable.
--
-- fn_supplier_matchable(bigint) is SECURITY DEFINER and, like every function created without an
-- explicit grant, carried the PostgreSQL default of EXECUTE to PUBLIC. PUBLIC includes `anon` and
-- `authenticated`, and PostgREST exposes every executable function at /rest/v1/rpc/, so any
-- unauthenticated caller could ask the platform "is supplier N matchable?" and get a definitive
-- answer computed with the definer's privileges — a public read of an internal policy decision,
-- and a cheap enumeration oracle over 20,464 lead ids.
--
-- Verified before revoking, not assumed: `fn_supplier_matchable` appears NOWHERE in the repository
-- outside its own two migrations — not in src/, not in any of the 190 edge functions. The comment
-- on the 20260803181750 migration claiming "edge functions call it by this signature" is wrong.
-- Nothing breaks. service_role (which every edge function runs as) keeps EXECUTE, so the function
-- remains available the moment something does call it.
--
-- Deliberately NOT revoked here: fn_is_matchable, fn_matching_strike_limit and fn_match_capability
-- also default to PUBLIC EXECUTE, but all three are SECURITY INVOKER — RLS still applies to them —
-- and match_suppliers / match_suppliers_kw delegate to fn_is_matchable. Revoking those is a
-- behaviour change to the live matching path, not an advisor fix, and must be proved separately.

revoke execute on function public.fn_supplier_matchable(bigint) from public;
revoke execute on function public.fn_supplier_matchable(bigint) from anon;
revoke execute on function public.fn_supplier_matchable(bigint) from authenticated;
grant  execute on function public.fn_supplier_matchable(bigint) to service_role;

comment on function public.fn_supplier_matchable(bigint) is
  'Canonical matchability by lead id. Delegates to fn_is_matchable — holds no eligibility logic of '
  'its own. SECURITY DEFINER, therefore NOT executable by anon or authenticated (revoked 3 Aug '
  '2026); service_role only. It currently has no caller anywhere in the repository.';;
