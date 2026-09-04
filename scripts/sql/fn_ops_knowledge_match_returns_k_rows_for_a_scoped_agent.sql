-- fn_ops_knowledge_match RETURNS k ROWS FOR A SCOPED AGENT, AND CAN BE ASKED FOR PLAYBOOK KINDS (4 Sep 2026).
--
-- Measured on production with scripts/kb/probe_ops_knowledge_match.mjs: for inquiry_router (marketplace
-- scope, 839 of 9,046 eligible rows) the need "RFQ found no matching suppliers" returned ONE row at
-- k=8; cs_support (customer_experience scope) returned 8. Cause: the HNSW scan hands back
-- hnsw.ef_search (default 40) nearest candidates BEFORE the scope predicate is applied, the predicate
-- then discards the ~95% that belong to other departments, and the function returns whatever
-- survives — so the tighter an agent's scope, the fewer rows it gets, down to one. A cosine retriever
-- that returns one row where eight were asked is the applier's "no confident match" for reasons that
-- have nothing to do with meaning.
--
-- pgvector 0.8.0 (live) has iterative index scans for exactly this: with hnsw.iterative_scan =
-- relaxed_order the scan keeps walking the graph until the LIMIT is satisfied after filtering.
-- Set at function level so every caller (agent_brain, fn_apply_playbook, the probe) gets it without
-- knowing. ef_search is raised too so the common case needs no second pass.
--
-- Second change: an optional p_record_types filter. The §4.2 applier wants the nearest decision
-- playbook / rule / exception playbook, not the nearest failure_mode_case; measured for qa_manager
-- "a test failed in CI": eight failure_mode_case rows, no playbook within k=8, while the playbooks
-- were there at rank > 8. NULL keeps today's behaviour for agent_brain. The old 3-argument signature
-- is dropped so a named-parameter rpc call resolves to exactly one function.
--
--   node scripts/apply_sql.mjs scripts/sql/fn_ops_knowledge_match_returns_k_rows_for_a_scoped_agent.sql --apply --ddl

begin;

-- Load pgvector's shared library into THIS backend before the CREATE below is validated: the SET
-- clauses name hnsw.* GUCs, which exist only once vector.so has run its init. A backend that has not
-- yet touched a vector value treats them as unknown placeholders and, for a non-superuser, refuses
-- with "permission denied to set parameter" (measured on the first apply of this file).
select '[0]'::vector;

drop function if exists public.fn_ops_knowledge_match(vector, text, integer);

create or replace function public.fn_ops_knowledge_match(
  p_query_embedding vector(384),
  p_agent_key       text,
  p_match_count     integer default 8,
  p_record_types    text[]  default null
)
returns table(record_id text, title text, content text, layer text, record_type text,
              authority_tier text, dept_key text, role_key text, similarity real)
language plpgsql stable security definer
set search_path to 'public', 'pg_temp'
set hnsw.iterative_scan to 'relaxed_order'
set hnsw.ef_search to '200'
as $function$
declare
  v_key      text;
  v_dept     text;
  v_scope    text[];
  v_role_ids text[];
begin
  if p_query_embedding is null then return; end if;
  -- resolve exactly as v3 does, so an alias or packaged role resolves to the same identity
  v_key := coalesce(public.fn_org_agent_resolve(p_agent_key), p_agent_key);
  select a.department into v_dept from public.org_agents a where a.agent_key = v_key;
  if v_dept is null then return; end if;
  v_scope := public.fn_dept_scope(v_dept);
  select array_agg(packaged_role_id) into v_role_ids
    from public.org_role_identity where agent_key = v_key;

  return query
    select o.record_id, o.title, o.content, o.layer, o.record_type, o.authority_tier,
           o.dept_key, o.role_key,
           (1 - (o.embedding_gte <=> p_query_embedding))::real as similarity
      from public.ops_knowledge o
     where o.embedding_gte is not null
       and o.runtime_eligible
       and o.supersession_state = 'current'
       and (p_record_types is null or o.record_type = any(p_record_types))
       and (
             o.scope_type in ('company','external_source')
          or (o.scope_type = 'department' and o.dept_key = any(v_scope))
          or (o.role_key = any(coalesce(v_role_ids, '{}')))
       )
     order by o.embedding_gte <=> p_query_embedding
     limit greatest(1, least(coalesce(p_match_count, 8), 20));
end
$function$;

-- A fresh signature is a fresh CREATE: EXECUTE goes to PUBLIC, so revoke it as the original did.
revoke execute on function public.fn_ops_knowledge_match(vector, text, integer, text[]) from public;

commit;
