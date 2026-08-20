-- =================================================================================================
-- Phase D — E8. The view handed back what the table withheld.
--
-- E4 closed the SECURITY DEFINER function door. This is the same door one layer up, and Phase D
-- built it: a SECURITY DEFINER VIEW reads as its OWNER, so a grant on the view returns exactly the
-- rows the grant on its base table was written to withhold.
--
-- THE SELF-CONTRADICTION, both halves in one file. scripts/sql/phase_d_d2_business_object_map.sql:
--
--   :722  revoke all on public.phase_d_object_record from public, anon, authenticated;
--   :723  grant select on public.phase_d_object_record to service_role;
--         -- "The store is written only through the service, which is SECURITY DEFINER."
--
--   :473  execute format('revoke all on public.v_obj_%s from public, anon, authenticated', …);
--   :474  execute format('grant select on public.v_obj_%s to service_role, authenticated', …);
--
-- Line 722 closes the store to a signed-in caller. Line 474 opens thirty views over that same store
-- to the same caller. Every one of the 30 is defined as
-- `select … from public.phase_d_object_record where object_id = '<x>'`, none carries
-- `security_invoker = true` (measured: 210 of 210 views in public are definer views), and
-- `phase_d_object_record` has RLS enabled with ZERO policies — deny-all, which a definer view reads
-- straight past. Measured on production 2026-08-20:
--
--     phase_d_object_record   authenticated SELECT = false        <- the revoke worked
--     30 x v_obj_*            authenticated SELECT = true         <- and was handed back
--     acl on each view        postgres=arwdDxtm | service_role=arwdDxtm | authenticated=r
--
-- The `authenticated=r` is an EXPLICIT grant, not one held through PUBLIC, so it was deliberate.
--
-- IT ALSO DEFEATS d43. `phase_d_d43_a_signed_in_caller_may_not_name_the_owner.sql` revoked
-- `fn_phase_d_object_read(jsonb)` to service_role precisely so a signed-in caller could not read
-- another party's Phase D object records. The function door closed; the view door beside it did not,
-- and PostgREST exposes every view in `public` as an endpoint. A signed-in customer or supplier JWT
-- could GET /rest/v1/v_obj_financial_close, /v_obj_supplier_verification_case,
-- /v_obj_organization_change_request and 27 more.
--
-- WHY NOTHING HAS LEAKED, AND WHY THAT IS NOT THE ARGUMENT FOR LEAVING IT.
-- `phase_d_object_record` holds 0 rows, so every one of the thirty returns an empty array today.
-- That is the D35 finding word for word: a zero cannot tell a dead guard from an idle system, and
-- the first committed Phase D object changes the payload, not the permission.
--
-- WHO NEEDS THE GRANT: measured, and it is nobody.
--   `v_obj_` in supabase/functions, src and scripts (excluding scripts/sql)     0 occurrences
--   database routines with `from public.v_obj_…` in a comment-stripped body     0
--   service_role SELECT on all 30                                              true, and untouched
--
-- Two siblings are revoked with them for the same reason — an explicit grant to `authenticated` with
-- no caller anywhere:
--   public.phase_d_business_object_binding  (d2:720)  the object registry and its policies
--   public.fn_phase_d_object_state()        (d2:717)  a board reader; SECURITY INVOKER, so it could
--                                                     not read the store anyway, and the grant is
--                                                     still unearned
-- Every reference to either is in scripts/phase_d/build_*.mjs, which use the MANAGEMENT API and run
-- as postgres. None uses a client JWT.
--
-- SCOPE BOUNDARY. This file covers the 30 `v_obj_*` views, one table and one routine, all created by
-- Phase D's d2. It says nothing about the other 180 views in `public` — they are 180 definer views
-- too, and NONE of them is selectable by anon or by authenticated, which is why they are not here.
-- The complete measured surface after this file, asserted by the control block rather than claimed:
-- anon can SELECT 2 relations of 574 in `public` (`blog_posts`, `category_specs`, both public site
-- content) and 0 views; authenticated can SELECT 0 views.
-- =================================================================================================

