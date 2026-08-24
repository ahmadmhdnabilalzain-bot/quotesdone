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

-- P05 / §8.B. THE LITERAL WAS A FACT ABOUT 20 AUG 2026, NOT A FACT ABOUT THIS FILE.
--
-- This block read:
--   if v_anon <> 56 or v_auth <> 59 then raise exception 'E4 down did not restore the prior state…'
-- over a count of EVERY SECURITY DEFINER routine in public — 835 of them today. 56 and 59 were
-- correct arithmetic over the population of 20 Aug 2026 at 02:27 UTC and are wrong now only because
-- the population grew: phase_d_f21 granted authenticated EXECUTE on fn_founder_command_clarify and
-- fn_founder_command_control, and phase_d_g01 on fn_phase_c_freeze_amendment_approve. All three come
-- AFTER e4 in scripts/sql/MANIFEST.txt (e4 at :1511, f21 at :1575, g01 at :1604) and E4 never
-- touched any of them. So the rehearsal reported "expected 56 anon / 59 authenticated, got 56 / 62"
-- and the down would have refused to run when it was needed.
--
-- UPDATING 59 TO 62 WOULD BE THE WRONG FIX, and it is worth saying exactly why. 62 is a reading of
-- the estate, not a statement about what this file put back. A TOTAL cannot distinguish "restored
-- correctly" from "broke three of my own 57 and gained three elsewhere" — it would go GREEN over a
-- broken rollback. And the next legitimate grant to an unrelated routine makes it wrong again, the
-- same silent way 59 went wrong.
--
-- The assertion below is a DELTA over the 57 routines THIS FILE NAMES, derived from the file's own
-- grant statements rather than from any reading of today's estate:
--   * 56 anon-affecting statements  (55 `to public`, which confers on both roles, + fn_os_open_access)
--   * 57 auth-affecting statements  (the same 56, + fn_goal_attainment)
-- and it also refuses collateral movement: no routine OUTSIDE the named set may have changed in
-- either direction.

create temporary table if not exists e4_down_before on commit drop as
select p.oid, p.proname,
       has_function_privilege('anon',          p.oid, 'EXECUTE') as anon_x,
       has_function_privilege('authenticated', p.oid, 'EXECUTE') as auth_x
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public' and p.prosecdef;


-- P05 / §8.B. THE LITERAL WAS A FACT ABOUT 20 AUG 2026, NOT A FACT ABOUT THIS FILE.
--
-- This block read:
--   if v_anon <> 56 or v_auth <> 59 then raise exception 'E4 down did not restore the prior state…'
-- over a count of EVERY SECURITY DEFINER routine in public — 835 of them today. 56 and 59 were
-- correct arithmetic over the population of 20 Aug 2026 at 02:27 UTC and are wrong now only because
-- the population grew: phase_d_f21 granted authenticated EXECUTE on fn_founder_command_clarify and
-- fn_founder_command_control, and phase_d_g01 on fn_phase_c_freeze_amendment_approve. All three come
-- AFTER e4 in scripts/sql/MANIFEST.txt (e4 at :1511, f21 at :1575, g01 at :1604) and E4 never
-- touched any of them. So the rehearsal reported "expected 56 anon / 59 authenticated, got 56 / 62"
-- and the down would have refused to run when it was needed.
--
-- UPDATING 59 TO 62 WOULD BE THE WRONG FIX, and it is worth saying exactly why. 62 is a reading of
-- the estate, not a statement about what this file put back. A TOTAL cannot distinguish "restored
-- correctly" from "broke three of my own 57 and gained three elsewhere" — it would go GREEN over a
-- broken rollback. And the next legitimate grant to an unrelated routine makes it wrong again, the
-- same silent way 59 went wrong.
--
-- The assertion below is a DELTA over the 57 routines THIS FILE NAMES, derived from the file's own
-- grant statements rather than from any reading of today's estate:
--   * 56 anon-affecting statements  (55 `to public`, which confers on both roles, + fn_os_open_access)
--   * 57 auth-affecting statements  (the same 56, + fn_goal_attainment)
-- and it also refuses collateral movement: no routine OUTSIDE the named set may have changed in
-- either direction.

