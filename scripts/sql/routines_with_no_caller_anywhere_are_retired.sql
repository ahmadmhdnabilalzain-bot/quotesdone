-- ROUTINES WITH NO CALLER ANYWHERE ARE RETIRED.
--
-- Seat: it_engineer. Founder ledgers 1714 and 1715 (16 Nov 2026): remove what is unnecessary and prove each removal with
-- evidence, and prove everything is still fine.
--
-- WHAT WAS WRONG. From the 219 routines the 16 Nov audit found with no live caller, these are the ones re-measured on
-- production today as HIGH: no caller of any kind listed below, no top-level call since 2 Nov, nothing in scripts or checks
-- that runs them (staging blueprints, seeds and org-as-code JSON only list names), and none touches money, the books, PDPL,
-- the backups, an audit log, the v1.2 support toolkit, the knowledge library, a founder-decision tool run by hand, or work
-- another seat has open. fn_workflow_step_done stays: fn_workflow_step_deterministic_done (a check reads it) calls it.
-- registered_supplier_count was executable by anon; no page, statement or body calls it.
-- KEPT although nothing calls them today: fn_order_thread_transcript, fn_escalation_clock_adopts_stale_person_requests and
-- fn_escalation_stale_apology (defined 13-16 Nov; a caller may be on an open branch); the books (fn_accountant_*), ads
-- (fn_ad_decision_mark_executed), sanctions (fn_sanctions_screen_tick*), the v1.2 support toolkit (fn_support_*), the
-- knowledge library, the demo purge (ruling 1539), the session work queues (fn_it_code_defect_*), and the approve, decide
-- and publish routines a session may run by hand on the founder's word (fn_kb_gov_approve, fn_review_decide,
-- fn_prompt_reject_draft, fn_report_recommendation_approve, fn_marketing_blog_publish, fn_marketing_month_plan_founder_decides,
-- fn_marketing_social_handoff_answered, fn_supplier_invite_test_send, fn_founder_open_instructions).
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
--   fn_action_release_held()                                               mentioned only by: sqlfile:2
--   fn_ceo_standing()                                                      mentioned only by: sqlfile:2
--   fn_dispatch_agent_knowledge_gaps(integer,integer)                      mentioned only by: sqlfile:2
--   kn_task(text,boolean,text,text,text,jsonb,text,text)                   mentioned only by: sqlfile:3 body of fn_dispatch_agent_knowledge_gaps
--   fn_it_refusal_is_policy(text,jsonb)                                    mentioned only by: sqlfile:9
--   fn_it_run_is_held(text,timestamp with time zone,jsonb,text)            mentioned only by: sqlfile:7
--   fn_kb_embed_backlog()                                                  mentioned only by: sqlfile:2
--   fn_kb_embed_claim(integer,text[],text[],boolean)                       mentioned only by: sqlfile:4 archive:1
--   fn_knowledge_exam_summary()                                            mentioned only by: sqlfile:3
--   fn_licence_ask_close_on_intake(bigint)                                 mentioned only by: sqlfile:3
--   fn_org_task_assign(integer)                                            mentioned only by: sqlfile:10 archive:2
--   fn_recommend_deterministic(bigint,boolean)                             mentioned only by: sqlfile:4
--   fn_security_watch(interval)                                            mentioned only by: sqlfile:2
--   fn_target_baseline(bigint)                                             mentioned only by: sqlfile:2
--   fn_resilience_step_board()                                             mentioned only by: sqlfile:2
--   fn_ai_quality_watch()                                                  mentioned only by: sqlfile:9 script:2
--   fn_expiring_docs(integer)                                              mentioned only by: sqlfile:2 script:2
--   registered_supplier_count()                                            mentioned only by: sqlfile:12 script:2
--   fn_supplier_exception_open(bigint,text)                                mentioned only by: sqlfile:4 script:2
--   fn_supplier_exception_close(bigint,text)                               mentioned only by: sqlfile:4 script:1
--   fn_event_consolidate()                                                 mentioned only by: sqlfile:7 script:1
--   fn_workflow_start_due(integer)                                         mentioned only by: sqlfile:3 archive:1 script:2
--   fn_workflow_step_sweep(integer)                                        mentioned only by: sqlfile:15 archive:1 script:1
--   fn_execution_sweep(integer)                                            mentioned only by: sqlfile:7 archive:1 body of fn_workflow_step_sweep
--   fn_workflow_step_claim(integer)                                        mentioned only by: sqlfile:13
--   fn_knowledge_gaps(integer,integer)                                     mentioned only by: sqlfile:4 archive:1 script:1 body of fn_dispatch_agent_knowledge_gaps
--   fn_employee_knowledge_freshness(integer,integer)                       mentioned only by: sqlfile:2 body of fn_knowledge_gaps
--
-- REVERSAL, one line per object (run as postgres): back to public, with the EXECUTE grants it had on 16 Nov:
--   alter function retired.fn_action_release_held() set schema public; grant execute on function public.fn_action_release_held() to public, service_role;
--   alter function retired.fn_ceo_standing() set schema public; grant execute on function public.fn_ceo_standing() to public, service_role;
--   alter function retired.fn_dispatch_agent_knowledge_gaps(integer,integer) set schema public; grant execute on function public.fn_dispatch_agent_knowledge_gaps(integer,integer) to service_role;
--   alter function retired.kn_task(text,boolean,text,text,text,jsonb,text,text) set schema public; grant execute on function public.kn_task(text,boolean,text,text,text,jsonb,text,text) to service_role;
--   alter function retired.fn_it_refusal_is_policy(text,jsonb) set schema public; grant execute on function public.fn_it_refusal_is_policy(text,jsonb) to service_role;
--   alter function retired.fn_it_run_is_held(text,timestamp with time zone,jsonb,text) set schema public; grant execute on function public.fn_it_run_is_held(text,timestamp with time zone,jsonb,text) to service_role;
--   alter function retired.fn_kb_embed_backlog() set schema public; grant execute on function public.fn_kb_embed_backlog() to service_role;
--   alter function retired.fn_kb_embed_claim(integer,text[],text[],boolean) set schema public; grant execute on function public.fn_kb_embed_claim(integer,text[],text[],boolean) to service_role;
--   alter function retired.fn_knowledge_exam_summary() set schema public; grant execute on function public.fn_knowledge_exam_summary() to service_role;
--   alter function retired.fn_licence_ask_close_on_intake(bigint) set schema public; grant execute on function public.fn_licence_ask_close_on_intake(bigint) to service_role;
--   alter function retired.fn_org_task_assign(integer) set schema public; grant execute on function public.fn_org_task_assign(integer) to service_role;
--   alter function retired.fn_recommend_deterministic(bigint,boolean) set schema public; grant execute on function public.fn_recommend_deterministic(bigint,boolean) to service_role;
--   alter function retired.fn_security_watch(interval) set schema public; grant execute on function public.fn_security_watch(interval) to service_role;
--   alter function retired.fn_target_baseline(bigint) set schema public; grant execute on function public.fn_target_baseline(bigint) to service_role;
--   alter function retired.fn_resilience_step_board() set schema public; grant execute on function public.fn_resilience_step_board() to service_role;
--   alter function retired.fn_ai_quality_watch() set schema public; grant execute on function public.fn_ai_quality_watch() to service_role;
--   alter function retired.fn_expiring_docs(integer) set schema public; grant execute on function public.fn_expiring_docs(integer) to service_role;
--   alter function retired.registered_supplier_count() set schema public; grant execute on function public.registered_supplier_count() to public, anon, authenticated, service_role;
--   alter function retired.fn_supplier_exception_open(bigint,text) set schema public; grant execute on function public.fn_supplier_exception_open(bigint,text) to service_role;
--   alter function retired.fn_supplier_exception_close(bigint,text) set schema public; grant execute on function public.fn_supplier_exception_close(bigint,text) to service_role;
--   alter function retired.fn_event_consolidate() set schema public; grant execute on function public.fn_event_consolidate() to service_role;
--   alter function retired.fn_workflow_start_due(integer) set schema public; grant execute on function public.fn_workflow_start_due(integer) to service_role;
--   alter function retired.fn_workflow_step_sweep(integer) set schema public; grant execute on function public.fn_workflow_step_sweep(integer) to service_role;
--   alter function retired.fn_execution_sweep(integer) set schema public; grant execute on function public.fn_execution_sweep(integer) to service_role;
--   alter function retired.fn_workflow_step_claim(integer) set schema public; grant execute on function public.fn_workflow_step_claim(integer) to service_role;
--   alter function retired.fn_knowledge_gaps(integer,integer) set schema public; grant execute on function public.fn_knowledge_gaps(integer,integer) to service_role;
--   alter function retired.fn_employee_knowledge_freshness(integer,integer) set schema public; grant execute on function public.fn_employee_knowledge_freshness(integer,integer) to service_role;