revoke select on public.v_obj_ai_change from public, anon, authenticated;
revoke select on public.v_obj_capability_case from public, anon, authenticated;
revoke select on public.v_obj_content_campaign from public, anon, authenticated;
revoke select on public.v_obj_customer_case from public, anon, authenticated;
revoke select on public.v_obj_customer_selection from public, anon, authenticated;
revoke select on public.v_obj_customer_terms_acceptance from public, anon, authenticated;
revoke select on public.v_obj_dispatch_batch from public, anon, authenticated;
revoke select on public.v_obj_document_extraction from public, anon, authenticated;
revoke select on public.v_obj_exception_record from public, anon, authenticated;
revoke select on public.v_obj_financial_close from public, anon, authenticated;
revoke select on public.v_obj_growth_program from public, anon, authenticated;
revoke select on public.v_obj_inquiry_route_set from public, anon, authenticated;
revoke select on public.v_obj_inquiry_version from public, anon, authenticated;
revoke select on public.v_obj_intelligence_product from public, anon, authenticated;
revoke select on public.v_obj_knowledge_change from public, anon, authenticated;
revoke select on public.v_obj_notification_attempt from public, anon, authenticated;
revoke select on public.v_obj_organization_change_request from public, anon, authenticated;
revoke select on public.v_obj_performance_recovery_case from public, anon, authenticated;
revoke select on public.v_obj_product_change from public, anon, authenticated;
revoke select on public.v_obj_quotation_evaluation from public, anon, authenticated;
revoke select on public.v_obj_quotation_revision from public, anon, authenticated;
revoke select on public.v_obj_reconciliation_case from public, anon, authenticated;
revoke select on public.v_obj_release_candidate from public, anon, authenticated;
revoke select on public.v_obj_supplier_correction_case from public, anon, authenticated;
revoke select on public.v_obj_supplier_coverage_case from public, anon, authenticated;
revoke select on public.v_obj_supplier_retention_case from public, anon, authenticated;
revoke select on public.v_obj_supplier_safe_package from public, anon, authenticated;
revoke select on public.v_obj_supplier_terms_acceptance from public, anon, authenticated;
revoke select on public.v_obj_supplier_verification_case from public, anon, authenticated;
revoke select on public.v_obj_ux_specification from public, anon, authenticated;

revoke select  on public.phase_d_business_object_binding from public, anon, authenticated;
revoke execute on function public.fn_phase_d_object_state() from public, anon, authenticated;

-- -------------------------------------------------------------------------------------------------
-- In the same transaction as the revokes, read-only, and it raises rather than reporting.
-- -------------------------------------------------------------------------------------------------
do $e8$
declare
  v_open int; v_names text; v_service int; v_anon_rel int; v_auth_view int;
begin
  select count(*), coalesce(string_agg(c.relname, ', ' order by c.relname), '')
    into v_open, v_names
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relkind = 'v' and c.relname like 'v\_obj\_%'
     and (has_table_privilege('anon', c.oid, 'SELECT')
       or has_table_privilege('authenticated', c.oid, 'SELECT'));
  if v_open <> 0 then
    raise exception 'E8: % v_obj_* view(s) still answer a client role: %. A revoke naming only anon '
      'against a PUBLIC grant is a no-op — name public first.', v_open, v_names;
  end if;

  select count(*) into v_service
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relkind = 'v' and c.relname like 'v\_obj\_%'
     and has_table_privilege('service_role', c.oid, 'SELECT');
  if v_service <> 30 then
    raise exception 'E8: service_role can select only % of the 30 v_obj_* views. The deliverable '
      'builders and fn_phase_d_object_read run as service_role and would now fail.', v_service;
  end if;

  if has_table_privilege('authenticated', 'public.phase_d_business_object_binding', 'SELECT')
     or has_function_privilege('authenticated', 'public.fn_phase_d_object_state()', 'EXECUTE') then
    raise exception 'E8: the two sibling grants did not go.';
  end if;

  -- The estate-wide reading this file claims in its header, asserted rather than left in prose.
  select count(*) into v_anon_rel
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relkind in ('r','p','v','m')
     and has_table_privilege('anon', c.oid, 'SELECT');
  select count(*) into v_auth_view
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relkind in ('v','m')
     and has_table_privilege('authenticated', c.oid, 'SELECT');
  if v_anon_rel <> 2 or v_auth_view <> 0 then
    raise exception 'E8: expected anon to reach 2 relations and authenticated 0 views in public; '
      'measured % and %.', v_anon_rel, v_auth_view;
  end if;
end
$e8$;
