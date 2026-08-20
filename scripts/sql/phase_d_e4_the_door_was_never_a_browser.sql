-- =================================================================================================
-- Phase D — E4. The door was never a browser.
--
-- 19 Aug 2026, D35 closed seven SECURITY DEFINER routines that a probe had PROVED an unauthenticated
-- caller could execute, and left 56 more open behind a ratchet. The ratchet's own comment says why:
-- "each needs one look at its callers before its grant goes, and a blind sweep over 56 routines is
-- how a security tidy-up becomes an outage."
--
-- This file is that look, taken function by function, and then the sweep it licenses.
--
-- WHAT WAS MEASURED ON PRODUCTION, 20 Aug 2026 02:27–02:40 UTC
--
--   59 SECURITY DEFINER routines in public are executable by anon or authenticated.
--      56 by anon, 59 by authenticated, anon a strict subset. (The check's disclosed ceilings were
--      56 / 60; the authenticated figure measured 59, not 60.)
--   55 of them hold the grant through PUBLIC — ACL `=X/postgres`. `revoke ... from anon` against a
--      PUBLIC grant is a silent no-op, so `public` is named FIRST in every statement below.
--    4 hold an explicit role grant: fn_os_open_access (anon + authenticated),
--      fn_customer_documents, fn_customer_document_refs, fn_goal_attainment (authenticated).
--
-- EVERY CALL SITE IN THE REPOSITORY, enumerated rather than sampled. `X.rpc(` across
-- supabase/functions, src and scripts returns exactly three client identifiers:
--
--      279  admin.rpc(...)    service_role key — holds its own grant, unaffected by a revoke
--        4  asUser.rpc(...)   ANON key + the caller's Bearer JWT -> PostgREST role `authenticated`
--        1  sb.rpc(...)       service_role key (wa_templates_watch), not one of the 59
--
-- The four asUser calls are all in supabase/functions/customer_documents/index.ts, and they call
-- exactly two of the 59:
--
--      fn_customer_documents        index.ts:125, :167, :197
--      fn_customer_document_refs    index.ts:148
--
-- `grep -rn "\.rpc(" src/` still returns 0 for the whole frontend, and `rest/v1/rpc/` in src/
-- returns 0. The browser calls no database routine directly. The three literal `rest/v1/rpc/<name>`
-- paths anywhere in the tree are qa_suite's fn_smoke, phase_c/inventory.mjs's fn_x placeholder, and
-- the Phase D §8 probe deliberately calling fn_supplier_opportunities as anon — which D35 closed.
--
-- THREE REACHABILITY PATHS A GREP CANNOT SEE, each checked in the catalog rather than assumed:
--
--   RLS POLICY EXPRESSIONS are evaluated as the QUERYING role, so a policy calling one of these
--   needs the caller to hold EXECUTE. Exactly one does:
--       documents.documents_customer_select  ->  fn_customer_document_refs
--   That is the second, independent reason that routine keeps its `authenticated` grant.
--
--   SECURITY INVOKER ROUTINES run as their caller, so one of them calling a target would carry the
--   requirement inward. One pair exists — fn_artifact_review_valid -> fn_pick_reviewer — and it is
--   unreachable: fn_artifact_review_valid is a trigger function, its only trigger is
--   a00_artifact_review_author_is_not_reviewer on public.artifact_review, and neither anon nor
--   authenticated holds INSERT, UPDATE or DELETE on that table. Re-run as a set: joining all 57
--   targets to every SECURITY INVOKER routine in public and to the tables those routines trigger
--   returns ZERO rows where a client role can write. (Postgres checks EXECUTE on a trigger function
--   at CREATE TRIGGER, not at fire time, so the trigger function's own grant is not the question —
--   what it CALLS while running as its caller is.)
--
--   VIEWS AND MATERIALIZED VIEWS: no view definition in public references any of the 57.
--
--   OTHER SCHEMAS, checked after the fact rather than assumed away: joining all 57 names against
--   every routine and every view or matview OUTSIDE public — excluding only pg_catalog and
--   information_schema — and keeping only those anon or authenticated can execute or select,
--   returns ZERO rows. So nothing outside public carries the requirement inward either.
--
-- WHAT THIS FILE DOES NOT CLAIM. It covers EXECUTE on SECURITY DEFINER routines in schema `public`.
-- It says nothing about table grants, about RLS coverage, or about SECURITY INVOKER routines. Those
-- are separate subjects and were not measured here.
--
-- CONFIRMED FROM A THIRD SOURCE. Supabase's own security advisor, read after the apply, returns
-- exactly TWO `authenticated_security_definer_function_executable` findings — `fn_customer_document_refs`
-- and `fn_customer_documents` — and no others, against 30 pre-existing `security_definer_view`
-- errors and 607 `rls_enabled_no_policy` notices that this file does not touch.
--
-- THE TWO THAT STAY, and why leaving them is not an exception to the rule but the rule applied:
--   fn_customer_documents      a signed-in customer's own document list. Called with the customer's
--   fn_customer_document_refs  own JWT, and the second one is what the documents RLS policy uses to
--                              decide which rows that customer may see. Both are already scoped to
--                              `authenticated` explicitly and are NOT anon-executable. Revoking
--                              either breaks the customer portal's documents tab and, worse, would
--                              make an RLS policy raise rather than filter. They are correct as they
--                              stand; this file leaves them untouched and the check now pins them.
--
-- AFTER THIS FILE: 0 anon-executable, 2 authenticated-executable, of 791 SECURITY DEFINER routines
-- in public. service_role and postgres keep EXECUTE on all 57 — every real caller runs as one of
-- those two, so no product surface changes behaviour.
-- =================================================================================================

