-- TRIGGER FUNCTIONS THAT NO TRIGGER RUNS ARE RETIRED.
--
-- Seat: it_engineer. Founder ledgers 1714 and 1715 (16 Nov 2026): remove what is unnecessary and prove each removal with
-- evidence, and prove everything is still fine.
--
-- WHAT WAS WRONG. Eight routines return `trigger` and no trigger in any schema runs them (pg_trigger, all non-internal rows),
-- plus fn_customer_terms_accept, whose only caller is one of them. Two are broken as well: trg_legal_documents_hash and
-- trg_terms_pins_sync lost their triggers on 7 Sep because the routines they call were deleted (removed_trigger_log ids 11
-- and 12: fn_legal_body_without_labels, fn_legal_version_bump, fn_terms_pins_sync), so either would throw if called. Two
-- were executable by anon and authenticated (trg_legal_documents_hash, trg_agent_knowledge_metadata).
-- KEPT: fn_kb_chunks_swap_log (also triggerless) - scripts/kb/kb_chunks_copy_swap.mjs attaches it for the next rewrite.
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
--   trg_legal_documents_hash()                                             mentioned only by: sqlfile:2
--   trg_terms_pins_sync()                                                  mentioned only by: sqlfile:1 script:1
--   fn_customer_terms_accepted_trg()                                       mentioned only by: sqlfile:1
--   fn_customer_terms_accept(uuid,text)                                    mentioned only by: sqlfile:4 body of fn_customer_terms_accepted_trg
--   fn_customer_welcome_trg()                                              mentioned only by: sqlfile:1
--   fn_emit_campaign_published()                                           mentioned only by: sqlfile:1
--   fn_org_authority_guard()                                               mentioned only by: sqlfile:2
--   trg_agent_knowledge_metadata()                                         mentioned only by: sqlfile:4
--   fn_page_high_agent_action()                                            mentioned only by: sqlfile:4
--
-- REVERSAL, one line per object (run as postgres): back to public, with the EXECUTE grants it had on 16 Nov:
--   alter function retired.trg_legal_documents_hash() set schema public; grant execute on function public.trg_legal_documents_hash() to public, service_role;
--   alter function retired.trg_terms_pins_sync() set schema public; grant execute on function public.trg_terms_pins_sync() to service_role;
--   alter function retired.fn_customer_terms_accepted_trg() set schema public; grant execute on function public.fn_customer_terms_accepted_trg() to service_role;
--   alter function retired.fn_customer_terms_accept(uuid,text) set schema public; grant execute on function public.fn_customer_terms_accept(uuid,text) to service_role;
--   alter function retired.fn_customer_welcome_trg() set schema public; grant execute on function public.fn_customer_welcome_trg() to service_role;
--   alter function retired.fn_emit_campaign_published() set schema public; grant execute on function public.fn_emit_campaign_published() to service_role;
--   alter function retired.fn_org_authority_guard() set schema public; grant execute on function public.fn_org_authority_guard() to service_role;
--   alter function retired.trg_agent_knowledge_metadata() set schema public; grant execute on function public.trg_agent_knowledge_metadata() to public, service_role;
--   alter function retired.fn_page_high_agent_action() set schema public; grant execute on function public.fn_page_high_agent_action() to service_role;

-- The schema that holds what is retired: owned by postgres, no USAGE for anyone else (PUBLIC, anon, authenticated and
-- service_role cannot even name an object in it), so a retired routine cannot be called and a retired table cannot be read
-- from the API. postgres keeps full access for the phase-2 archive. Idempotent: every cluster file repeats these lines.
create schema if not exists retired;
revoke all on schema retired from public, anon, authenticated, service_role;