-- The schema that holds what is retired: owned by postgres, no USAGE for anyone else (PUBLIC, anon, authenticated and
-- service_role cannot even name an object in it), so a retired routine cannot be called and a retired table cannot be read
-- from the API. postgres keeps full access for the phase-2 archive. Idempotent: every cluster file repeats these lines.
create schema if not exists retired;
revoke all on schema retired from public, anon, authenticated, service_role;

do $retire_no_caller$
begin
  if to_regprocedure('public.fn_action_release_held()') is not null then
    revoke all on function public.fn_action_release_held() from public, anon, authenticated, service_role;
    alter function public.fn_action_release_held() set schema retired;
  end if;
  if to_regprocedure('public.fn_ceo_standing()') is not null then
    revoke all on function public.fn_ceo_standing() from public, anon, authenticated, service_role;
    alter function public.fn_ceo_standing() set schema retired;
  end if;
  if to_regprocedure('public.fn_dispatch_agent_knowledge_gaps(integer,integer)') is not null then
    revoke all on function public.fn_dispatch_agent_knowledge_gaps(integer,integer) from public, anon, authenticated, service_role;
    alter function public.fn_dispatch_agent_knowledge_gaps(integer,integer) set schema retired;
  end if;
  if to_regprocedure('public.kn_task(text,boolean,text,text,text,jsonb,text,text)') is not null then
    revoke all on function public.kn_task(text,boolean,text,text,text,jsonb,text,text) from public, anon, authenticated, service_role;
    alter function public.kn_task(text,boolean,text,text,text,jsonb,text,text) set schema retired;
  end if;
  if to_regprocedure('public.fn_it_refusal_is_policy(text,jsonb)') is not null then
    revoke all on function public.fn_it_refusal_is_policy(text,jsonb) from public, anon, authenticated, service_role;
    alter function public.fn_it_refusal_is_policy(text,jsonb) set schema retired;
  end if;
  if to_regprocedure('public.fn_it_run_is_held(text,timestamp with time zone,jsonb,text)') is not null then
    revoke all on function public.fn_it_run_is_held(text,timestamp with time zone,jsonb,text) from public, anon, authenticated, service_role;
    alter function public.fn_it_run_is_held(text,timestamp with time zone,jsonb,text) set schema retired;
  end if;
  if to_regprocedure('public.fn_kb_embed_backlog()') is not null then
    revoke all on function public.fn_kb_embed_backlog() from public, anon, authenticated, service_role;
    alter function public.fn_kb_embed_backlog() set schema retired;
  end if;
  if to_regprocedure('public.fn_kb_embed_claim(integer,text[],text[],boolean)') is not null then
    revoke all on function public.fn_kb_embed_claim(integer,text[],text[],boolean) from public, anon, authenticated, service_role;
    alter function public.fn_kb_embed_claim(integer,text[],text[],boolean) set schema retired;
  end if;
  if to_regprocedure('public.fn_knowledge_exam_summary()') is not null then
    revoke all on function public.fn_knowledge_exam_summary() from public, anon, authenticated, service_role;
    alter function public.fn_knowledge_exam_summary() set schema retired;
  end if;
  if to_regprocedure('public.fn_licence_ask_close_on_intake(bigint)') is not null then
    revoke all on function public.fn_licence_ask_close_on_intake(bigint) from public, anon, authenticated, service_role;
    alter function public.fn_licence_ask_close_on_intake(bigint) set schema retired;
  end if;
  if to_regprocedure('public.fn_org_task_assign(integer)') is not null then
    revoke all on function public.fn_org_task_assign(integer) from public, anon, authenticated, service_role;
    alter function public.fn_org_task_assign(integer) set schema retired;
  end if;
  if to_regprocedure('public.fn_recommend_deterministic(bigint,boolean)') is not null then
    revoke all on function public.fn_recommend_deterministic(bigint,boolean) from public, anon, authenticated, service_role;
    alter function public.fn_recommend_deterministic(bigint,boolean) set schema retired;
  end if;
  if to_regprocedure('public.fn_security_watch(interval)') is not null then
    revoke all on function public.fn_security_watch(interval) from public, anon, authenticated, service_role;
    alter function public.fn_security_watch(interval) set schema retired;
  end if;
  if to_regprocedure('public.fn_target_baseline(bigint)') is not null then
    revoke all on function public.fn_target_baseline(bigint) from public, anon, authenticated, service_role;
    alter function public.fn_target_baseline(bigint) set schema retired;
  end if;
  if to_regprocedure('public.fn_resilience_step_board()') is not null then
    revoke all on function public.fn_resilience_step_board() from public, anon, authenticated, service_role;
    alter function public.fn_resilience_step_board() set schema retired;
  end if;
  if to_regprocedure('public.fn_ai_quality_watch()') is not null then
    revoke all on function public.fn_ai_quality_watch() from public, anon, authenticated, service_role;
    alter function public.fn_ai_quality_watch() set schema retired;
  end if;
  if to_regprocedure('public.fn_expiring_docs(integer)') is not null then
    revoke all on function public.fn_expiring_docs(integer) from public, anon, authenticated, service_role;
    alter function public.fn_expiring_docs(integer) set schema retired;
  end if;
  if to_regprocedure('public.registered_supplier_count()') is not null then
    revoke all on function public.registered_supplier_count() from public, anon, authenticated, service_role;
    alter function public.registered_supplier_count() set schema retired;
  end if;
  if to_regprocedure('public.fn_supplier_exception_open(bigint,text)') is not null then
    revoke all on function public.fn_supplier_exception_open(bigint,text) from public, anon, authenticated, service_role;
    alter function public.fn_supplier_exception_open(bigint,text) set schema retired;
  end if;
  if to_regprocedure('public.fn_supplier_exception_close(bigint,text)') is not null then
    revoke all on function public.fn_supplier_exception_close(bigint,text) from public, anon, authenticated, service_role;
    alter function public.fn_supplier_exception_close(bigint,text) set schema retired;
  end if;
  if to_regprocedure('public.fn_event_consolidate()') is not null then
    revoke all on function public.fn_event_consolidate() from public, anon, authenticated, service_role;
    alter function public.fn_event_consolidate() set schema retired;
  end if;
  if to_regprocedure('public.fn_workflow_start_due(integer)') is not null then
    revoke all on function public.fn_workflow_start_due(integer) from public, anon, authenticated, service_role;
    alter function public.fn_workflow_start_due(integer) set schema retired;
  end if;
  if to_regprocedure('public.fn_workflow_step_sweep(integer)') is not null then
    revoke all on function public.fn_workflow_step_sweep(integer) from public, anon, authenticated, service_role;
    alter function public.fn_workflow_step_sweep(integer) set schema retired;
  end if;
  if to_regprocedure('public.fn_execution_sweep(integer)') is not null then
    revoke all on function public.fn_execution_sweep(integer) from public, anon, authenticated, service_role;
    alter function public.fn_execution_sweep(integer) set schema retired;
  end if;
  if to_regprocedure('public.fn_workflow_step_claim(integer)') is not null then
    revoke all on function public.fn_workflow_step_claim(integer) from public, anon, authenticated, service_role;
    alter function public.fn_workflow_step_claim(integer) set schema retired;
  end if;
  if to_regprocedure('public.fn_knowledge_gaps(integer,integer)') is not null then
    revoke all on function public.fn_knowledge_gaps(integer,integer) from public, anon, authenticated, service_role;
    alter function public.fn_knowledge_gaps(integer,integer) set schema retired;
  end if;
  if to_regprocedure('public.fn_employee_knowledge_freshness(integer,integer)') is not null then
    revoke all on function public.fn_employee_knowledge_freshness(integer,integer) from public, anon, authenticated, service_role;
    alter function public.fn_employee_knowledge_freshness(integer,integer) set schema retired;
  end if;