revoke execute on function public.fn_action_policies(p_kind text, p_confidence numeric)                                 from public, anon, authenticated;
revoke execute on function public.fn_approval_trace_audit()                                                             from public, anon, authenticated;
revoke execute on function public.fn_capability_verify()                                                                from public, anon, authenticated;
revoke execute on function public.fn_category_knowledge(p_category text)                                                from public, anon, authenticated;
revoke execute on function public.fn_category_questions(p_category text, p_lang text, p_limit integer)                  from public, anon, authenticated;
revoke execute on function public.fn_decision_conflict_scan()                                                           from public, anon, authenticated;
revoke execute on function public.fn_decision_outcomes(p_kind text, p_days integer)                                     from public, anon, authenticated;
revoke execute on function public.fn_emit(p_event_type text, p_entity_type text, p_entity_id text, p_actor text, p_payload jsonb) from public, anon, authenticated;
revoke execute on function public.fn_emit_task_assigned(p_lookback_minutes integer)                                     from public, anon, authenticated;
revoke execute on function public.fn_event_consolidate()                                                                from public, anon, authenticated;
revoke execute on function public.fn_execution_run(p_limit integer)                                                     from public, anon, authenticated;
revoke execute on function public.fn_execution_sweep(p_stall_minutes integer)                                           from public, anon, authenticated;
revoke execute on function public.fn_founder_command_trace_guard()                                                      from public, anon, authenticated;
revoke execute on function public.fn_goal_attainment(p_horizon text)                                                    from public, anon, authenticated;
revoke execute on function public.fn_graph_supplier_market()                                                            from public, anon, authenticated;
revoke execute on function public.fn_improvement_handover(p_limit integer)                                              from public, anon, authenticated;
revoke execute on function public.fn_improvement_plan_refresh()                                                         from public, anon, authenticated;
revoke execute on function public.fn_index_slowdown_watch()                                                             from public, anon, authenticated;
revoke execute on function public.fn_intake_slug_for_catalog(p_catalog_slug text)                                       from public, anon, authenticated;
revoke execute on function public.fn_kernel_handoff_run_trace_guard()                                                   from public, anon, authenticated;
revoke execute on function public.fn_learning_loop_sweep(p_limit integer)                                               from public, anon, authenticated;
revoke execute on function public.fn_os_health_brief()                                                                  from public, anon, authenticated;
revoke execute on function public.fn_os_knowledge_query(p_os_key text, p_topic text)                                    from public, anon, authenticated;
revoke execute on function public.fn_os_objective_measure()                                                             from public, anon, authenticated;
revoke execute on function public.fn_os_open_access()                                                                   from public, anon, authenticated;
revoke execute on function public.fn_owning_os(p_agent text)                                                            from public, anon, authenticated;
revoke execute on function public.fn_phase_b_invariants()                                                               from public, anon, authenticated;
revoke execute on function public.fn_phase_c_event_binding_status_guard()                                               from public, anon, authenticated;
revoke execute on function public.fn_phase_c_task_trace_guard()                                                         from public, anon, authenticated;
revoke execute on function public.fn_pick_reviewer(p_dept_key text, p_author text)                                      from public, anon, authenticated;
revoke execute on function public.fn_promote_memory_sweep(p_limit integer)                                              from public, anon, authenticated;
revoke execute on function public.fn_rating_due(p_now timestamp with time zone)                                         from public, anon, authenticated;
revoke execute on function public.fn_regulation_watch()                                                                 from public, anon, authenticated;
revoke execute on function public.fn_report_drilldown(p_metric text, p_days integer)                                    from public, anon, authenticated;
revoke execute on function public.fn_report_recommendation_approve(p_report_id bigint, p_index integer, p_by text, p_source text) from public, anon, authenticated;
revoke execute on function public.fn_route_party(p_name text)                                                           from public, anon, authenticated;
revoke execute on function public.fn_supplier_advisor(p_lead_id bigint)                                                 from public, anon, authenticated;
revoke execute on function public.fn_supplier_certifications(p_lead_id bigint)                                          from public, anon, authenticated;
revoke execute on function public.fn_supplier_market(p_lead_id bigint)                                                  from public, anon, authenticated;
revoke execute on function public.fn_supplier_negotiation(p_quote_id uuid)                                              from public, anon, authenticated;
revoke execute on function public.fn_supplier_network_map()                                                             from public, anon, authenticated;
revoke execute on function public.fn_supplier_product_match(p_inquiry_id uuid, p_lead_id bigint)                        from public, anon, authenticated;
revoke execute on function public.fn_supplier_products(p_lead_id bigint, p_query text)                                  from public, anon, authenticated;
revoke execute on function public.fn_supplier_quality(p_lead_id bigint)                                                 from public, anon, authenticated;
revoke execute on function public.fn_supplier_risk_monitor(p_signal text)                                               from public, anon, authenticated;
revoke execute on function public.fn_supplier_tier(p_lead_id bigint)                                                    from public, anon, authenticated;
revoke execute on function public.fn_supplier_workspaces(p_lead_id bigint)                                              from public, anon, authenticated;
revoke execute on function public.fn_task_approve(p_dry_run boolean)                                                    from public, anon, authenticated;
revoke execute on function public.fn_task_lesson(p_task_id bigint, p_outcome text, p_review jsonb)                      from public, anon, authenticated;
revoke execute on function public.fn_task_review(p_task_id bigint)                                                      from public, anon, authenticated;
revoke execute on function public.fn_workflow_start(p_workflow_key text, p_trigger_event_id bigint, p_entity_type text, p_entity_id text, p_context jsonb) from public, anon, authenticated;
revoke execute on function public.fn_workflow_start_due(p_lookback_minutes integer)                                     from public, anon, authenticated;
revoke execute on function public.fn_workflow_step_done(p_run uuid, p_step_no integer, p_output jsonb, p_status text)    from public, anon, authenticated;
revoke execute on function public.fn_ws_company_os()                                                                    from public, anon, authenticated;
revoke execute on function public.fn_ws_intelligence()                                                                  from public, anon, authenticated;
revoke execute on function public.fn_ws_live_company()                                                                  from public, anon, authenticated;
revoke execute on function public.fn_ws_notifications()                                                                 from public, anon, authenticated;