do $retire_orphan_triggers$
begin
  if to_regprocedure('public.trg_legal_documents_hash()') is not null then
    revoke all on function public.trg_legal_documents_hash() from public, anon, authenticated, service_role;
    alter function public.trg_legal_documents_hash() set schema retired;
  end if;
  if to_regprocedure('public.trg_terms_pins_sync()') is not null then
    revoke all on function public.trg_terms_pins_sync() from public, anon, authenticated, service_role;
    alter function public.trg_terms_pins_sync() set schema retired;
  end if;
  if to_regprocedure('public.fn_customer_terms_accepted_trg()') is not null then
    revoke all on function public.fn_customer_terms_accepted_trg() from public, anon, authenticated, service_role;
    alter function public.fn_customer_terms_accepted_trg() set schema retired;
  end if;
  if to_regprocedure('public.fn_customer_terms_accept(uuid,text)') is not null then
    revoke all on function public.fn_customer_terms_accept(uuid,text) from public, anon, authenticated, service_role;
    alter function public.fn_customer_terms_accept(uuid,text) set schema retired;
  end if;
  if to_regprocedure('public.fn_customer_welcome_trg()') is not null then
    revoke all on function public.fn_customer_welcome_trg() from public, anon, authenticated, service_role;
    alter function public.fn_customer_welcome_trg() set schema retired;
  end if;
  if to_regprocedure('public.fn_emit_campaign_published()') is not null then
    revoke all on function public.fn_emit_campaign_published() from public, anon, authenticated, service_role;
    alter function public.fn_emit_campaign_published() set schema retired;
  end if;
  if to_regprocedure('public.fn_org_authority_guard()') is not null then
    revoke all on function public.fn_org_authority_guard() from public, anon, authenticated, service_role;
    alter function public.fn_org_authority_guard() set schema retired;
  end if;
  if to_regprocedure('public.trg_agent_knowledge_metadata()') is not null then
    revoke all on function public.trg_agent_knowledge_metadata() from public, anon, authenticated, service_role;
    alter function public.trg_agent_knowledge_metadata() set schema retired;
  end if;
  if to_regprocedure('public.fn_page_high_agent_action()') is not null then
    revoke all on function public.fn_page_high_agent_action() from public, anon, authenticated, service_role;
    alter function public.fn_page_high_agent_action() set schema retired;
  end if;
end
$retire_orphan_triggers$;

-- PROBE (orphan_triggers): a verdict row, never a raise (a raise would roll back the moves above). It reads, live, at apply time:
--   moved      every signature is now in schema retired;  gone  no routine of these names is left in public;
--   callers    no routine outside schema retired names one of them in its body (comments stripped), no cron command,
--              no view, no policy, no column default, and no trigger outside retired runs a retired routine;
--   closed     no role but postgres may execute a retired routine.
with sig(s) as (values
         ('trg_legal_documents_hash()'),
         ('trg_terms_pins_sync()'),
         ('fn_customer_terms_accepted_trg()'),
         ('fn_customer_terms_accept(uuid,text)'),
         ('fn_customer_welcome_trg()'),
         ('fn_emit_campaign_published()'),
         ('fn_org_authority_guard()'),
         ('trg_agent_knowledge_metadata()'),
         ('fn_page_high_agent_action()')),
nm(n) as (select unnest(array['fn_customer_terms_accept','fn_customer_terms_accepted_trg','fn_customer_welcome_trg','fn_emit_campaign_published','fn_org_authority_guard','fn_page_high_agent_action','trg_agent_knowledge_metadata','trg_legal_documents_hash','trg_terms_pins_sync'])),
body as (select regexp_replace(regexp_replace(p.prosrc, '/\*.*?\*/', '', 'g'), '--[^\n]*', '', 'g') src, ns.nspname || '.' || p.proname who
           from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
          where ns.nspname not in ('retired', 'pg_catalog', 'information_schema')
            and not exists (select 1 from pg_depend d where d.objid = p.oid and d.deptype = 'e')),