end
$retire_no_caller$;

-- PROBE (no_caller): a verdict row, never a raise (a raise would roll back the moves above). It reads, live, at apply time:
--   moved      every signature is now in schema retired;  gone  no routine of these names is left in public;
--   callers    no routine outside schema retired names one of them in its body (comments stripped), no cron command,
--              no view, no policy, no column default, and no trigger outside retired runs a retired routine;
--   closed     no role but postgres may execute a retired routine.
with sig(s) as (values
         ('fn_action_release_held()'),
         ('fn_ceo_standing()'),
         ('fn_dispatch_agent_knowledge_gaps(integer,integer)'),
         ('kn_task(text,boolean,text,text,text,jsonb,text,text)'),
         ('fn_it_refusal_is_policy(text,jsonb)'),
         ('fn_it_run_is_held(text,timestamp with time zone,jsonb,text)'),
         ('fn_kb_embed_backlog()'),
         ('fn_kb_embed_claim(integer,text[],text[],boolean)'),
         ('fn_knowledge_exam_summary()'),
         ('fn_licence_ask_close_on_intake(bigint)'),
         ('fn_org_task_assign(integer)'),
         ('fn_recommend_deterministic(bigint,boolean)'),
         ('fn_security_watch(interval)'),
         ('fn_target_baseline(bigint)'),
         ('fn_resilience_step_board()'),
         ('fn_ai_quality_watch()'),
         ('fn_expiring_docs(integer)'),
         ('registered_supplier_count()'),
         ('fn_supplier_exception_open(bigint,text)'),
         ('fn_supplier_exception_close(bigint,text)'),
         ('fn_event_consolidate()'),
         ('fn_workflow_start_due(integer)'),
         ('fn_workflow_step_sweep(integer)'),
         ('fn_execution_sweep(integer)'),
         ('fn_workflow_step_claim(integer)'),
         ('fn_knowledge_gaps(integer,integer)'),
         ('fn_employee_knowledge_freshness(integer,integer)')),
