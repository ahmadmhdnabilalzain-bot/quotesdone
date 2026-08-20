-- =================================================================================================
-- DOWN for scripts/sql/phase_d_e4_the_door_was_never_a_browser.sql
--
-- Restores the EXACT prior grant state measured on htdblwldjkcgjvmqkbeh at 2026-08-20 02:27 UTC,
-- not a uniform one: 55 of the 57 held EXECUTE through PUBLIC (ACL `=X/postgres`), while
-- fn_os_open_access held an explicit anon + authenticated grant and fn_goal_attainment an explicit
-- authenticated grant. Re-granting all 57 to PUBLIC would be a WIDER estate than the one this file
-- reverses, so the two explicit ones are restored as they actually were.
--
-- Running this re-opens 56 SECURITY DEFINER routines to unauthenticated callers. Read
-- scripts/checks/anon_cannot_execute_security_definer.test.mjs before you do — it will go red, and
-- it is supposed to.
--
-- fn_customer_documents and fn_customer_document_refs are absent from both files. The up-file never
-- touched them; there is nothing here to put back.
-- =================================================================================================

grant execute on function public.fn_action_policies(p_kind text, p_confidence numeric)                                 to public;
grant execute on function public.fn_approval_trace_audit()                                                             to public;
grant execute on function public.fn_capability_verify()                                                                to public;
grant execute on function public.fn_category_knowledge(p_category text)                                                to public;
grant execute on function public.fn_category_questions(p_category text, p_lang text, p_limit integer)                  to public;
grant execute on function public.fn_decision_conflict_scan()                                                           to public;
grant execute on function public.fn_decision_outcomes(p_kind text, p_days integer)                                     to public;
grant execute on function public.fn_emit(p_event_type text, p_entity_type text, p_entity_id text, p_actor text, p_payload jsonb) to public;
grant execute on function public.fn_emit_task_assigned(p_lookback_minutes integer)                                     to public;
grant execute on function public.fn_event_consolidate()                                                                to public;
grant execute on function public.fn_execution_run(p_limit integer)                                                     to public;
grant execute on function public.fn_execution_sweep(p_stall_minutes integer)                                           to public;
grant execute on function public.fn_founder_command_trace_guard()                                                      to public;
grant execute on function public.fn_graph_supplier_market()                                                            to public;
grant execute on function public.fn_improvement_handover(p_limit integer)                                              to public;
grant execute on function public.fn_improvement_plan_refresh()                                                         to public;
grant execute on function public.fn_index_slowdown_watch()                                                             to public;
grant execute on function public.fn_intake_slug_for_catalog(p_catalog_slug text)                                       to public;
grant execute on function public.fn_kernel_handoff_run_trace_guard()                                                   to public;
grant execute on function public.fn_learning_loop_sweep(p_limit integer)                                               to public;
grant execute on function public.fn_os_health_brief()                                                                  to public;
grant execute on function public.fn_os_knowledge_query(p_os_key text, p_topic text)                                    to public;
grant execute on function public.fn_os_objective_measure()                                                             to public;
grant execute on function public.fn_owning_os(p_agent text)                                                            to public;
grant execute on function public.fn_phase_b_invariants()                                                               to public;
grant execute on function public.fn_phase_c_event_binding_status_guard()                                               to public;
grant execute on function public.fn_phase_c_task_trace_guard()                                                         to public;
grant execute on function public.fn_pick_reviewer(p_dept_key text, p_author text)                                      to public;
grant execute on function public.fn_promote_memory_sweep(p_limit integer)                                              to public;
grant execute on function public.fn_rating_due(p_now timestamp with time zone)                                         to public;
grant execute on function public.fn_regulation_watch()                                                                 to public;
grant execute on function public.fn_report_drilldown(p_metric text, p_days integer)                                    to public;
grant execute on function public.fn_report_recommendation_approve(p_report_id bigint, p_index integer, p_by text, p_source text) to public;
grant execute on function public.fn_route_party(p_name text)                                                           to public;
grant execute on function public.fn_supplier_advisor(p_lead_id bigint)                                                 to public;
grant execute on function public.fn_supplier_certifications(p_lead_id bigint)                                          to public;
grant execute on function public.fn_supplier_market(p_lead_id bigint)                                                  to public;
grant execute on function public.fn_supplier_negotiation(p_quote_id uuid)                                              to public;
grant execute on function public.fn_supplier_network_map()                                                             to public;
grant execute on function public.fn_supplier_product_match(p_inquiry_id uuid, p_lead_id bigint)                        to public;
grant execute on function public.fn_supplier_products(p_lead_id bigint, p_query text)                                  to public;
grant execute on function public.fn_supplier_quality(p_lead_id bigint)                                                 to public;
grant execute on function public.fn_supplier_risk_monitor(p_signal text)                                               to public;
grant execute on function public.fn_supplier_tier(p_lead_id bigint)                                                    to public;
grant execute on function public.fn_supplier_workspaces(p_lead_id bigint)                                              to public;
grant execute on function public.fn_task_approve(p_dry_run boolean)                                                    to public;
grant execute on function public.fn_task_lesson(p_task_id bigint, p_outcome text, p_review jsonb)                      to public;
grant execute on function public.fn_task_review(p_task_id bigint)                                                      to public;
grant execute on function public.fn_workflow_start(p_workflow_key text, p_trigger_event_id bigint, p_entity_type text, p_entity_id text, p_context jsonb) to public;
grant execute on function public.fn_workflow_start_due(p_lookback_minutes integer)                                     to public;
grant execute on function public.fn_workflow_step_done(p_run uuid, p_step_no integer, p_output jsonb, p_status text)    to public;
grant execute on function public.fn_ws_company_os()                                                                    to public;
grant execute on function public.fn_ws_intelligence()                                                                  to public;
grant execute on function public.fn_ws_live_company()                                                                  to public;
grant execute on function public.fn_ws_notifications()                                                                 to public;
grant  execute on function public.fn_os_open_access()                                                                   to anon, authenticated;
grant  execute on function public.fn_goal_attainment(p_horizon text)                                                    to authenticated;

do $ctl$
declare v_anon int; v_auth int;
begin
  select count(*) filter (where has_function_privilege('anon', p.oid, 'EXECUTE')),
         count(*) filter (where has_function_privilege('authenticated', p.oid, 'EXECUTE'))
    into v_anon, v_auth
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.prosecdef;
  if v_anon <> 56 or v_auth <> 59 then
    raise exception 'E4 down did not restore the prior state: expected 56 anon / 59 authenticated, got % / %', v_anon, v_auth;
  end if;
end
$ctl$;
