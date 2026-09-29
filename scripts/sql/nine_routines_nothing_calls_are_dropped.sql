-- NINE ROUTINES NOTHING CALLS ARE DROPPED.
-- Seat: it_engineer. 28 Sep 2026. Deep audit 28 Sep, code-structure finding 3.
--
-- HOW EACH WAS PROVED DEAD (production htdblwldjkcgjvmqkbeh, read-only, 28 Sep 2026), per
-- a-mention-is-not-a-reference: a name written in a register, a seed of agent_knowledge prose or an old
-- migration is not a caller. For every routine below, all of these were zero:
--   * callers   - another public routine whose body names it (pg_proc.prosrc, word-bounded), and no
--                 routine that builds it by format();
--   * triggers  - pg_trigger rows executing it (the two trigger functions below have none);
--   * cron      - cron.job commands naming it;
--   * views     - pg_views definitions naming it; pg_depend normal dependents; RLS policies;
--   * dispatch  - seat_duty.routine, seat_handoff_kind.handler, agent_tool.impl_target,
--                 it_playbook.remedy_routine, org_action_executor.target, fn_task_class, llm_seat_binding;
--   * code      - supabase/functions, src, scripts (every file except SQL definitions/migrations) and
--                 .github: no call. fn_exam_revert is named only in scripts/checks/retired/*.RETIRED.mjs.
--
-- The deep audit listed 16 as "confirmed dead" on a database-only scan. Tracing the code and the dispatch tables kept eight of them:
-- fn_accountant_ad_spend_reconcile (a seat_duty routine), fn_accountant_keeps_reported_ad_spend (a
-- seat_handoff_kind handler), fn_glm_sender_known (email_triage), fn_wa_sms_twin (send_whatsapp),
-- fn_it_refusal_is_policy, fn_ops_knowledge_match, fn_recommend_deterministic, kb_match (each still named by
-- another routine; not traced further, so kept). Eight were dropped from that list; fn_exam_revert comes
-- from the audit's 47-name sample. Every other sampled name is called by an edge function or the app by RPC.
--
-- Owners, for the record: fn_company_map and fn_founder_habits were the ceo's; qd_notify_refund_request
-- customer_support's; the rest it_engineer's. None is reached by any seat today.
-- Each drop is recorded in routine_change_log by the qd_record_routine_drop event trigger, and in
-- scripts/sql/DROPPED.txt. Older files that define these routines are history: applying one would
-- resurrect a routine with no caller, which canonical_routine_manifest reports against DROPPED.txt.

drop function if exists public.fn_company_map(integer);
drop function if exists public.fn_founder_habits();
drop function if exists public.fn_name_norm(text);
drop function if exists public.fn_service_implications(text[]);
drop function if exists public.fn_ws_intelligence();
drop function if exists public.kb_norm(text);
drop function if exists public.qd_norm_customer_ver();
drop function if exists public.qd_notify_refund_request();
drop function if exists public.fn_exam_revert(text);

select case when not exists (
         select 1 from pg_proc p
          where p.pronamespace = 'public'::regnamespace
            and p.proname in ('fn_company_map','fn_founder_habits','fn_name_norm','fn_service_implications',
                              'fn_ws_intelligence','kb_norm','qd_norm_customer_ver','qd_notify_refund_request',
                              'fn_exam_revert'))
       then 'PROBE OK' else 'PROBE FAILED: a dropped routine is still present' end as verdict;