create temporary table if not exists e4_down_before on commit drop as
select p.oid, p.proname,
       has_function_privilege('anon',          p.oid, 'EXECUTE') as anon_x,
       has_function_privilege('authenticated', p.oid, 'EXECUTE') as auth_x
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public' and p.prosecdef;


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
declare
  v_named    text[] := array['fn_action_policies', 'fn_approval_trace_audit', 'fn_capability_verify', 'fn_category_knowledge', 'fn_category_questions', 'fn_decision_conflict_scan', 'fn_decision_outcomes', 'fn_emit', 'fn_emit_task_assigned', 'fn_event_consolidate', 'fn_execution_run', 'fn_execution_sweep', 'fn_founder_command_trace_guard', 'fn_graph_supplier_market', 'fn_improvement_handover', 'fn_improvement_plan_refresh', 'fn_index_slowdown_watch', 'fn_intake_slug_for_catalog', 'fn_kernel_handoff_run_trace_guard', 'fn_learning_loop_sweep', 'fn_os_health_brief', 'fn_os_knowledge_query', 'fn_os_objective_measure', 'fn_owning_os', 'fn_phase_b_invariants', 'fn_phase_c_event_binding_status_guard', 'fn_phase_c_task_trace_guard', 'fn_pick_reviewer', 'fn_promote_memory_sweep', 'fn_rating_due', 'fn_regulation_watch', 'fn_report_drilldown', 'fn_report_recommendation_approve', 'fn_route_party', 'fn_supplier_advisor', 'fn_supplier_certifications', 'fn_supplier_market', 'fn_supplier_negotiation', 'fn_supplier_network_map', 'fn_supplier_product_match', 'fn_supplier_products', 'fn_supplier_quality', 'fn_supplier_risk_monitor', 'fn_supplier_tier', 'fn_supplier_workspaces', 'fn_task_approve', 'fn_task_lesson', 'fn_task_review', 'fn_workflow_start', 'fn_workflow_start_due', 'fn_workflow_step_done', 'fn_ws_company_os', 'fn_ws_intelligence', 'fn_ws_live_company', 'fn_ws_notifications', 'fn_os_open_access', 'fn_goal_attainment'];
  v_anon_moved int; v_auth_moved int; v_collateral text; v_missed text;
begin
  select count(*) filter (where not b.anon_x and has_function_privilege('anon',          p.oid,'EXECUTE')),
         count(*) filter (where not b.auth_x and has_function_privilege('authenticated', p.oid,'EXECUTE'))
    into v_anon_moved, v_auth_moved
    from e4_down_before b join pg_proc p on p.oid = b.oid;

  if v_anon_moved <> 56 or v_auth_moved <> 57 then
    raise exception 'E4 down opened % anon and % authenticated grant(s); this file issues 56 anon-affecting and 57 authenticated-affecting statements over % named routines',
      v_anon_moved, v_auth_moved, cardinality(v_named);
  end if;

  -- Nothing outside the named set may have moved, in either direction.
  select string_agg(distinct b.proname, ', ') into v_collateral
    from e4_down_before b join pg_proc p on p.oid = b.oid
   where (b.anon_x is distinct from has_function_privilege('anon',          p.oid,'EXECUTE')
       or b.auth_x is distinct from has_function_privilege('authenticated', p.oid,'EXECUTE'))
     and not (b.proname = any (v_named));
  if v_collateral is not null then
    raise exception 'E4 down moved a grant on a routine it does not name: %', v_collateral;
  end if;

  -- And every routine it names must actually hold what it granted.
  select string_agg(distinct p.proname, ', ') into v_missed
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.prosecdef
     and p.proname = any (v_named)
     and not has_function_privilege('authenticated', p.oid, 'EXECUTE');
  if v_missed is not null then
    raise exception 'E4 down did not restore: %', v_missed;
  end if;
end
$ctl$;
