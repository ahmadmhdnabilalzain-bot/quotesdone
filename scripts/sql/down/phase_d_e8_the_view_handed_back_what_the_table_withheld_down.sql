-- =================================================================================================
-- DOWN for scripts/sql/phase_d_e8_the_view_handed_back_what_the_table_withheld.sql
--
-- Restores the exact prior grants, which were EXPLICIT role grants and not held through PUBLIC:
-- `authenticated=r` on each of the 30 `v_obj_*` views and on `phase_d_business_object_binding`, and
-- `authenticated=X` on `fn_phase_d_object_state()`. Re-granting to PUBLIC would be a WIDER estate
-- than the one E8 closed, so PUBLIC is not named here at all.
--
-- RUNNING THIS RE-OPENS THIRTY SECURITY DEFINER VIEWS OVER public.phase_d_object_record TO ANY
-- SIGNED-IN JWT, through PostgREST, past an RLS policy set that is deny-all. It also re-defeats
-- phase_d_d43_a_signed_in_caller_may_not_name_the_owner.sql, which revoked the function door to the
-- same data. `scripts/checks/anon_cannot_execute_security_definer.test.mjs` will go red, and it is
-- supposed to. Read E8's header before you run this.
-- =================================================================================================

grant select on public.v_obj_ai_change to authenticated;
grant select on public.v_obj_capability_case to authenticated;
grant select on public.v_obj_content_campaign to authenticated;
grant select on public.v_obj_customer_case to authenticated;
grant select on public.v_obj_customer_selection to authenticated;
grant select on public.v_obj_customer_terms_acceptance to authenticated;
grant select on public.v_obj_dispatch_batch to authenticated;
grant select on public.v_obj_document_extraction to authenticated;
grant select on public.v_obj_exception_record to authenticated;
grant select on public.v_obj_financial_close to authenticated;
grant select on public.v_obj_growth_program to authenticated;
grant select on public.v_obj_inquiry_route_set to authenticated;
grant select on public.v_obj_inquiry_version to authenticated;
grant select on public.v_obj_intelligence_product to authenticated;
grant select on public.v_obj_knowledge_change to authenticated;
grant select on public.v_obj_notification_attempt to authenticated;
grant select on public.v_obj_organization_change_request to authenticated;
grant select on public.v_obj_performance_recovery_case to authenticated;
grant select on public.v_obj_product_change to authenticated;
grant select on public.v_obj_quotation_evaluation to authenticated;
grant select on public.v_obj_quotation_revision to authenticated;
grant select on public.v_obj_reconciliation_case to authenticated;
grant select on public.v_obj_release_candidate to authenticated;
grant select on public.v_obj_supplier_correction_case to authenticated;
grant select on public.v_obj_supplier_coverage_case to authenticated;
grant select on public.v_obj_supplier_retention_case to authenticated;
grant select on public.v_obj_supplier_safe_package to authenticated;
grant select on public.v_obj_supplier_terms_acceptance to authenticated;
grant select on public.v_obj_supplier_verification_case to authenticated;
grant select on public.v_obj_ux_specification to authenticated;

grant select  on public.phase_d_business_object_binding to authenticated;
grant execute on function public.fn_phase_d_object_state() to authenticated;

do $ctl$
declare v int;
begin
  select count(*) into v
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relkind = 'v' and c.relname like 'v\_obj\_%'
     and has_table_privilege('authenticated', c.oid, 'SELECT');
  if v <> 30 then
    raise exception 'E8 down did not restore the prior state: % of 30 v_obj_* views are '
      'authenticated-selectable', v;
  end if;
end
$ctl$;
