-- THE JULY "OS CONSOLE" BACKEND AND THE OLD AGENT-CONTEXT BUILDER ARE RETIRED.
--
-- Seat: it_engineer. Founder ledgers 1714 and 1715 (16 Nov 2026): remove what is unnecessary and prove each removal with
-- evidence, and prove everything is still fine.
--
-- WHAT WAS WRONG. The fn_os_* settings, automation, catalog, incident, search and health API, the fn_ws_* home screens that
-- fn_query_platform does NOT dispatch, and the boards (customers, suppliers, rfq, report drilldown, entity files and
-- comments, goal attainment, inbox) served a July admin console whose screens no longer exist (ruling 1607: the admin
-- dashboard comes "later", built on today's tables). fn_agent_context (both overloads), fn_agent_context_v3 and the two
-- helpers only it calls (fn_agent_institutional_memory, fn_knowledge_staleness_tag) built agent context in SQL; the edge
-- functions build it in TypeScript now (_shared/think, case_context.ts). Also, on the coordinator's 16 Nov list:
--   fn_action_invoke_dispatch (asked the founder to approve spend; nothing calls it) and fn_action_resolve_approver and
--   fn_action_authority_rank, which only it called;
--   fn_agent_handoff_inbox: its one route was agent_tool row handoff_inbox -> fn_agent_tools -> supabase/functions/_shared/
--   tools.ts, and no file imports tools.ts, so no deployed function can reach it;
--   fn_dbx_category: DROPPED.txt records it retired on 8 Sep, yet it was live; the backup builds the supplier folder from
--   the licensed name now (fn_enqueue_doc_backups no longer calls it).
-- KEPT, because something live reaches them: the fn_ws_* tools fn_query_platform dispatches, fn_os_command (fn_ws_exec),
-- fn_os_fresh_start_at, fn_os_catalog_test_gate (reasoned_suppliers.ts), and the fn_os_incident_* trigger routines.
--
-- HOW "NO CALLER" WAS MEASURED (16 Nov 2026, it_engineer, production read with light SELECTs only):
--   * every live routine body in every schema, read with pg_get_functiondef (2,667 in public), comments stripped;
--   * every cron.job command (active or not), trigger, event trigger, view, RLS policy, column default and check constraint;
--   * every table that names a routine for dispatch: seat_duty.routine, seat_handoff_kind.handler, org_task_kind_handler.handler,
--     org_departments.health_fn, agent_tool.impl_target, it_playbook.remedy_routine, it_rerunnable_job.routine,
--     it_safe_fix_family.routine, org_action_executor, fn_task_class, llm_seat_binding, quality_standard.criteria, decision_policy
--     and every *_sql column; and the run-time name builders ('fn_reason_apply_' ||, 'fn_it_game_day_' ||, format('%I') over those
--     tables) - none of which can produce these names;
--   * origin/main supabase/functions and src, comments stripped (no rpc name in either is built from a template);
--   * pg_stat_statements (reset 2 Nov 07:12 UTC, track = top): no top-level statement by any role calls them.
--   A routine whose only body callers are themselves retired here is retired with them (the closure is checked by the probe).
--   The per-object evidence is in the hand-back's EVIDENCE_C.md; the names below carry what still MENTIONS them.
--
-- REVERSIBLE (phase 1 of 2). Nothing is dropped: each object only changes schema, so a caller nobody found fails loudly
-- with "function public.<name> does not exist" instead of silently, and one line brings it back (listed per object below).
-- Phase 2 (DROP, after the tables are archived to the evidence bucket with row counts and checksums) is owed after 7 clean
-- days: scripts/sql/pending/the_retired_schema_is_dropped_only_after_seven_clean_days_probe.txt says how clean is measured.

-- THE OBJECTS (public signature, then who still mentions the name - a scripts/sql definition, a check, an archived file):
--   fn_os_ai_quality()                                                     mentioned only by: sqlfile:2
--   fn_os_automation_list()                                                mentioned only by: sqlfile:3
--   fn_os_automation_reschedule(bigint,text,text)                          mentioned only by: sqlfile:1
--   fn_os_automation_run(bigint,text)                                      mentioned only by: sqlfile:1
--   fn_os_automation_set_active(bigint,boolean,text)                       mentioned only by: sqlfile:1
--   fn_os_catalog_get(text)                                                mentioned only by: sqlfile:1
--   fn_os_catalog_list()                                                   mentioned only by: sqlfile:1
--   fn_os_catalog_save_fields(text,jsonb,text)                             mentioned only by: sqlfile:1
--   fn_os_catalog_spec_delete(bigint,text)                                 mentioned only by: sqlfile:1
--   fn_os_catalog_spec_upsert(bigint,text,text,text,text,boolean,text,text) mentioned only by: sqlfile:1
--   fn_os_incident_list(text)                                              mentioned only by: sqlfile:2
--   fn_os_incident_open(text,text,text,jsonb,text)                         mentioned only by: sqlfile:5
--   fn_os_incident_resolve(bigint,text,text)                               mentioned only by: sqlfile:2
--   fn_os_open_access()                                                    mentioned only by: sqlfile:4
--   fn_os_reconcile()                                                      mentioned only by: sqlfile:1
--   fn_os_runbooks()                                                       mentioned only by: sqlfile:2
--   fn_os_settings_history(text)                                           mentioned only by: sqlfile:1
--   fn_os_settings_list()                                                  mentioned only by: sqlfile:1
--   fn_os_settings_revert(text,text)                                       mentioned only by: sqlfile:1
--   fn_os_settings_set(text,text,text,boolean)                             mentioned only by: sqlfile:1
--   fn_os_dashboard_viz()                                                  mentioned only by: sqlfile:2 script:2
--   fn_os_detail(text,text)                                                mentioned only by: sqlfile:2 script:2
--   fn_os_list(text,jsonb)                                                 mentioned only by: sqlfile:2 script:2
--   fn_os_nav()                                                            mentioned only by: sqlfile:2 script:2
--   fn_os_record(text,text)                                                mentioned only by: sqlfile:1 script:3
--   fn_os_search(text)                                                     mentioned only by: sqlfile:4 script:3
--   fn_os_health()                                                         mentioned only by: sqlfile:5 archive:1 script:2
--   fn_os_health_brief()                                                   mentioned only by: sqlfile:6 script:1
--   fn_os_review()                                                         mentioned only by: sqlfile:4 archive:1 script:2 body of fn_os_health_brief
--   fn_os_memory(text,date,date)                                           mentioned only by: sqlfile:2 test:1
--   fn_self_review()                                                       mentioned only by: sqlfile:2 archive:1
--   fn_ws_exec_home()                                                      mentioned only by: sqlfile:14 archive:3
--   fn_ws_company_os()                                                     mentioned only by: sqlfile:7 archive:2
--   fn_ws_live_company()                                                   mentioned only by: sqlfile:3
--   fn_ws_notifications()                                                  mentioned only by: sqlfile:5 archive:1
--   fn_ws_customer_behavior()                                              mentioned only by: sqlfile:2
--   fn_customers_board(text,integer,integer)                               mentioned only by: sqlfile:2 script:1
--   fn_suppliers_board(text,text,integer,integer)                          mentioned only by: sqlfile:2 script:2
--   fn_rfq_board(text,integer,integer)                                     mentioned only by: sqlfile:1 script:1
--   fn_report_drilldown(text,integer)                                      mentioned only by: sqlfile:3
--   fn_entity_files(text,text)                                             mentioned only by: sqlfile:2 script:1
--   fn_entity_comment_add(text,text,text,text)                             mentioned only by: sqlfile:2
--   fn_goal_attainment(text)                                               mentioned only by: sqlfile:17 body of fn_ws_exec_home
--   fn_inbox_list()                                                        mentioned only by: sqlfile:4
--   fn_agent_context(text,integer)                                         mentioned only by: sqlfile:29 archive:3 script:21 test:1
--   fn_agent_context(text,integer,text)                                    mentioned only by: sqlfile:29 archive:3 script:21 test:1
--   fn_agent_context_v3(text,text,text,text,integer)                       mentioned only by: sqlfile:24 archive:2 script:2 test:3 body of fn_agent_context
--   fn_agent_institutional_memory(text,integer)                            mentioned only by: sqlfile:16 script:3 body of fn_agent_context
--   fn_knowledge_staleness_tag(date,text)                                  mentioned only by: sqlfile:14 body of fn_agent_context
--   fn_action_invoke_dispatch(integer)                                     mentioned only by: sqlfile:10 archive:3 script:3
--   fn_action_resolve_approver(text,text)                                  mentioned only by: sqlfile:9 archive:2 body of fn_action_invoke_dispatch
--   fn_action_authority_rank(text)                                         mentioned only by: sqlfile:4 body of fn_action_resolve_approver
--   fn_agent_handoff_inbox(text)                                           mentioned only by: sqlfile:5 archive:1
--   fn_dbx_category(bigint)                                                mentioned only by: sqlfile:18
--
-- REVERSAL, one line per object (run as postgres): back to public, with the EXECUTE grants it had on 16 Nov:
--   alter function retired.fn_os_ai_quality() set schema public; grant execute on function public.fn_os_ai_quality() to service_role;
--   alter function retired.fn_os_automation_list() set schema public; grant execute on function public.fn_os_automation_list() to service_role;
--   alter function retired.fn_os_automation_reschedule(bigint,text,text) set schema public; grant execute on function public.fn_os_automation_reschedule(bigint,text,text) to service_role;
--   alter function retired.fn_os_automation_run(bigint,text) set schema public; grant execute on function public.fn_os_automation_run(bigint,text) to service_role;
--   alter function retired.fn_os_automation_set_active(bigint,boolean,text) set schema public; grant execute on function public.fn_os_automation_set_active(bigint,boolean,text) to service_role;
--   alter function retired.fn_os_catalog_get(text) set schema public; grant execute on function public.fn_os_catalog_get(text) to service_role;
--   alter function retired.fn_os_catalog_list() set schema public; grant execute on function public.fn_os_catalog_list() to service_role;
--   alter function retired.fn_os_catalog_save_fields(text,jsonb,text) set schema public; grant execute on function public.fn_os_catalog_save_fields(text,jsonb,text) to service_role;
--   alter function retired.fn_os_catalog_spec_delete(bigint,text) set schema public; grant execute on function public.fn_os_catalog_spec_delete(bigint,text) to service_role;
--   alter function retired.fn_os_catalog_spec_upsert(bigint,text,text,text,text,boolean,text,text) set schema public; grant execute on function public.fn_os_catalog_spec_upsert(bigint,text,text,text,text,boolean,text,text) to service_role;
--   alter function retired.fn_os_incident_list(text) set schema public; grant execute on function public.fn_os_incident_list(text) to service_role;
--   alter function retired.fn_os_incident_open(text,text,text,jsonb,text) set schema public; grant execute on function public.fn_os_incident_open(text,text,text,jsonb,text) to service_role;
--   alter function retired.fn_os_incident_resolve(bigint,text,text) set schema public; grant execute on function public.fn_os_incident_resolve(bigint,text,text) to service_role;
--   alter function retired.fn_os_open_access() set schema public; grant execute on function public.fn_os_open_access() to service_role;
--   alter function retired.fn_os_reconcile() set schema public; grant execute on function public.fn_os_reconcile() to service_role;
--   alter function retired.fn_os_runbooks() set schema public; grant execute on function public.fn_os_runbooks() to service_role;
--   alter function retired.fn_os_settings_history(text) set schema public; grant execute on function public.fn_os_settings_history(text) to service_role;
--   alter function retired.fn_os_settings_list() set schema public; grant execute on function public.fn_os_settings_list() to service_role;
--   alter function retired.fn_os_settings_revert(text,text) set schema public; grant execute on function public.fn_os_settings_revert(text,text) to service_role;
--   alter function retired.fn_os_settings_set(text,text,text,boolean) set schema public; grant execute on function public.fn_os_settings_set(text,text,text,boolean) to service_role;
--   alter function retired.fn_os_dashboard_viz() set schema public; grant execute on function public.fn_os_dashboard_viz() to service_role;
--   alter function retired.fn_os_detail(text,text) set schema public; grant execute on function public.fn_os_detail(text,text) to service_role;
--   alter function retired.fn_os_list(text,jsonb) set schema public; grant execute on function public.fn_os_list(text,jsonb) to service_role;
--   alter function retired.fn_os_nav() set schema public; grant execute on function public.fn_os_nav() to service_role;
--   alter function retired.fn_os_record(text,text) set schema public; grant execute on function public.fn_os_record(text,text) to service_role;
--   alter function retired.fn_os_search(text) set schema public; grant execute on function public.fn_os_search(text) to service_role;
--   alter function retired.fn_os_health() set schema public; grant execute on function public.fn_os_health() to service_role;
--   alter function retired.fn_os_health_brief() set schema public; grant execute on function public.fn_os_health_brief() to service_role;
--   alter function retired.fn_os_review() set schema public; grant execute on function public.fn_os_review() to service_role;
--   alter function retired.fn_os_memory(text,date,date) set schema public; grant execute on function public.fn_os_memory(text,date,date) to service_role;
--   alter function retired.fn_self_review() set schema public; grant execute on function public.fn_self_review() to service_role;
--   alter function retired.fn_ws_exec_home() set schema public; grant execute on function public.fn_ws_exec_home() to service_role;
--   alter function retired.fn_ws_company_os() set schema public; grant execute on function public.fn_ws_company_os() to service_role;
--   alter function retired.fn_ws_live_company() set schema public; grant execute on function public.fn_ws_live_company() to service_role;
--   alter function retired.fn_ws_notifications() set schema public; grant execute on function public.fn_ws_notifications() to service_role;
--   alter function retired.fn_ws_customer_behavior() set schema public; grant execute on function public.fn_ws_customer_behavior() to service_role;
--   alter function retired.fn_customers_board(text,integer,integer) set schema public; grant execute on function public.fn_customers_board(text,integer,integer) to service_role;
--   alter function retired.fn_suppliers_board(text,text,integer,integer) set schema public; grant execute on function public.fn_suppliers_board(text,text,integer,integer) to service_role;
--   alter function retired.fn_rfq_board(text,integer,integer) set schema public; grant execute on function public.fn_rfq_board(text,integer,integer) to service_role;
--   alter function retired.fn_report_drilldown(text,integer) set schema public; grant execute on function public.fn_report_drilldown(text,integer) to service_role;
--   alter function retired.fn_entity_files(text,text) set schema public; grant execute on function public.fn_entity_files(text,text) to service_role;
--   alter function retired.fn_entity_comment_add(text,text,text,text) set schema public; grant execute on function public.fn_entity_comment_add(text,text,text,text) to service_role;
--   alter function retired.fn_goal_attainment(text) set schema public; grant execute on function public.fn_goal_attainment(text) to service_role;
--   alter function retired.fn_inbox_list() set schema public; grant execute on function public.fn_inbox_list() to service_role;
--   alter function retired.fn_agent_context(text,integer) set schema public; grant execute on function public.fn_agent_context(text,integer) to service_role;
--   alter function retired.fn_agent_context(text,integer,text) set schema public; grant execute on function public.fn_agent_context(text,integer,text) to service_role;
--   alter function retired.fn_agent_context_v3(text,text,text,text,integer) set schema public; grant execute on function public.fn_agent_context_v3(text,text,text,text,integer) to service_role;
--   alter function retired.fn_agent_institutional_memory(text,integer) set schema public; grant execute on function public.fn_agent_institutional_memory(text,integer) to service_role;
--   alter function retired.fn_knowledge_staleness_tag(date,text) set schema public; grant execute on function public.fn_knowledge_staleness_tag(date,text) to public, service_role;
--   alter function retired.fn_action_invoke_dispatch(integer) set schema public; grant execute on function public.fn_action_invoke_dispatch(integer) to service_role;
--   alter function retired.fn_action_resolve_approver(text,text) set schema public; grant execute on function public.fn_action_resolve_approver(text,text) to service_role;
--   alter function retired.fn_action_authority_rank(text) set schema public; grant execute on function public.fn_action_authority_rank(text) to service_role;
--   alter function retired.fn_agent_handoff_inbox(text) set schema public; grant execute on function public.fn_agent_handoff_inbox(text) to service_role;
--   alter function retired.fn_dbx_category(bigint) set schema public; grant execute on function public.fn_dbx_category(bigint) to service_role;

-- The schema that holds what is retired: owned by postgres, no USAGE for anyone else (PUBLIC, anon, authenticated and
-- service_role cannot even name an object in it), so a retired routine cannot be called and a retired table cannot be read
-- from the API. postgres keeps full access for the phase-2 archive. Idempotent: every cluster file repeats these lines.
create schema if not exists retired;
revoke all on schema retired from public, anon, authenticated, service_role;

do $retire_os_console$
begin
  if to_regprocedure('public.fn_os_ai_quality()') is not null then
    revoke all on function public.fn_os_ai_quality() from public, anon, authenticated, service_role;
    alter function public.fn_os_ai_quality() set schema retired;
  end if;
  if to_regprocedure('public.fn_os_automation_list()') is not null then
    revoke all on function public.fn_os_automation_list() from public, anon, authenticated, service_role;
    alter function public.fn_os_automation_list() set schema retired;
  end if;
  if to_regprocedure('public.fn_os_automation_reschedule(bigint,text,text)') is not null then
    revoke all on function public.fn_os_automation_reschedule(bigint,text,text) from public, anon, authenticated, service_role;
    alter function public.fn_os_automation_reschedule(bigint,text,text) set schema retired;
  end if;
  if to_regprocedure('public.fn_os_automation_run(bigint,text)') is not null then
    revoke all on function public.fn_os_automation_run(bigint,text) from public, anon, authenticated, service_role;
    alter function public.fn_os_automation_run(bigint,text) set schema retired;
  end if;
  if to_regprocedure('public.fn_os_automation_set_active(bigint,boolean,text)') is not null then
    revoke all on function public.fn_os_automation_set_active(bigint,boolean,text) from public, anon, authenticated, service_role;
    alter function public.fn_os_automation_set_active(bigint,boolean,text) set schema retired;
  end if;
  if to_regprocedure('public.fn_os_catalog_get(text)') is not null then
    revoke all on function public.fn_os_catalog_get(text) from public, anon, authenticated, service_role;
    alter function public.fn_os_catalog_get(text) set schema retired;
  end if;
  if to_regprocedure('public.fn_os_catalog_list()') is not null then
    revoke all on function public.fn_os_catalog_list() from public, anon, authenticated, service_role;
    alter function public.fn_os_catalog_list() set schema retired;
  end if;
  if to_regprocedure('public.fn_os_catalog_save_fields(text,jsonb,text)') is not null then
    revoke all on function public.fn_os_catalog_save_fields(text,jsonb,text) from public, anon, authenticated, service_role;
    alter function public.fn_os_catalog_save_fields(text,jsonb,text) set schema retired;
  end if;
  if to_regprocedure('public.fn_os_catalog_spec_delete(bigint,text)') is not null then
    revoke all on function public.fn_os_catalog_spec_delete(bigint,text) from public, anon, authenticated, service_role;
    alter function public.fn_os_catalog_spec_delete(bigint,text) set schema retired;
  end if;
  if to_regprocedure('public.fn_os_catalog_spec_upsert(bigint,text,text,text,text,boolean,text,text)') is not null then
    revoke all on function public.fn_os_catalog_spec_upsert(bigint,text,text,text,text,boolean,text,text) from public, anon, authenticated, service_role;
    alter function public.fn_os_catalog_spec_upsert(bigint,text,text,text,text,boolean,text,text) set schema retired;
  end if;
  if to_regprocedure('public.fn_os_incident_list(text)') is not null then
    revoke all on function public.fn_os_incident_list(text) from public, anon, authenticated, service_role;
    alter function public.fn_os_incident_list(text) set schema retired;
  end if;
  if to_regprocedure('public.fn_os_incident_open(text,text,text,jsonb,text)') is not null then
    revoke all on function public.fn_os_incident_open(text,text,text,jsonb,text) from public, anon, authenticated, service_role;
    alter function public.fn_os_incident_open(text,text,text,jsonb,text) set schema retired;
  end if;
  if to_regprocedure('public.fn_os_incident_resolve(bigint,text,text)') is not null then
    revoke all on function public.fn_os_incident_resolve(bigint,text,text) from public, anon, authenticated, service_role;
    alter function public.fn_os_incident_resolve(bigint,text,text) set schema retired;
  end if;
  if to_regprocedure('public.fn_os_open_access()') is not null then
    revoke all on function public.fn_os_open_access() from public, anon, authenticated, service_role;
    alter function public.fn_os_open_access() set schema retired;
  end if;
  if to_regprocedure('public.fn_os_reconcile()') is not null then
    revoke all on function public.fn_os_reconcile() from public, anon, authenticated, service_role;
    alter function public.fn_os_reconcile() set schema retired;
  end if;
  if to_regprocedure('public.fn_os_runbooks()') is not null then
    revoke all on function public.fn_os_runbooks() from public, anon, authenticated, service_role;
    alter function public.fn_os_runbooks() set schema retired;
  end if;
  if to_regprocedure('public.fn_os_settings_history(text)') is not null then
    revoke all on function public.fn_os_settings_history(text) from public, anon, authenticated, service_role;
    alter function public.fn_os_settings_history(text) set schema retired;
  end if;
  if to_regprocedure('public.fn_os_settings_list()') is not null then
    revoke all on function public.fn_os_settings_list() from public, anon, authenticated, service_role;
    alter function public.fn_os_settings_list() set schema retired;
  end if;
  if to_regprocedure('public.fn_os_settings_revert(text,text)') is not null then
    revoke all on function public.fn_os_settings_revert(text,text) from public, anon, authenticated, service_role;
    alter function public.fn_os_settings_revert(text,text) set schema retired;
  end if;
  if to_regprocedure('public.fn_os_settings_set(text,text,text,boolean)') is not null then
    revoke all on function public.fn_os_settings_set(text,text,text,boolean) from public, anon, authenticated, service_role;
    alter function public.fn_os_settings_set(text,text,text,boolean) set schema retired;
  end if;
  if to_regprocedure('public.fn_os_dashboard_viz()') is not null then
    revoke all on function public.fn_os_dashboard_viz() from public, anon, authenticated, service_role;
    alter function public.fn_os_dashboard_viz() set schema retired;
  end if;
  if to_regprocedure('public.fn_os_detail(text,text)') is not null then
    revoke all on function public.fn_os_detail(text,text) from public, anon, authenticated, service_role;
    alter function public.fn_os_detail(text,text) set schema retired;
  end if;
  if to_regprocedure('public.fn_os_list(text,jsonb)') is not null then
    revoke all on function public.fn_os_list(text,jsonb) from public, anon, authenticated, service_role;
    alter function public.fn_os_list(text,jsonb) set schema retired;
  end if;
  if to_regprocedure('public.fn_os_nav()') is not null then
    revoke all on function public.fn_os_nav() from public, anon, authenticated, service_role;
    alter function public.fn_os_nav() set schema retired;
  end if;
  if to_regprocedure('public.fn_os_record(text,text)') is not null then
    revoke all on function public.fn_os_record(text,text) from public, anon, authenticated, service_role;
    alter function public.fn_os_record(text,text) set schema retired;
  end if;
  if to_regprocedure('public.fn_os_search(text)') is not null then
    revoke all on function public.fn_os_search(text) from public, anon, authenticated, service_role;
    alter function public.fn_os_search(text) set schema retired;
  end if;
  if to_regprocedure('public.fn_os_health()') is not null then
    revoke all on function public.fn_os_health() from public, anon, authenticated, service_role;
    alter function public.fn_os_health() set schema retired;
  end if;
  if to_regprocedure('public.fn_os_health_brief()') is not null then
    revoke all on function public.fn_os_health_brief() from public, anon, authenticated, service_role;
    alter function public.fn_os_health_brief() set schema retired;
  end if;
  if to_regprocedure('public.fn_os_review()') is not null then
    revoke all on function public.fn_os_review() from public, anon, authenticated, service_role;
    alter function public.fn_os_review() set schema retired;
  end if;
  if to_regprocedure('public.fn_os_memory(text,date,date)') is not null then
    revoke all on function public.fn_os_memory(text,date,date) from public, anon, authenticated, service_role;
    alter function public.fn_os_memory(text,date,date) set schema retired;
  end if;
  if to_regprocedure('public.fn_self_review()') is not null then
    revoke all on function public.fn_self_review() from public, anon, authenticated, service_role;
    alter function public.fn_self_review() set schema retired;
  end if;
  if to_regprocedure('public.fn_ws_exec_home()') is not null then
    revoke all on function public.fn_ws_exec_home() from public, anon, authenticated, service_role;
    alter function public.fn_ws_exec_home() set schema retired;
  end if;
  if to_regprocedure('public.fn_ws_company_os()') is not null then
    revoke all on function public.fn_ws_company_os() from public, anon, authenticated, service_role;
    alter function public.fn_ws_company_os() set schema retired;
  end if;
  if to_regprocedure('public.fn_ws_live_company()') is not null then
    revoke all on function public.fn_ws_live_company() from public, anon, authenticated, service_role;
    alter function public.fn_ws_live_company() set schema retired;
  end if;
  if to_regprocedure('public.fn_ws_notifications()') is not null then
    revoke all on function public.fn_ws_notifications() from public, anon, authenticated, service_role;
    alter function public.fn_ws_notifications() set schema retired;
  end if;
  if to_regprocedure('public.fn_ws_customer_behavior()') is not null then
    revoke all on function public.fn_ws_customer_behavior() from public, anon, authenticated, service_role;
    alter function public.fn_ws_customer_behavior() set schema retired;
  end if;
  if to_regprocedure('public.fn_customers_board(text,integer,integer)') is not null then
    revoke all on function public.fn_customers_board(text,integer,integer) from public, anon, authenticated, service_role;
    alter function public.fn_customers_board(text,integer,integer) set schema retired;
  end if;
  if to_regprocedure('public.fn_suppliers_board(text,text,integer,integer)') is not null then
    revoke all on function public.fn_suppliers_board(text,text,integer,integer) from public, anon, authenticated, service_role;
    alter function public.fn_suppliers_board(text,text,integer,integer) set schema retired;
  end if;
  if to_regprocedure('public.fn_rfq_board(text,integer,integer)') is not null then
    revoke all on function public.fn_rfq_board(text,integer,integer) from public, anon, authenticated, service_role;
    alter function public.fn_rfq_board(text,integer,integer) set schema retired;
  end if;
  if to_regprocedure('public.fn_report_drilldown(text,integer)') is not null then
    revoke all on function public.fn_report_drilldown(text,integer) from public, anon, authenticated, service_role;
    alter function public.fn_report_drilldown(text,integer) set schema retired;
  end if;
  if to_regprocedure('public.fn_entity_files(text,text)') is not null then
    revoke all on function public.fn_entity_files(text,text) from public, anon, authenticated, service_role;
    alter function public.fn_entity_files(text,text) set schema retired;
  end if;
  if to_regprocedure('public.fn_entity_comment_add(text,text,text,text)') is not null then
    revoke all on function public.fn_entity_comment_add(text,text,text,text) from public, anon, authenticated, service_role;
    alter function public.fn_entity_comment_add(text,text,text,text) set schema retired;
  end if;
  if to_regprocedure('public.fn_goal_attainment(text)') is not null then
    revoke all on function public.fn_goal_attainment(text) from public, anon, authenticated, service_role;
    alter function public.fn_goal_attainment(text) set schema retired;
  end if;
  if to_regprocedure('public.fn_inbox_list()') is not null then
    revoke all on function public.fn_inbox_list() from public, anon, authenticated, service_role;
    alter function public.fn_inbox_list() set schema retired;
  end if;
  if to_regprocedure('public.fn_agent_context(text,integer)') is not null then
    revoke all on function public.fn_agent_context(text,integer) from public, anon, authenticated, service_role;
    alter function public.fn_agent_context(text,integer) set schema retired;
  end if;
  if to_regprocedure('public.fn_agent_context(text,integer,text)') is not null then
    revoke all on function public.fn_agent_context(text,integer,text) from public, anon, authenticated, service_role;
    alter function public.fn_agent_context(text,integer,text) set schema retired;
  end if;
  if to_regprocedure('public.fn_agent_context_v3(text,text,text,text,integer)') is not null then
    revoke all on function public.fn_agent_context_v3(text,text,text,text,integer) from public, anon, authenticated, service_role;
    alter function public.fn_agent_context_v3(text,text,text,text,integer) set schema retired;
  end if;
  if to_regprocedure('public.fn_agent_institutional_memory(text,integer)') is not null then
    revoke all on function public.fn_agent_institutional_memory(text,integer) from public, anon, authenticated, service_role;
    alter function public.fn_agent_institutional_memory(text,integer) set schema retired;
  end if;
  if to_regprocedure('public.fn_knowledge_staleness_tag(date,text)') is not null then
    revoke all on function public.fn_knowledge_staleness_tag(date,text) from public, anon, authenticated, service_role;
    alter function public.fn_knowledge_staleness_tag(date,text) set schema retired;
  end if;
  if to_regprocedure('public.fn_action_invoke_dispatch(integer)') is not null then
    revoke all on function public.fn_action_invoke_dispatch(integer) from public, anon, authenticated, service_role;
    alter function public.fn_action_invoke_dispatch(integer) set schema retired;
  end if;
  if to_regprocedure('public.fn_action_resolve_approver(text,text)') is not null then
    revoke all on function public.fn_action_resolve_approver(text,text) from public, anon, authenticated, service_role;
    alter function public.fn_action_resolve_approver(text,text) set schema retired;
  end if;
  if to_regprocedure('public.fn_action_authority_rank(text)') is not null then
    revoke all on function public.fn_action_authority_rank(text) from public, anon, authenticated, service_role;
    alter function public.fn_action_authority_rank(text) set schema retired;
  end if;
  if to_regprocedure('public.fn_agent_handoff_inbox(text)') is not null then
    revoke all on function public.fn_agent_handoff_inbox(text) from public, anon, authenticated, service_role;
    alter function public.fn_agent_handoff_inbox(text) set schema retired;
  end if;
  if to_regprocedure('public.fn_dbx_category(bigint)') is not null then
    revoke all on function public.fn_dbx_category(bigint) from public, anon, authenticated, service_role;
    alter function public.fn_dbx_category(bigint) set schema retired;
  end if;
end
$retire_os_console$;

-- PROBE (os_console): a verdict row, never a raise (a raise would roll back the moves above). It reads, live, at apply time:
--   moved      every signature is now in schema retired;  gone  no routine of these names is left in public;
--   callers    no routine outside schema retired names one of them in its body (comments stripped), no cron command,
--              no view, no policy, no column default, and no trigger outside retired runs a retired routine;
--   closed     no role but postgres may execute a retired routine.
with sig(s) as (values
         ('fn_os_ai_quality()'),
         ('fn_os_automation_list()'),
         ('fn_os_automation_reschedule(bigint,text,text)'),
         ('fn_os_automation_run(bigint,text)'),
         ('fn_os_automation_set_active(bigint,boolean,text)'),
         ('fn_os_catalog_get(text)'),
         ('fn_os_catalog_list()'),
         ('fn_os_catalog_save_fields(text,jsonb,text)'),
         ('fn_os_catalog_spec_delete(bigint,text)'),
         ('fn_os_catalog_spec_upsert(bigint,text,text,text,text,boolean,text,text)'),
         ('fn_os_incident_list(text)'),
         ('fn_os_incident_open(text,text,text,jsonb,text)'),
         ('fn_os_incident_resolve(bigint,text,text)'),
         ('fn_os_open_access()'),
         ('fn_os_reconcile()'),
         ('fn_os_runbooks()'),
         ('fn_os_settings_history(text)'),
         ('fn_os_settings_list()'),
         ('fn_os_settings_revert(text,text)'),
         ('fn_os_settings_set(text,text,text,boolean)'),
         ('fn_os_dashboard_viz()'),
         ('fn_os_detail(text,text)'),
         ('fn_os_list(text,jsonb)'),
         ('fn_os_nav()'),
         ('fn_os_record(text,text)'),
         ('fn_os_search(text)'),
         ('fn_os_health()'),
         ('fn_os_health_brief()'),
         ('fn_os_review()'),
         ('fn_os_memory(text,date,date)'),
         ('fn_self_review()'),
         ('fn_ws_exec_home()'),
         ('fn_ws_company_os()'),
         ('fn_ws_live_company()'),
         ('fn_ws_notifications()'),
         ('fn_ws_customer_behavior()'),
         ('fn_customers_board(text,integer,integer)'),
         ('fn_suppliers_board(text,text,integer,integer)'),
         ('fn_rfq_board(text,integer,integer)'),
         ('fn_report_drilldown(text,integer)'),
         ('fn_entity_files(text,text)'),
         ('fn_entity_comment_add(text,text,text,text)'),
         ('fn_goal_attainment(text)'),
         ('fn_inbox_list()'),
         ('fn_agent_context(text,integer)'),
         ('fn_agent_context(text,integer,text)'),
         ('fn_agent_context_v3(text,text,text,text,integer)'),
         ('fn_agent_institutional_memory(text,integer)'),
         ('fn_knowledge_staleness_tag(date,text)'),
         ('fn_action_invoke_dispatch(integer)'),
         ('fn_action_resolve_approver(text,text)'),
         ('fn_action_authority_rank(text)'),
         ('fn_agent_handoff_inbox(text)'),
         ('fn_dbx_category(bigint)')),
nm(n) as (select unnest(array['fn_action_authority_rank','fn_action_invoke_dispatch','fn_action_resolve_approver','fn_agent_context','fn_agent_context_v3','fn_agent_handoff_inbox','fn_agent_institutional_memory','fn_customers_board','fn_dbx_category','fn_entity_comment_add','fn_entity_files','fn_goal_attainment','fn_inbox_list','fn_knowledge_staleness_tag','fn_os_ai_quality','fn_os_automation_list','fn_os_automation_reschedule','fn_os_automation_run','fn_os_automation_set_active','fn_os_catalog_get','fn_os_catalog_list','fn_os_catalog_save_fields','fn_os_catalog_spec_delete','fn_os_catalog_spec_upsert','fn_os_dashboard_viz','fn_os_detail','fn_os_health','fn_os_health_brief','fn_os_incident_list','fn_os_incident_open','fn_os_incident_resolve','fn_os_list','fn_os_memory','fn_os_nav','fn_os_open_access','fn_os_reconcile','fn_os_record','fn_os_review','fn_os_runbooks','fn_os_search','fn_os_settings_history','fn_os_settings_list','fn_os_settings_revert','fn_os_settings_set','fn_report_drilldown','fn_rfq_board','fn_self_review','fn_suppliers_board','fn_ws_company_os','fn_ws_customer_behavior','fn_ws_exec_home','fn_ws_live_company','fn_ws_notifications'])),
body as (select regexp_replace(regexp_replace(p.prosrc, '/\*.*?\*/', '', 'g'), '--[^\n]*', '', 'g') src, ns.nspname || '.' || p.proname who
           from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
          where ns.nspname not in ('retired', 'pg_catalog', 'information_schema')
            and not exists (select 1 from pg_depend d where d.objid = p.oid and d.deptype = 'e')),
v as (select
  (select count(*) from sig where to_regprocedure('retired.' || s) is not null) moved,
  (select count(*) from sig) wanted,
  (select count(*) from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace join nm on nm.n = p.proname where ns.nspname = 'public') left_in_public,
  (select string_agg(who || ' names ' || substring(src from '\m(fn_action_authority_rank|fn_action_invoke_dispatch|fn_action_resolve_approver|fn_agent_context|fn_agent_context_v3|fn_agent_handoff_inbox|fn_agent_institutional_memory|fn_customers_board|fn_dbx_category|fn_entity_comment_add|fn_entity_files|fn_goal_attainment|fn_inbox_list|fn_knowledge_staleness_tag|fn_os_ai_quality|fn_os_automation_list|fn_os_automation_reschedule|fn_os_automation_run|fn_os_automation_set_active|fn_os_catalog_get|fn_os_catalog_list|fn_os_catalog_save_fields|fn_os_catalog_spec_delete|fn_os_catalog_spec_upsert|fn_os_dashboard_viz|fn_os_detail|fn_os_health|fn_os_health_brief|fn_os_incident_list|fn_os_incident_open|fn_os_incident_resolve|fn_os_list|fn_os_memory|fn_os_nav|fn_os_open_access|fn_os_reconcile|fn_os_record|fn_os_review|fn_os_runbooks|fn_os_search|fn_os_settings_history|fn_os_settings_list|fn_os_settings_revert|fn_os_settings_set|fn_report_drilldown|fn_rfq_board|fn_self_review|fn_suppliers_board|fn_ws_company_os|fn_ws_customer_behavior|fn_ws_exec_home|fn_ws_live_company|fn_ws_notifications)\M'), '; ') from body where src ~ '\m(fn_action_authority_rank|fn_action_invoke_dispatch|fn_action_resolve_approver|fn_agent_context|fn_agent_context_v3|fn_agent_handoff_inbox|fn_agent_institutional_memory|fn_customers_board|fn_dbx_category|fn_entity_comment_add|fn_entity_files|fn_goal_attainment|fn_inbox_list|fn_knowledge_staleness_tag|fn_os_ai_quality|fn_os_automation_list|fn_os_automation_reschedule|fn_os_automation_run|fn_os_automation_set_active|fn_os_catalog_get|fn_os_catalog_list|fn_os_catalog_save_fields|fn_os_catalog_spec_delete|fn_os_catalog_spec_upsert|fn_os_dashboard_viz|fn_os_detail|fn_os_health|fn_os_health_brief|fn_os_incident_list|fn_os_incident_open|fn_os_incident_resolve|fn_os_list|fn_os_memory|fn_os_nav|fn_os_open_access|fn_os_reconcile|fn_os_record|fn_os_review|fn_os_runbooks|fn_os_search|fn_os_settings_history|fn_os_settings_list|fn_os_settings_revert|fn_os_settings_set|fn_report_drilldown|fn_rfq_board|fn_self_review|fn_suppliers_board|fn_ws_company_os|fn_ws_customer_behavior|fn_ws_exec_home|fn_ws_live_company|fn_ws_notifications)\M') body_callers,
  (select string_agg(jobname, ', ') from cron.job where command ~ '\m(fn_action_authority_rank|fn_action_invoke_dispatch|fn_action_resolve_approver|fn_agent_context|fn_agent_context_v3|fn_agent_handoff_inbox|fn_agent_institutional_memory|fn_customers_board|fn_dbx_category|fn_entity_comment_add|fn_entity_files|fn_goal_attainment|fn_inbox_list|fn_knowledge_staleness_tag|fn_os_ai_quality|fn_os_automation_list|fn_os_automation_reschedule|fn_os_automation_run|fn_os_automation_set_active|fn_os_catalog_get|fn_os_catalog_list|fn_os_catalog_save_fields|fn_os_catalog_spec_delete|fn_os_catalog_spec_upsert|fn_os_dashboard_viz|fn_os_detail|fn_os_health|fn_os_health_brief|fn_os_incident_list|fn_os_incident_open|fn_os_incident_resolve|fn_os_list|fn_os_memory|fn_os_nav|fn_os_open_access|fn_os_reconcile|fn_os_record|fn_os_review|fn_os_runbooks|fn_os_search|fn_os_settings_history|fn_os_settings_list|fn_os_settings_revert|fn_os_settings_set|fn_report_drilldown|fn_rfq_board|fn_self_review|fn_suppliers_board|fn_ws_company_os|fn_ws_customer_behavior|fn_ws_exec_home|fn_ws_live_company|fn_ws_notifications)\M') cron_callers,
  (select string_agg(schemaname || '.' || viewname, ', ') from pg_views where schemaname not in ('retired', 'pg_catalog', 'information_schema') and definition ~ '\m(fn_action_authority_rank|fn_action_invoke_dispatch|fn_action_resolve_approver|fn_agent_context|fn_agent_context_v3|fn_agent_handoff_inbox|fn_agent_institutional_memory|fn_customers_board|fn_dbx_category|fn_entity_comment_add|fn_entity_files|fn_goal_attainment|fn_inbox_list|fn_knowledge_staleness_tag|fn_os_ai_quality|fn_os_automation_list|fn_os_automation_reschedule|fn_os_automation_run|fn_os_automation_set_active|fn_os_catalog_get|fn_os_catalog_list|fn_os_catalog_save_fields|fn_os_catalog_spec_delete|fn_os_catalog_spec_upsert|fn_os_dashboard_viz|fn_os_detail|fn_os_health|fn_os_health_brief|fn_os_incident_list|fn_os_incident_open|fn_os_incident_resolve|fn_os_list|fn_os_memory|fn_os_nav|fn_os_open_access|fn_os_reconcile|fn_os_record|fn_os_review|fn_os_runbooks|fn_os_search|fn_os_settings_history|fn_os_settings_list|fn_os_settings_revert|fn_os_settings_set|fn_report_drilldown|fn_rfq_board|fn_self_review|fn_suppliers_board|fn_ws_company_os|fn_ws_customer_behavior|fn_ws_exec_home|fn_ws_live_company|fn_ws_notifications)\M') view_callers,
  (select string_agg(tablename || '.' || policyname, ', ') from pg_policies where coalesce(qual, '') || ' ' || coalesce(with_check, '') ~ '\m(fn_action_authority_rank|fn_action_invoke_dispatch|fn_action_resolve_approver|fn_agent_context|fn_agent_context_v3|fn_agent_handoff_inbox|fn_agent_institutional_memory|fn_customers_board|fn_dbx_category|fn_entity_comment_add|fn_entity_files|fn_goal_attainment|fn_inbox_list|fn_knowledge_staleness_tag|fn_os_ai_quality|fn_os_automation_list|fn_os_automation_reschedule|fn_os_automation_run|fn_os_automation_set_active|fn_os_catalog_get|fn_os_catalog_list|fn_os_catalog_save_fields|fn_os_catalog_spec_delete|fn_os_catalog_spec_upsert|fn_os_dashboard_viz|fn_os_detail|fn_os_health|fn_os_health_brief|fn_os_incident_list|fn_os_incident_open|fn_os_incident_resolve|fn_os_list|fn_os_memory|fn_os_nav|fn_os_open_access|fn_os_reconcile|fn_os_record|fn_os_review|fn_os_runbooks|fn_os_search|fn_os_settings_history|fn_os_settings_list|fn_os_settings_revert|fn_os_settings_set|fn_report_drilldown|fn_rfq_board|fn_self_review|fn_suppliers_board|fn_ws_company_os|fn_ws_customer_behavior|fn_ws_exec_home|fn_ws_live_company|fn_ws_notifications)\M') policy_callers,
  (select string_agg(c.relname, ', ') from pg_attrdef ad join pg_class c on c.oid = ad.adrelid where pg_get_expr(ad.adbin, ad.adrelid) ~ '\m(fn_action_authority_rank|fn_action_invoke_dispatch|fn_action_resolve_approver|fn_agent_context|fn_agent_context_v3|fn_agent_handoff_inbox|fn_agent_institutional_memory|fn_customers_board|fn_dbx_category|fn_entity_comment_add|fn_entity_files|fn_goal_attainment|fn_inbox_list|fn_knowledge_staleness_tag|fn_os_ai_quality|fn_os_automation_list|fn_os_automation_reschedule|fn_os_automation_run|fn_os_automation_set_active|fn_os_catalog_get|fn_os_catalog_list|fn_os_catalog_save_fields|fn_os_catalog_spec_delete|fn_os_catalog_spec_upsert|fn_os_dashboard_viz|fn_os_detail|fn_os_health|fn_os_health_brief|fn_os_incident_list|fn_os_incident_open|fn_os_incident_resolve|fn_os_list|fn_os_memory|fn_os_nav|fn_os_open_access|fn_os_reconcile|fn_os_record|fn_os_review|fn_os_runbooks|fn_os_search|fn_os_settings_history|fn_os_settings_list|fn_os_settings_revert|fn_os_settings_set|fn_report_drilldown|fn_rfq_board|fn_self_review|fn_suppliers_board|fn_ws_company_os|fn_ws_customer_behavior|fn_ws_exec_home|fn_ws_live_company|fn_ws_notifications)\M') default_callers,
  (select string_agg(c.relname || '.' || t.tgname, ', ') from pg_trigger t join pg_proc p on p.oid = t.tgfoid join pg_namespace pn on pn.oid = p.pronamespace
     join pg_class c on c.oid = t.tgrelid join pg_namespace cn on cn.oid = c.relnamespace where pn.nspname = 'retired' and cn.nspname <> 'retired') trigger_callers,
  (select count(*) from sig, unnest(array['anon', 'authenticated', 'service_role']) r(role)
     where to_regprocedure('retired.' || s) is not null and has_function_privilege(r.role, to_regprocedure('retired.' || s), 'execute')) still_executable)
select case when moved = wanted and left_in_public = 0 and body_callers is null and cron_callers is null and view_callers is null
             and policy_callers is null and default_callers is null and trigger_callers is null and still_executable = 0
            then 'PROBE OK: os_console: ' || moved || ' of ' || wanted || ' routines in schema retired, none left in public, no caller outside retired, executable by no API role'
            else 'PROBE FAILED: os_console: moved ' || moved || '/' || wanted || ', left in public ' || left_in_public
                 || ', bodies [' || coalesce(body_callers, '') || '], cron [' || coalesce(cron_callers, '') || '], views [' || coalesce(view_callers, '')
                 || '], policies [' || coalesce(policy_callers, '') || '], defaults [' || coalesce(default_callers, '') || '], triggers [' || coalesce(trigger_callers, '')
                 || '], executable by an API role ' || still_executable end as verdict
  from v;