-- -------------------------------------------------------------------------------------------------
-- The assertion runs INSIDE the same transaction as the revokes, so a wrong outcome takes the whole
-- file with it rather than leaving a half-closed estate. It reads the catalog and writes nothing.
-- -------------------------------------------------------------------------------------------------
do $e4$
declare
  v_anon   int;
  v_auth   int;
  v_lost   text;
  v_names  text;
begin
  select count(*) filter (where has_function_privilege('anon', p.oid, 'EXECUTE')),
         count(*) filter (where has_function_privilege('authenticated', p.oid, 'EXECUTE')),
         coalesce(string_agg(p.proname, ', ') filter (
           where has_function_privilege('authenticated', p.oid, 'EXECUTE')), '(none)')
    into v_anon, v_auth, v_names
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.prosecdef;

  if v_anon <> 0 then
    raise exception 'E4: % SECURITY DEFINER routine(s) in public are still anon-executable. '
      'A revoke naming only anon against a PUBLIC grant is a silent no-op — name public first.', v_anon;
  end if;

  if v_auth <> 2 or v_names <> 'fn_customer_document_refs, fn_customer_documents' then
    raise exception 'E4: expected exactly the two customer-document routines to stay '
      'authenticated-executable, found % — %', v_auth, v_names;
  end if;

  -- The revoke must not have taken the grant the real callers depend on. Every caller of the 57
  -- runs as service_role (279 admin.rpc call sites) or as postgres (cron, and SECURITY DEFINER
  -- routines calling each other). If this fires, the supplier portal and the OS shell are down and
  -- the failure would otherwise read as a security win.
  select string_agg(p.proname, ', ')
    into v_lost
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.prosecdef
     and p.proname in (
       'fn_action_policies','fn_approval_trace_audit','fn_capability_verify','fn_category_knowledge',
       'fn_category_questions','fn_decision_conflict_scan','fn_decision_outcomes','fn_emit',
       'fn_emit_task_assigned','fn_event_consolidate','fn_execution_run','fn_execution_sweep',
       'fn_founder_command_trace_guard','fn_goal_attainment','fn_graph_supplier_market',
       'fn_improvement_handover','fn_improvement_plan_refresh','fn_index_slowdown_watch',
       'fn_intake_slug_for_catalog','fn_kernel_handoff_run_trace_guard','fn_learning_loop_sweep',
       'fn_os_health_brief','fn_os_knowledge_query','fn_os_objective_measure','fn_os_open_access',
       'fn_owning_os','fn_phase_b_invariants','fn_phase_c_event_binding_status_guard',
       'fn_phase_c_task_trace_guard','fn_pick_reviewer','fn_promote_memory_sweep','fn_rating_due',
       'fn_regulation_watch','fn_report_drilldown','fn_report_recommendation_approve','fn_route_party',
       'fn_supplier_advisor','fn_supplier_certifications','fn_supplier_market','fn_supplier_negotiation',
       'fn_supplier_network_map','fn_supplier_product_match','fn_supplier_products','fn_supplier_quality',
       'fn_supplier_risk_monitor','fn_supplier_tier','fn_supplier_workspaces','fn_task_approve',
       'fn_task_lesson','fn_task_review','fn_workflow_start','fn_workflow_start_due',
       'fn_workflow_step_done','fn_ws_company_os','fn_ws_intelligence','fn_ws_live_company',
       'fn_ws_notifications')
     and not has_function_privilege('service_role', p.oid, 'EXECUTE');

  if v_lost is not null then
    raise exception 'E4: service_role lost EXECUTE on: % — these are called from supplier_portal, '
      'os_api, customer_api and the OS edge functions and will now fail.', v_lost;
  end if;
end
$e4$;
