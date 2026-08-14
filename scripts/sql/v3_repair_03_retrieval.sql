-- V3 REMEDIATION — STAGE 4: KNOWLEDGE RETRIEVAL
-- Result of record V3-COR-0A782DA90B10: KNOWLEDGE_NOT_RETRIEVED on 1,706 questions, while
-- retrieval traces were non-empty on every single row and averaged 46 records per execution.
-- The corpus is loaded (8,256 ops_knowledge rows, 95,912 kb_chunks) and records ARE being fetched.
-- They were not reaching the answer, and this file is why.
--
-- THE DEFECT, verified live on staging before writing this (pg_get_functiondef, 14 Aug 2026):
--
--     and (p_q is null or tsv @@ p_q or true)
--                                     ^^^^^^^
-- The trailing `or true` makes the whole predicate a tautology. The task's own search query has
-- NEVER filtered anything in fn_context_slice — it only ordered. Every agent received the
-- highest-ranked rows of its layer whether or not a single one related to its task, and the budget
-- window then cut the list at 1,800 chars per record. That is how you retrieve 46 records per call
-- and still answer from memory: the records were real, they were about something else.
--
-- WHY DELETING `or true` IS NOT THE FIX ON ITS OWN. With a strict filter a non-matching query
-- returns an empty slice, and the agent is handed no departmental knowledge at all. Silence is what
-- produced the failure in the first place. The fix has to make the MISS VISIBLE:
--
--   1. matched rows first, ranked, filtered for real;
--   2. if fewer than the floor match, fall back to the layer's highest-authority rows AND LABEL
--      THEM `match: "fallback"` so the caller can see that topical retrieval found nothing;
--   3. emit a knowledge-gap signal the runtime can escalate on.
--
-- An agent that is told "no knowledge matched your task, these are general department rules"
-- can say so. An agent silently handed the same rows cannot.

begin;

-- ---------------------------------------------------------------------------------------------
-- 1. THE SLICE — real filtering, labelled fallback, duplicate suppression, freshness carried
-- ---------------------------------------------------------------------------------------------
create or replace function public.fn_context_slice(
  p_dept text, p_role_ids text[], p_category text, p_layer text, p_q tsquery, p_budget integer)
returns jsonb
language sql stable security definer set search_path = 'public' as $function$
  with scoped as (
    select record_id, title, content, version, source_freshness, effective_date, review_after,
           layer, record_type, authority_tier, tsv
      from ops_knowledge
     where runtime_eligible
       and supersession_state = 'current'
       and layer = p_layer
       and (
         (p_layer = 'company_core'        and scope_type = 'company')
      -- THE MERGE ARM. A department that absorbed another owns its predecessor's knowledge; the
      -- 5,775 rows tagged with the 22 absorbed keys are not rewritten, they are scoped in.
      or (p_layer = 'department_shared'   and dept_key = any(public.fn_dept_scope(p_dept)))
      or (p_layer = 'role_specific'       and role_key = any(coalesce(p_role_ids, '{}')))
      or (p_layer = 'category_specialist' and category_key = p_category)
       )
  ), matched as (
    -- THE FILTER THAT WAS DEAD. No `or true`: when a query is supplied it now decides membership.
    select *, ts_rank(tsv, p_q) as rank, 'query'::text as match
      from scoped
     where p_q is not null and tsv @@ p_q
  ), fallback as (
    -- Only consulted when topical retrieval under-delivers. Highest authority first, and every row
    -- carries match='fallback' so the caller can tell the difference.
    select *, 0::real as rank, 'fallback'::text as match
      from scoped
     where p_q is null or (select count(*) from matched) < 3
  ), unioned as (
    select * from matched
    union all
    select * from fallback f where not exists (select 1 from matched m where m.record_id = f.record_id)
  ), deduped as (
    -- Duplicate suppression: the same record can be reachable by more than one scope arm, and the
    -- same TITLE often repeats across package generations. Keep the freshest of each title.
    select distinct on (coalesce(nullif(title,''), record_id))
           record_id, title, content, version, source_freshness, effective_date, review_after,
           layer, record_type, authority_tier, rank, match
      from unioned
     order by coalesce(nullif(title,''), record_id),
              (match = 'query') desc, rank desc,
              coalesce(effective_date, '1900-01-01'::date) desc, record_id
  ), ranked as (
    select *,
           -- freshness is carried, not judged here: review_after in the past is stale and the
           -- caller must be able to see that rather than infer it.
           (review_after is not null and review_after < current_date) as stale,
           sum(least(length(content), 1800)) over (
             order by (match = 'query') desc, rank desc, record_id
             rows between unbounded preceding and current row) as running
      from deduped
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'record_id', record_id, 'title', title, 'layer', layer, 'record_type', record_type,
           'version', version, 'source_freshness', source_freshness,
           'review_after', review_after, 'stale', stale,
           'authority_tier', authority_tier, 'match', match,
           'content', left(content, 1800))
         order by (match = 'query') desc, rank desc, record_id), '[]'::jsonb)
    from ranked
   where running <= greatest(p_budget, 1800);
