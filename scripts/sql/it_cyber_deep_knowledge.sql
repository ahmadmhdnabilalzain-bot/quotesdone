-- STEP 3 — IT / CYBERSECURITY DEEP KNOWLEDGE (the extra depth only these agents carry).
--
-- Company knowledge is universal (the 20-year veteran layer). The app's code and its security are the
-- ONE extra layer, and only for the engineering + assurance agents (product_eng, assurance). This file
-- builds the delivery for that layer:
--   * fn_it_security_knowledge_upsert  — ingest one deep record (layer = it_security_deep, dept-scoped).
--   * fn_it_security_slice             — retrieval, GATED to product_eng/assurance, folded into v3.
--   * fn_it_security_live_posture      — the derivable security posture, recomputed every run (nothing
--                                        static): RLS coverage, definer surface, cron baseline, anon grants.
-- The v3 fold and the fn_company_knowledge_search exclusion (keep this layer OUT of universal recall,
-- so it stays scoped to IT/cyber) are spliced in a second step once these exist.
--
--   node scripts/apply_sql.mjs scripts/sql/it_cyber_deep_knowledge.sql --apply --ddl

begin;

-- 0. Allow the scoping layer. Additive only — every existing value is preserved, 'it_security_deep'
--    is added so this layer can be filtered in retrieval and excluded from universal recall.
alter table public.ops_knowledge drop constraint if exists ops_knowledge_layer_ck;
alter table public.ops_knowledge add constraint ops_knowledge_layer_ck
  check (layer is null or layer = any(array[
    'company_core','department_shared','role_specific','task_specific','category_specialist',
    'validated_experience','policy','authority','kpi','decision_playbook','case_training',
    'failure_mode','remediation','source_reference','it_security_deep']));

-- 1. INGEST one deep record. Keywords are folded into content so tsv retrieval matches them.
-- ROUTINE REMOVED 7 September 2026. public.fn_it_security_knowledge_upsert was dropped from the database with
-- everything else that did not belong to the new structure, and its definition is cut from
-- this file so re-applying the file cannot recreate it. The other routines defined here are
-- still running and are untouched.

revoke execute on function public.fn_it_security_knowledge_upsert(text,text,text,text,text,text,text,text[],text,text) from public;
grant execute on function public.fn_it_security_knowledge_upsert(text,text,text,text,text,text,text,text[],text,text) to service_role;

-- 2. RETRIEVAL slice — only product_eng and assurance agents receive this layer in context.
create or replace function public.fn_it_security_slice(p_dept text, p_q tsquery, p_budget integer)
 returns jsonb language sql stable security definer set search_path to 'public','pg_temp'
as $fn$
  select case
    when p_dept in ('product_eng','assurance') and p_q is not null then
      coalesce((
        select jsonb_agg(jsonb_build_object(
                 'title', title,
                 'area', coalesce(structured_data->>'subdomain', module),
                 'content', left(content, 1600)) order by rank desc)
        from (
          select k.title, k.module, k.structured_data, k.content, ts_rank(k.tsv, p_q) rank
            from public.ops_knowledge k
           where k.runtime_eligible and k.supersession_state = 'current'
             and k.layer = 'it_security_deep' and k.tsv @@ p_q
           order by ts_rank(k.tsv, p_q) desc, coalesce(k.effective_date,'1900-01-01') desc
           limit greatest(least(coalesce(p_budget,4800) / 1600, 8), 3)
        ) x), '[]'::jsonb)
    else '[]'::jsonb end;
$fn$;
revoke execute on function public.fn_it_security_slice(text, tsquery, integer) from public;
grant execute on function public.fn_it_security_slice(text, tsquery, integer) to service_role;

-- 3. LIVE POSTURE — recomputed every run so the security picture is never stale. The numbers are what
--    SQL can derive; the external threat picture (CVEs, npm/Supabase advisories) is refreshed separately.
-- ROUTINE REMOVED 7 September 2026. public.fn_it_security_live_posture was dropped from the database with
-- everything else that did not belong to the new structure, and its definition is cut from
-- this file so re-applying the file cannot recreate it. The other routines defined here are
-- still running and are untouched.

revoke execute on function public.fn_it_security_live_posture() from public;
grant execute on function public.fn_it_security_live_posture() to service_role;

-- 4. Keep it current — refresh the live posture hourly. It reaches no watched relation (verified against
--    fn_phase_d_committed_scenario_guards), so it needs no committed-scenario registration.
-- CRON SCHEDULE REMOVED 7 September 2026 on the founder's instruction: "there shouldn't be
-- any job in the code except the stuff that I literally told you for the CEO... Remove it from
-- the code. Delete, not archive." The job it created was deleted from the database in the same
-- change. Do not restore this without his word: an estate reaches 235 scheduled jobs precisely
-- by each build adding one and nothing ever removing one.

commit;
