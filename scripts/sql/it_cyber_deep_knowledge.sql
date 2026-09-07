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
create or replace function public.fn_it_security_knowledge_upsert(
  p_rid text, p_dept text, p_module text, p_rtype text, p_subdomain text,
  p_title text, p_content text, p_kw text[], p_risk text, p_source text)
 returns void language sql security definer set search_path to 'public','pg_temp'
as $fn$
  insert into public.ops_knowledge
    (record_id, scope_type, scope_key, dept_key, module, layer, record_type, title, content,
     structured_data, source_ids, implementation_status, validation_status, authority_tier, risk_level,
     version, keywords, runtime_eligible, supersession_state, embedding_status)
  values
    (p_rid, 'department', 'it_security', p_dept, coalesce(p_module,'security'), 'it_security_deep',
     coalesce(p_rtype,'knowledge_domain'), p_title,
     p_content || case when coalesce(array_length(p_kw,1),0) > 0
                       then E'\n\nkeywords: ' || array_to_string(p_kw,', ') else '' end,
     jsonb_build_object('subdomain', p_subdomain, 'source_note', p_source),
     array[coalesce(p_source,'step3_it_cyber')]::text[],
     'active', 'author_verified', 'advisory', coalesce(p_risk,'medium'),
     '1.0', coalesce(p_kw,'{}'::text[]), true, 'current', 'pending')
  on conflict (record_id) do update set
     dept_key = excluded.dept_key, module = excluded.module, record_type = excluded.record_type,
     title = excluded.title, content = excluded.content, structured_data = excluded.structured_data,
     keywords = excluded.keywords, risk_level = excluded.risk_level,
     supersession_state = 'current', runtime_eligible = true, embedding_status = 'pending';
$fn$;
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
create or replace function public.fn_it_security_live_posture()
 returns jsonb language plpgsql security definer set search_path to 'public','pg_temp'
as $fn$
declare
  v_total int; v_rls int; v_definer int; v_crons int; v_anon int; v_content text;
begin
  select count(*) into v_total   from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relkind='r';
  select count(*) into v_rls     from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relkind='r' and c.relrowsecurity;
  select count(*) into v_definer from pg_proc  p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.prosecdef;
  select count(*) into v_crons   from cron.job where active;
  select count(distinct table_name) into v_anon from information_schema.role_table_grants where table_schema='public' and grantee='anon';
  v_content :=
    -- the project ref is read, never written down: an export that names its own project can never be
    -- byte-identical from either source (scripts/checks/export_from_either_source_is_identical.mjs)
    'LIVE SECURITY POSTURE of the QuotesDone Supabase project (' || coalesce((select value from public.app_secrets where key = 'project_ref'), 'project_ref unset') || '), recomputed every run — nothing static. As of '
      || to_char(now(),'YYYY-MM-DD HH24:MI') || ' UTC:' || E'\n'
    || '- public tables: ' || v_total || '; RLS enabled: ' || v_rls || '; WITHOUT RLS: ' || (v_total - v_rls)
      || ' (a table reachable through PostgREST without RLS is an access-control gap to justify or close).' || E'\n'
    || '- SECURITY DEFINER functions in public: ' || v_definer
      || ' (each runs as its owner and is a privilege boundary; confirm search_path is pinned on every one).' || E'\n'
    || '- active cron jobs: ' || v_crons
      || ' (hold this against the known baseline; a new or off-cadence job is a detection signal worth chasing).' || E'\n'
    || '- public tables granted to anon (unauthenticated): ' || v_anon
      || ' (every anon grant must be intended and RLS-guarded).' || E'\n'
    || 'External threat intelligence is NOT derivable here — refresh it via npm audit, Supabase get_advisors, and CVE feeds for Postgres/Deno/Next.js.';
  perform public.fn_it_security_knowledge_upsert(
    'it_sec_live_posture','assurance','security','live_data_binding','live-posture',
    'Live security posture (auto-refreshed): RLS coverage, definer surface, cron baseline, anon grants',
    v_content,
    array['security posture','rls coverage','security definer surface','cron baseline','anon grants','attack surface','live','always current'],
    'high','fn_it_security_live_posture');
  -- The security watch rides this existing hourly cron rather than adding a new one, so the active-cron
  -- count stays under the Phase D automation-hold ceiling (GATE-032) until that hold is formally lifted.
  perform public.fn_secops_watch();
  return jsonb_build_object('tables',v_total,'rls',v_rls,'no_rls',v_total-v_rls,'definer',v_definer,'active_crons',v_crons,'anon_tables',v_anon);
end $fn$;
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