v as (select
  (select count(*) from sig where to_regprocedure('retired.' || s) is not null) moved,
  (select count(*) from sig) wanted,
  (select count(*) from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace join nm on nm.n = p.proname where ns.nspname = 'public') left_in_public,
  (select string_agg(who || ' names ' || substring(src from '\m(fn_customer_terms_accept|fn_customer_terms_accepted_trg|fn_customer_welcome_trg|fn_emit_campaign_published|fn_org_authority_guard|fn_page_high_agent_action|trg_agent_knowledge_metadata|trg_legal_documents_hash|trg_terms_pins_sync)\M'), '; ') from body where src ~ '\m(fn_customer_terms_accept|fn_customer_terms_accepted_trg|fn_customer_welcome_trg|fn_emit_campaign_published|fn_org_authority_guard|fn_page_high_agent_action|trg_agent_knowledge_metadata|trg_legal_documents_hash|trg_terms_pins_sync)\M') body_callers,
  (select string_agg(jobname, ', ') from cron.job where command ~ '\m(fn_customer_terms_accept|fn_customer_terms_accepted_trg|fn_customer_welcome_trg|fn_emit_campaign_published|fn_org_authority_guard|fn_page_high_agent_action|trg_agent_knowledge_metadata|trg_legal_documents_hash|trg_terms_pins_sync)\M') cron_callers,
  (select string_agg(schemaname || '.' || viewname, ', ') from pg_views where schemaname not in ('retired', 'pg_catalog', 'information_schema') and definition ~ '\m(fn_customer_terms_accept|fn_customer_terms_accepted_trg|fn_customer_welcome_trg|fn_emit_campaign_published|fn_org_authority_guard|fn_page_high_agent_action|trg_agent_knowledge_metadata|trg_legal_documents_hash|trg_terms_pins_sync)\M') view_callers,
  (select string_agg(tablename || '.' || policyname, ', ') from pg_policies where coalesce(qual, '') || ' ' || coalesce(with_check, '') ~ '\m(fn_customer_terms_accept|fn_customer_terms_accepted_trg|fn_customer_welcome_trg|fn_emit_campaign_published|fn_org_authority_guard|fn_page_high_agent_action|trg_agent_knowledge_metadata|trg_legal_documents_hash|trg_terms_pins_sync)\M') policy_callers,
  (select string_agg(c.relname, ', ') from pg_attrdef ad join pg_class c on c.oid = ad.adrelid where pg_get_expr(ad.adbin, ad.adrelid) ~ '\m(fn_customer_terms_accept|fn_customer_terms_accepted_trg|fn_customer_welcome_trg|fn_emit_campaign_published|fn_org_authority_guard|fn_page_high_agent_action|trg_agent_knowledge_metadata|trg_legal_documents_hash|trg_terms_pins_sync)\M') default_callers,
  (select string_agg(c.relname || '.' || t.tgname, ', ') from pg_trigger t join pg_proc p on p.oid = t.tgfoid join pg_namespace pn on pn.oid = p.pronamespace
     join pg_class c on c.oid = t.tgrelid join pg_namespace cn on cn.oid = c.relnamespace where pn.nspname = 'retired' and cn.nspname <> 'retired') trigger_callers,
  (select count(*) from sig, unnest(array['anon', 'authenticated', 'service_role']) r(role)
     where to_regprocedure('retired.' || s) is not null and has_function_privilege(r.role, to_regprocedure('retired.' || s), 'execute')) still_executable)
select case when moved = wanted and left_in_public = 0 and body_callers is null and cron_callers is null and view_callers is null
             and policy_callers is null and default_callers is null and trigger_callers is null and still_executable = 0
            then 'PROBE OK: orphan_triggers: ' || moved || ' of ' || wanted || ' routines in schema retired, none left in public, no caller outside retired, executable by no API role'
            else 'PROBE FAILED: orphan_triggers: moved ' || moved || '/' || wanted || ', left in public ' || left_in_public
                 || ', bodies [' || coalesce(body_callers, '') || '], cron [' || coalesce(cron_callers, '') || '], views [' || coalesce(view_callers, '')
                 || '], policies [' || coalesce(policy_callers, '') || '], defaults [' || coalesce(default_callers, '') || '], triggers [' || coalesce(trigger_callers, '')
                 || '], executable by an API role ' || still_executable end as verdict
  from v;
