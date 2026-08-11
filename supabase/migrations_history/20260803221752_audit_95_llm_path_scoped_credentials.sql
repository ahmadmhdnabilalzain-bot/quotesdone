-- AUDIT 9.5 / WI-001. The shared secret's largest consumer was never in the D3/D5 hop inventory.
--
-- supabase/functions/_shared/llm.ts - imported by 32 edge functions - authenticates EVERY call to
-- ai_gateway with sec('inbound_secret'). D3 and D5 built their hop inventory by reading each
-- function's own fetch() calls; this hop lives inside a shared module, so it was invisible, and not
-- one of the 32 calling contexts received a credential scoped to ai_gateway. Eight unrelated
-- contexts happen to list ai_gateway in scope and seven of those have never been presented once.
--
-- Measured, not inferred: internal_credential.use_count for legacy.shared stood at 379 and was
-- still rising at 20:23:07 UTC on 3 Aug with last_function 'ai_gateway'. That means
-- v_internal_secret_migration_progress.safe_to_withdraw_shared_secret can never turn true - its
-- 7-day silence clock is reset by every model call the platform makes - and a withdrawal on the
-- pencilled 10 Aug date would have returned 403 to ai_gateway, which makeLlm converts to `null`,
-- which all 32 callers treat as "the model declined". Silent, total, and invisible to every monitor.
--
-- THIS MIGRATION CHANGES NO BEHAVIOUR BY ITSELF. It only makes the credentials exist. llm.ts must
-- be redeployed to present them, and it keeps the legacy fallback until v_legacy_secret_users has
-- stayed empty for a full 7-day window.
--
-- Widening an existing context rather than minting a second credential for it is deliberate. Two
-- credentials for one function makes "which should this caller present" ambiguous, and ambiguity is
-- how the llm.ts hop went unnoticed. Scope grows by exactly one entry, ai_gateway, and only for
-- functions that provably import _shared/llm.ts.
do $$
declare
  callers text[] := array[
    -- action_worker added 10 Aug 2026. CI refused the merge without it — "these functions import
    -- _shared/llm.ts but are not in the credential migration, so each one falls back to the shared
    -- inbound_secret on every model call" — and it was right: the credential had been issued at
    -- runtime, so a REBUILT database would have put the worker back on the shared secret. This
    -- block widens-or-issues per caller and is re-runnable, so naming it here is a no-op against
    -- the credential that already exists.
    'action_worker',
    'agent_act','agent_brain','agents','analytics_recommend','archive_rfq','blog_weekly',
    'boost_recommend','canon_eval','category_provision','category_reqs','content_revise','copilot',
    'cos_execute','dept_learn','dept_plan','doc_render','ea_meeting_summary','email_triage',
    'enrich_capability','exec_agents','gen_category_knowledge','gen_category_personas',
    'intent_router','kb_deepen','kb_research_test','knowledge_exam','learn_gaps','marketing_draft',
    'messages_api','project_consultant','prompt_gate','reflect',
    -- workflow_dispatch added 11 Aug 2026, the employee side of the workflow engine. Named here for
    -- the same reason action_worker was: the credential is issued at runtime by
    -- scripts/sql/wiring_for_the_employee_side_of_the_engine.sql, and a rebuilt database that never
    -- replayed that file would put every step deliberation back on the shared secret.
    'workflow_dispatch'];
  c text; v jsonb; v_id bigint; v_has_secret boolean;
  n_widened int := 0; n_issued int := 0; n_rotated int := 0; n_noop int := 0; n_missing int;
begin
  foreach c in array callers loop
    select id into v_id from public.internal_credential where context = 'fn.' || c and active;
    select exists(select 1 from public.app_secrets where key = 'cred_fn_' || c) into v_has_secret;

    if v_id is not null and v_has_secret then
      if exists (select 1 from public.internal_credential
                  where id = v_id and not (scope @> array['ai_gateway'])) then
        update public.internal_credential
           set scope = array(select distinct s from unnest(scope || array['ai_gateway']) s order by s)
         where id = v_id;
        n_widened := n_widened + 1;
      else
        n_noop := n_noop + 1;
      end if;

    elsif v_id is not null and not v_has_secret then
      -- A credential nobody can present is not a credential. The secret is unrecoverable by design,
      -- so the only honest repair is a rotation that hands us a fresh one to store.
      update public.internal_credential
         set scope = array(select distinct s from unnest(scope || array['ai_gateway']) s order by s)
       where id = v_id;
      v := public.fn_internal_credential_rotate('fn.' || c,
             'rotated 4 Aug 2026: the credential existed but its secret was not stored, so it could never be presented');
      insert into public.app_secrets (key, value) values ('cred_fn_' || c, v->>'secret')
      on conflict (key) do update set value = excluded.value;
      n_rotated := n_rotated + 1;

    else
      v := public.fn_internal_credential_issue('fn.' || c, array['ai_gateway'],
             '_shared/llm.ts -> ai_gateway. Issued 4 Aug 2026 from the shared-module hop the D3/D5 caller inventory could not see.');
      insert into public.app_secrets (key, value) values ('cred_fn_' || c, v->>'secret')
      on conflict (key) do update set value = excluded.value;
      n_issued := n_issued + 1;
    end if;
  end loop;

  raise notice 'llm.ts contexts: % widened, % issued, % rotated, % already correct',
    n_widened, n_issued, n_rotated, n_noop;

  -- Assert the INVARIANT, not the change: every function that imports _shared/llm.ts can present a
  -- credential that ai_gateway will accept. "I updated 30 rows" is not the property that matters.
  select count(*) into n_missing
    from unnest(callers) as t(fnname)
   where not exists (
     select 1 from public.internal_credential ic
      join public.app_secrets s on s.key = 'cred_fn_' || t.fnname
     where ic.context = 'fn.' || t.fnname and ic.active and ic.scope @> array['ai_gateway']
       and coalesce(btrim(s.value), '') <> '');

  if n_missing > 0 then
    raise exception '% of % _shared/llm.ts callers still have no presentable ai_gateway credential',
      n_missing, array_length(callers, 1);
  end if;
end $$;;
