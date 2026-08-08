-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260726145252   name: knowledge_exam_helpers
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- Pick the real agent (has knowledge, excluding the company-wide _global bucket) that has gone
-- longest without an exam. Returns the runtime agent_key (e.g. 'cat:scaffolding' or 'legal').
create or replace function public.fn_exam_pick_agent()
returns text language sql stable security definer set search_path to 'public','pg_catalog' as $$
  select k.agent_key
  from (select distinct agent_key from agent_knowledge where agent_key <> '_global') k
  left join (select agent_key, max(created_at) last_exam from knowledge_exam_results group by agent_key) e
    on e.agent_key = k.agent_key
  order by e.last_exam asc nulls first, k.agent_key
  limit 1;
$$;

create or replace function public.fn_bump_exam_question(p_id bigint)
returns void language sql security definer set search_path to 'public','pg_catalog' as $$
  update knowledge_exam_questions set times_asked = coalesce(times_asked,0)+1, last_asked = now() where id = p_id;
$$;

revoke execute on function public.fn_exam_pick_agent() from anon, authenticated, public;
revoke execute on function public.fn_bump_exam_question(bigint) from anon, authenticated, public;
