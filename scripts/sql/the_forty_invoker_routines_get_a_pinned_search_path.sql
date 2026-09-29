-- THE FORTY INVOKER ROUTINES GET A PINNED SEARCH_PATH (platform audit 30 Sep 2026, finding M2).
--
-- Supabase's security advisor reported function_search_path_mutable x40. All 40 are SECURITY
-- INVOKER (measured: pg_proc.prosecdef = false for every one), so the definer hijack does not apply.
-- This is the apply-discipline rule that every routine pins its path, so that its behaviour does not
-- depend on the caller's session.
--
-- NOTHING'S BEHAVIOUR CHANGES. The database default is "$user", public, extensions (measured with
-- `show search_path`). Each routine is pinned to public, extensions, pg_temp (the only role-named schema is pgbouncer, which no caller of these runs as),
-- which is what it resolves against today. ALTER FUNCTION ... SET adds the clause without retyping a
-- body, so prosrc is untouched and canonical_routine_manifest sees no drift. It also keeps the ACL.
--
-- The customer-document RPCs named in the same finding (fn_customer_documents,
-- fn_customer_document_refs) already pin their path and scope rows to auth.email()/auth.uid(). An
-- aborted-transaction probe with two ZZ DEMO customers, signed in as A, returned own=1, other=0,
-- refs_other=0, and a caller with no email saw 0 rows. They are not changed here.
--
-- CAVEAT for the next author: a later CREATE OR REPLACE of any of these without a SET clause drops
-- the pin again (that is how fn_ceo_binding_constraint lost the pin it was given on 9 Sep). The
-- security advisor baseline check is what catches it.

alter function cert.no_mutation() set search_path to 'public', 'extensions', 'pg_temp';
alter function holdout_v2.fn_eff(jsonb,jsonb,text,text) set search_path to 'public', 'extensions', 'pg_temp';
alter function holdout_v2.trg_immutable() set search_path to 'public', 'extensions', 'pg_temp';
alter function holdout_v2.trg_seal_guard() set search_path to 'public', 'extensions', 'pg_temp';
alter function kb_stage.trg_archive_record_version() set search_path to 'public', 'extensions', 'pg_temp';
alter function ops_kb_stage.trg_archive_record_version() set search_path to 'public', 'extensions', 'pg_temp';
alter function public.fn_action_authority_rank(text) set search_path to 'public', 'extensions', 'pg_temp';
alter function public.fn_alert_severe(text) set search_path to 'public', 'extensions', 'pg_temp';
alter function public.fn_artifact_review_valid() set search_path to 'public', 'extensions', 'pg_temp';
alter function public.fn_authority_rank(text) set search_path to 'public', 'extensions', 'pg_temp';
alter function public.fn_ceo_approval_append_only() set search_path to 'public', 'extensions', 'pg_temp';
alter function public.fn_ceo_binding_constraint(jsonb) set search_path to 'public', 'extensions', 'pg_temp';
alter function public.fn_ceo_command_state_guard() set search_path to 'public', 'extensions', 'pg_temp';
alter function public.fn_expense_document(bigint) set search_path to 'public', 'extensions', 'pg_temp';
alter function public.fn_expense_document_coverage() set search_path to 'public', 'extensions', 'pg_temp';
alter function public.fn_gate_state_satisfies(public.gate_state) set search_path to 'public', 'extensions', 'pg_temp';
alter function public.fn_internal_credential_audit_immutable() set search_path to 'public', 'extensions', 'pg_temp';
alter function public.fn_knowledge_provenance_stamp() set search_path to 'public', 'extensions', 'pg_temp';
alter function public.fn_knowledge_staleness_tag(date,text) set search_path to 'public', 'extensions', 'pg_temp';
alter function public.fn_ops_authority_check(text,text,numeric,text) set search_path to 'public', 'extensions', 'pg_temp';
alter function public.fn_org_role_resolve(text) set search_path to 'public', 'extensions', 'pg_temp';
alter function public.fn_org_task_close_needs_an_act() set search_path to 'public', 'extensions', 'pg_temp';
alter function public.fn_phase1_rollback_log_immutable() set search_path to 'public', 'extensions', 'pg_temp';
alter function public.fn_refund_ceo_approval_only() set search_path to 'public', 'extensions', 'pg_temp';
alter function public.fn_refunds_settled_at() set search_path to 'public', 'extensions', 'pg_temp';
alter function public.fn_supplier_changeable() set search_path to 'public', 'extensions', 'pg_temp';
alter function public.fn_supplier_exception_days() set search_path to 'public', 'extensions', 'pg_temp';
alter function public.fn_usd_to_aed() set search_path to 'public', 'extensions', 'pg_temp';
alter function public.fn_wa_model_brief() set search_path to 'public', 'extensions', 'pg_temp';
alter function public.fn_wa_off_topic_reply() set search_path to 'public', 'extensions', 'pg_temp';
alter function public.fn_wa_unmatched_reply() set search_path to 'public', 'extensions', 'pg_temp';
alter function public.trg_agent_knowledge_metadata() set search_path to 'public', 'extensions', 'pg_temp';
alter function public.trg_inquiry_answer_value_immutable() set search_path to 'public', 'extensions', 'pg_temp';
alter function public.trg_org_role_no_cycle() set search_path to 'public', 'extensions', 'pg_temp';
alter function public.trg_org_role_touch() set search_path to 'public', 'extensions', 'pg_temp';
alter function public.trg_p2c1_append_only() set search_path to 'public', 'extensions', 'pg_temp';
alter function public.trg_quote_committed_hash() set search_path to 'public', 'extensions', 'pg_temp';
alter function public.trg_refunds_touch() set search_path to 'public', 'extensions', 'pg_temp';
alter function public.trg_scenario_expected_needs_ledger() set search_path to 'public', 'extensions', 'pg_temp';
alter function public.trg_step_run_actor_is_a_real_employee() set search_path to 'public', 'extensions', 'pg_temp';

-- VERDICT: no application routine in these schemas is left without a pinned search_path.
select case when count(*) = 0 then 'PROBE OK'
            else 'PROBE FAILED: ' || count(*) || ' routines still unpinned: '
                 || string_agg(p.oid::regprocedure::text, ', ') end as verdict
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  left join pg_depend d on d.objid = p.oid and d.deptype = 'e'
 where p.prokind = 'f'
   and n.nspname in ('public', 'cert', 'holdout_v2', 'kb_stage', 'ops_kb_stage')
   and d.objid is null
   and not exists (select 1 from unnest(coalesce(p.proconfig, '{}')) c where c like 'search_path=%');