$function$;

-- ---------------------------------------------------------------------------------------------
-- 2. GAP DETECTION — the signal the runtime escalates on
-- ---------------------------------------------------------------------------------------------
-- Returns, per layer, whether the task's own query actually matched anything. A layer that is
-- entirely 'fallback' means: this agent has NO knowledge about what it was asked to do.
create or replace function public.fn_knowledge_gap(p_ctx jsonb)
returns jsonb
language sql immutable set search_path = public as $$
  with layers as (
    select k as layer, p_ctx->k as rows
      from unnest(array['company_core','department_knowledge','role_knowledge','category_knowledge']) k
     where jsonb_typeof(p_ctx->k) = 'array'
  ), per as (
    select l.layer,
           jsonb_array_length(l.rows)                                                          as n,
           (select count(*) from jsonb_array_elements(l.rows) e where e->>'match' = 'query')    as matched,
           (select count(*) from jsonb_array_elements(l.rows) e where (e->>'stale')::boolean)   as stale
      from layers l
  )
  select jsonb_build_object(
    'layers', coalesce(jsonb_object_agg(layer, jsonb_build_object('records', n, 'matched_query', matched, 'stale', stale)), '{}'::jsonb),
    'total_records',  coalesce(sum(n),0),
    'total_matched',  coalesce(sum(matched),0),
    'total_stale',    coalesce(sum(stale),0),
    -- The one boolean the runtime acts on.
    'has_gap',        coalesce(sum(matched),0) = 0,
    'gap_layers',     coalesce((select jsonb_agg(layer order by layer) from per where n > 0 and matched = 0), '[]'::jsonb),
    'instruction',    case when coalesce(sum(matched),0) = 0
                        then 'NO retrieved knowledge matched this task. You are working from general departmental material only. Say so explicitly, and request, research or escalate rather than answering as if you had specific guidance.'
                        else null end)
  from per;
$$;
revoke all on function public.fn_knowledge_gap(jsonb) from public;
grant execute on function public.fn_knowledge_gap(jsonb) to service_role;

-- ---------------------------------------------------------------------------------------------
-- 3. COVERAGE PROBE — used by the regression suite to assert retrieval per role/category
-- ---------------------------------------------------------------------------------------------
create or replace function public.fn_retrieval_probe(
  p_agent_key text, p_task_text text, p_category_key text default null)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_ctx jsonb; v_gap jsonb;
begin
  v_ctx := public.fn_agent_context_v3(p_agent_key, null, p_task_text, p_category_key, 24000);
  v_gap := public.fn_knowledge_gap(v_ctx);
  return jsonb_build_object(
    'agent_key',        p_agent_key,
    'role_ids',         v_ctx->'identity'->'packaged_role_ids',
    'knowledge_count',  v_ctx->'knowledge_count',
    'role_records',     coalesce(jsonb_array_length(v_ctx->'role_knowledge'),0),
    'dept_records',     coalesce(jsonb_array_length(v_ctx->'department_knowledge'),0),
    'category_records', coalesce(jsonb_array_length(v_ctx->'category_knowledge'),0),
    'rules_records',    coalesce(jsonb_array_length(v_ctx->'deterministic_rules'),0),
    'gap',              v_gap);
end $$;
revoke all on function public.fn_retrieval_probe(text,text,text) from public;
grant execute on function public.fn_retrieval_probe(text,text,text) to service_role;

-- ---------------------------------------------------------------------------------------------
-- 4. CROSS-ROLE LEAKAGE CHECK — role_specific knowledge must not reach a role that does not own it
-- ---------------------------------------------------------------------------------------------
create or replace function public.fn_retrieval_leak_check(p_agent_key text, p_task_text text)
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_ctx jsonb; v_mine text[]; v_leak int;
begin
  select coalesce(array_agg(packaged_role_id),'{}') into v_mine
    from org_role_identity where agent_key = p_agent_key;
  v_ctx := public.fn_agent_context_v3(p_agent_key, null, p_task_text, null, 24000);
  select count(*) into v_leak
    from jsonb_array_elements(coalesce(v_ctx->'role_knowledge','[]'::jsonb)) e
    join ops_knowledge k on k.record_id = e->>'record_id'
   where k.role_key is not null and not (k.role_key = any(v_mine));
  return jsonb_build_object('agent_key', p_agent_key, 'own_roles', to_jsonb(v_mine),
                            'foreign_role_records', v_leak,
                            'clean', v_leak = 0);
end $$;
revoke all on function public.fn_retrieval_leak_check(text,text) from public;
grant execute on function public.fn_retrieval_leak_check(text,text) to service_role;

commit;
