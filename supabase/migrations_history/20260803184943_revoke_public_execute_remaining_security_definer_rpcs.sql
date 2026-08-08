-- AUDIT 3 Aug 2026 — the other six SECURITY DEFINER functions PostgREST was publishing.
--
-- Revoking fn_supplier_matchable earlier today closed one advisor finding and left six of exactly
-- the same class. They are not all the same severity, and one of them is not an information leak
-- at all:
--
--   fn_resync_supplier_registration_state()  returns integer, VOLATILE, WRITES, and was callable
--     by `anon` with no argument at POST /rest/v1/rpc/. An unauthenticated caller could force a
--     full resync of registration state across 20,464 leads, as often as they liked. That is an
--     unauthenticated write and a free amplification primitive, not merely a disclosure.
--   fn_supplier_registration_state(bigint)   STABLE, but SECURITY DEFINER: it answers, for any
--     lead id, whether that business is registered, what it still owes and what it may do. Public
--     enumeration of every supplier's commercial standing.
--   fn_phase1_status(), fn_phase1_disarmed()  publish the platform's own containment posture to
--     anonymous callers. Nothing outside the operator needs to know whether Phase 1 is disarmed.
--   fn_rfq_required_check(public.inquiries)  publishes the RFQ policy decision itself.
--   scrub_inquiry_contacts()                 returns trigger, so PostgREST refuses to call it in
--     practice; revoked anyway, because "the router happens to reject it" is not an access control.
--
-- Verified before revoking, not assumed. Across src/ and all 190 edge functions the only caller of
-- any of these six is supplier_api -> fn_supplier_registration_state, and supplier_api runs as
-- service_role, which keeps EXECUTE. The others have no caller anywhere; the SQL-internal uses
-- (triggers, views) run as the definer and are unaffected by role grants.

do $$
declare f text;
begin
  foreach f in array array[
    'public.fn_phase1_disarmed()',
    'public.fn_phase1_status()',
    'public.fn_resync_supplier_registration_state()',
    'public.fn_rfq_required_check(public.inquiries)',
    'public.fn_supplier_registration_state(bigint)',
    'public.scrub_inquiry_contacts()'
  ] loop
    execute format('revoke execute on function %s from public', f);
    execute format('revoke execute on function %s from anon', f);
    execute format('revoke execute on function %s from authenticated', f);
    execute format('grant  execute on function %s to service_role', f);
  end loop;
end $$;

comment on function public.fn_resync_supplier_registration_state() is
  'Operator-only bulk resync of leads.supplier_registration_state. VOLATILE and writing, therefore '
  'NOT executable by anon or authenticated (revoked 3 Aug 2026) - it was reachable unauthenticated '
  'at /rest/v1/rpc/ and would rewrite state for every lead on demand. service_role only.';;