nm(n) as (select unnest(array['fn_action_release_held','fn_ai_quality_watch','fn_ceo_standing','fn_dispatch_agent_knowledge_gaps','fn_employee_knowledge_freshness','fn_event_consolidate','fn_execution_sweep','fn_expiring_docs','fn_it_refusal_is_policy','fn_it_run_is_held','fn_kb_embed_backlog','fn_kb_embed_claim','fn_knowledge_exam_summary','fn_knowledge_gaps','fn_licence_ask_close_on_intake','fn_org_task_assign','fn_recommend_deterministic','fn_resilience_step_board','fn_security_watch','fn_supplier_exception_close','fn_supplier_exception_open','fn_target_baseline','fn_workflow_start_due','fn_workflow_step_claim','fn_workflow_step_sweep','kn_task','registered_supplier_count'])),
body as (select regexp_replace(regexp_replace(p.prosrc, '/\*.*?\*/', '', 'g'), '--[^\n]*', '', 'g') src, ns.nspname || '.' || p.proname who
           from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
          where ns.nspname not in ('retired', 'pg_catalog', 'information_schema')
            and not exists (select 1 from pg_depend d where d.objid = p.oid and d.deptype = 'e')),
v as (select
  (select count(*) from sig where to_regprocedure('retired.' || s) is not null) moved,
  (select count(*) from sig) wanted,
  (select count(*) from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace join nm on nm.n = p.proname where ns.nspname = 'public') left_in_public,
  (select string_agg(who || ' names ' || substring(src from '\m(fn_action_release_held|fn_ai_quality_watch|fn_ceo_standing|fn_dispatch_agent_knowledge_gaps|fn_employee_knowledge_freshness|fn_event_consolidate|fn_execution_sweep|fn_expiring_docs|fn_it_refusal_is_policy|fn_it_run_is_held|fn_kb_embed_backlog|fn_kb_embed_claim|fn_knowledge_exam_summary|fn_knowledge_gaps|fn_licence_ask_close_on_intake|fn_org_task_assign|fn_recommend_deterministic|fn_resilience_step_board|fn_security_watch|fn_supplier_exception_close|fn_supplier_exception_open|fn_target_baseline|fn_workflow_start_due|fn_workflow_step_claim|fn_workflow_step_sweep|kn_task|registered_supplier_count)\M'), '; ') from body where src ~ '\m(fn_action_release_held|fn_ai_quality_watch|fn_ceo_standing|fn_dispatch_agent_knowledge_gaps|fn_employee_knowledge_freshness|fn_event_consolidate|fn_execution_sweep|fn_expiring_docs|fn_it_refusal_is_policy|fn_it_run_is_held|fn_kb_embed_backlog|fn_kb_embed_claim|fn_knowledge_exam_summary|fn_knowledge_gaps|fn_licence_ask_close_on_intake|fn_org_task_assign|fn_recommend_deterministic|fn_resilience_step_board|fn_security_watch|fn_supplier_exception_close|fn_supplier_exception_open|fn_target_baseline|fn_workflow_start_due|fn_workflow_step_claim|fn_workflow_step_sweep|kn_task|registered_supplier_count)\M') body_callers,
  (select string_agg(jobname, ', ') from cron.job where command ~ '\m(fn_action_release_held|fn_ai_quality_watch|fn_ceo_standing|fn_dispatch_agent_knowledge_gaps|fn_employee_knowledge_freshness|fn_event_consolidate|fn_execution_sweep|fn_expiring_docs|fn_it_refusal_is_policy|fn_it_run_is_held|fn_kb_embed_backlog|fn_kb_embed_claim|fn_knowledge_exam_summary|fn_knowledge_gaps|fn_licence_ask_close_on_intake|fn_org_task_assign|fn_recommend_deterministic|fn_resilience_step_board|fn_security_watch|fn_supplier_exception_close|fn_supplier_exception_open|fn_target_baseline|fn_workflow_start_due|fn_workflow_step_claim|fn_workflow_step_sweep|kn_task|registered_supplier_count)\M') cron_callers,
  (select string_agg(schemaname || '.' || viewname, ', ') from pg_views where schemaname not in ('retired', 'pg_catalog', 'information_schema') and definition ~ '\m(fn_action_release_held|fn_ai_quality_watch|fn_ceo_standing|fn_dispatch_agent_knowledge_gaps|fn_employee_knowledge_freshness|fn_event_consolidate|fn_execution_sweep|fn_expiring_docs|fn_it_refusal_is_policy|fn_it_run_is_held|fn_kb_embed_backlog|fn_kb_embed_claim|fn_knowledge_exam_summary|fn_knowledge_gaps|fn_licence_ask_close_on_intake|fn_org_task_assign|fn_recommend_deterministic|fn_resilience_step_board|fn_security_watch|fn_supplier_exception_close|fn_supplier_exception_open|fn_target_baseline|fn_workflow_start_due|fn_workflow_step_claim|fn_workflow_step_sweep|kn_task|registered_supplier_count)\M') view_callers,
  (select string_agg(tablename || '.' || policyname, ', ') from pg_policies where coalesce(qual, '') || ' ' || coalesce(with_check, '') ~ '\m(fn_action_release_held|fn_ai_quality_watch|fn_ceo_standing|fn_dispatch_agent_knowledge_gaps|fn_employee_knowledge_freshness|fn_event_consolidate|fn_execution_sweep|fn_expiring_docs|fn_it_refusal_is_policy|fn_it_run_is_held|fn_kb_embed_backlog|fn_kb_embed_claim|fn_knowledge_exam_summary|fn_knowledge_gaps|fn_licence_ask_close_on_intake|fn_org_task_assign|fn_recommend_deterministic|fn_resilience_step_board|fn_security_watch|fn_supplier_exception_close|fn_supplier_exception_open|fn_target_baseline|fn_workflow_start_due|fn_workflow_step_claim|fn_workflow_step_sweep|kn_task|registered_supplier_count)\M') policy_callers,
  (select string_agg(c.relname, ', ') from pg_attrdef ad join pg_class c on c.oid = ad.adrelid where pg_get_expr(ad.adbin, ad.adrelid) ~ '\m(fn_action_release_held|fn_ai_quality_watch|fn_ceo_standing|fn_dispatch_agent_knowledge_gaps|fn_employee_knowledge_freshness|fn_event_consolidate|fn_execution_sweep|fn_expiring_docs|fn_it_refusal_is_policy|fn_it_run_is_held|fn_kb_embed_backlog|fn_kb_embed_claim|fn_knowledge_exam_summary|fn_knowledge_gaps|fn_licence_ask_close_on_intake|fn_org_task_assign|fn_recommend_deterministic|fn_resilience_step_board|fn_security_watch|fn_supplier_exception_close|fn_supplier_exception_open|fn_target_baseline|fn_workflow_start_due|fn_workflow_step_claim|fn_workflow_step_sweep|kn_task|registered_supplier_count)\M') default_callers,
  (select string_agg(c.relname || '.' || t.tgname, ', ') from pg_trigger t join pg_proc p on p.oid = t.tgfoid join pg_namespace pn on pn.oid = p.pronamespace
     join pg_class c on c.oid = t.tgrelid join pg_namespace cn on cn.oid = c.relnamespace where pn.nspname = 'retired' and cn.nspname <> 'retired') trigger_callers,
  (select count(*) from sig, unnest(array['anon', 'authenticated', 'service_role']) r(role)
     where to_regprocedure('retired.' || s) is not null and has_function_privilege(r.role, to_regprocedure('retired.' || s), 'execute')) still_executable)
select case when moved = wanted and left_in_public = 0 and body_callers is null and cron_callers is null and view_callers is null
             and policy_callers is null and default_callers is null and trigger_callers is null and still_executable = 0
            then 'PROBE OK: no_caller: ' || moved || ' of ' || wanted || ' routines in schema retired, none left in public, no caller outside retired, executable by no API role'
            else 'PROBE FAILED: no_caller: moved ' || moved || '/' || wanted || ', left in public ' || left_in_public
                 || ', bodies [' || coalesce(body_callers, '') || '], cron [' || coalesce(cron_callers, '') || '], views [' || coalesce(view_callers, '')
                 || '], policies [' || coalesce(policy_callers, '') || '], defaults [' || coalesce(default_callers, '') || '], triggers [' || coalesce(trigger_callers, '')
                 || '], executable by an API role ' || still_executable end as verdict
  from v;
