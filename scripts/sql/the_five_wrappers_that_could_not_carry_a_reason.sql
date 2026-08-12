-- The five wrappers that could not carry a reason — 12 Aug 2026
--
-- Follows a_recommendation_that_cannot_say_what_it_assumed.sql, which added assumptions,
-- expected_impact and cost to agent_actions and filled them at the thirteen call sites in
-- supabase/functions/agents/index.ts.
--
-- The SQL side writes through five near-identical wrappers — ai_rec, ops_rec, mkt_rec, kn_task,
-- doc_rec — each taking (signal, condition, risk, title, recommendation) and inserting one row.
-- Twenty-five call sites across six routines go through them, and NONE of them could pass a reason
-- even if it had one: the wrapper had nowhere to put it.
--
-- Widened with three OPTIONAL parameters. Every existing call keeps working untouched and simply
-- writes NULL, which reads as "this rule did not say what it assumed" — true. Callers are updated
-- separately, rule by rule, so a routine is only claimed to explain itself once it actually does.
--
-- WHY DROP AND RECREATE RATHER THAN CREATE OR REPLACE: adding defaulted parameters produces a
-- SECOND function rather than replacing the first, and then every existing five-argument call is
-- ambiguous between them and fails at runtime. Dropping the old signature first is what makes the
-- defaults resolve. PL/pgSQL binds function calls at runtime, so the callers need no edit to
-- continue working.
--
-- The wrappers are SECURITY DEFINER and are being CREATEd fresh here rather than replaced, so the
-- implicit grant to PUBLIC applies and is revoked at the bottom. That revoke lands on staging only
-- when this file is promoted — it is re-run directly against production in the same change.

drop function if exists public.ai_rec(text, boolean, text, text, text);
drop function if exists public.ops_rec(text, boolean, text, text, text);
drop function if exists public.mkt_rec(text, boolean, text, text, text);
drop function if exists public.kn_task(text, boolean, text, text, text);
drop function if exists public.doc_rec(text, boolean, text, text, text);

create function public.ai_rec(p_sig text, p_cond boolean, p_risk text, p_title text, p_reco text,
                              p_assumptions jsonb default null, p_impact text default null, p_cost text default null)
returns void language plpgsql security definer set search_path to 'public', 'pg_temp'
as $function$
begin
  if p_cond and not exists (select 1 from agent_actions where kind='ai_improvement' and detail->>'signal'=p_sig and status in ('pending','needs_review')) then
    insert into agent_actions(agent,kind,status,risk,title,recommendation,detail,target_table,target_id,assumptions,expected_impact,cost)
    values ('ai_trainer','ai_improvement','pending',p_risk,p_title,p_reco,jsonb_build_object('signal',p_sig),'ai',p_sig,p_assumptions,p_impact,p_cost);
  end if;
end $function$;

create function public.ops_rec(p_sig text, p_cond boolean, p_risk text, p_title text, p_reco text,
                               p_assumptions jsonb default null, p_impact text default null, p_cost text default null)
returns void language plpgsql security definer set search_path to 'public', 'pg_temp'
as $function$
begin
  if p_cond and not exists (select 1 from agent_actions where kind='ops_recommendation' and detail->>'signal'=p_sig and status in ('pending','needs_review')) then
    insert into agent_actions(agent,kind,status,risk,title,recommendation,detail,target_table,target_id,assumptions,expected_impact,cost)
    values ('operations_ai','ops_recommendation','pending',p_risk,p_title,p_reco,jsonb_build_object('signal',p_sig),'operations',p_sig,p_assumptions,p_impact,p_cost);
  end if;
end $function$;

create function public.mkt_rec(p_sig text, p_cond boolean, p_risk text, p_title text, p_reco text,
                               p_assumptions jsonb default null, p_impact text default null, p_cost text default null)
returns void language plpgsql security definer set search_path to 'public', 'pg_temp'
as $function$
begin
  if p_cond and not exists (select 1 from agent_actions where kind='marketing_recommendation' and detail->>'signal'=p_sig and status in ('pending','needs_review')) then
    insert into agent_actions(agent,kind,status,risk,title,recommendation,detail,target_table,target_id,assumptions,expected_impact,cost)
    values ('marketing_ai','marketing_recommendation','pending',p_risk,p_title,p_reco,jsonb_build_object('signal',p_sig),'marketing',p_sig,p_assumptions,p_impact,p_cost);
  end if;
end $function$;

-- kn_task keeps its auto-resolve branch: when the condition stops holding, the open task is closed
-- rather than left standing. That half is unchanged and deliberately not given a reason to carry —
-- a resolution is not a recommendation.
create function public.kn_task(p_sig text, p_cond boolean, p_risk text, p_title text, p_reco text,
                               p_assumptions jsonb default null, p_impact text default null, p_cost text default null)
returns void language plpgsql security definer set search_path to 'public', 'pg_temp'
as $function$
begin
  if p_cond then
    if not exists (select 1 from agent_actions where kind='knowledge_task' and detail->>'signal'=p_sig and status in ('pending','needs_review')) then
      insert into agent_actions(agent,kind,status,risk,title,recommendation,detail,target_table,target_id,assumptions,expected_impact,cost)
      values ('knowledge_curator','knowledge_task','pending',p_risk,p_title,p_reco,jsonb_build_object('signal',p_sig),'knowledge',p_sig,p_assumptions,p_impact,p_cost);
    end if;
  else
    update agent_actions
       set status='resolved', decided_at=now(), decided_by='knowledge_curator (auto-resolved)'
     where kind='knowledge_task' and detail->>'signal'=p_sig and status in ('pending','needs_review');
  end if;
end $function$;

create function public.doc_rec(p_sig text, p_cond boolean, p_risk text, p_title text, p_reco text,
                               p_assumptions jsonb default null, p_impact text default null, p_cost text default null)
returns void language plpgsql security definer set search_path to 'public', 'pg_temp'
as $function$
begin
  if p_cond and not exists (select 1 from agent_actions where kind='doc_task' and detail->>'signal'=p_sig and status in ('pending','needs_review')) then
    insert into agent_actions(agent,kind,status,risk,title,recommendation,detail,target_table,target_id,assumptions,expected_impact,cost)
    values ('document_controller','doc_task','pending',p_risk,p_title,p_reco,jsonb_build_object('signal',p_sig),'documents',p_sig,p_assumptions,p_impact,p_cost);
  end if;
end $function$;

revoke all on function public.ai_rec(text, boolean, text, text, text, jsonb, text, text)  from public, anon, authenticated;
revoke all on function public.ops_rec(text, boolean, text, text, text, jsonb, text, text) from public, anon, authenticated;
revoke all on function public.mkt_rec(text, boolean, text, text, text, jsonb, text, text) from public, anon, authenticated;
revoke all on function public.kn_task(text, boolean, text, text, text, jsonb, text, text) from public, anon, authenticated;
revoke all on function public.doc_rec(text, boolean, text, text, text, jsonb, text, text) from public, anon, authenticated;
