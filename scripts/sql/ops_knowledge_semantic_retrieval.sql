-- REASONING LAYER — semantic retrieval over the agents' OWN operating knowledge (ops_knowledge).
--
-- The founder's requirement: agents must reason from MEANING (linked knowledge), not keyword
-- cross-matching. Half of that was already true — the deep reference corpus (kb_chunks) is retrieved
-- by hybrid semantic+keyword through kb_search. The other half was not: the agent's own operating
-- knowledge (ops_knowledge: authority, policy, decision playbooks, failure modes, department library)
-- was retrieved ONLY by tsquery (fn_ops_knowledge_search / fn_context_slice), which is exactly the
-- keyword matching the founder rejects. ops_knowledge had no embedding column at all.
--
-- This migration gives ops_knowledge the same free in-region gte-small vector the rest of the corpus
-- uses, a cosine HNSW index, a semantic retriever scoped EXACTLY as fn_agent_context_v3 scopes an
-- agent (resolve -> department scope -> packaged role ids -> company/external), and a backfill cron in
-- the identical style to the existing kb_embed crons. agent_brain then embeds the task once (free) and
-- injects the semantically-retrieved operating knowledge as a runtime context layer.
--
--   node scripts/apply_sql.mjs scripts/sql/ops_knowledge_semantic_retrieval.sql --apply --ddl

begin;

-- 1. The embedding column — same shape as kb_chunks.embedding_gte (gte-small, 384-dim).
alter table public.ops_knowledge add column if not exists embedding_gte vector(384);

commit;

-- 2. HNSW cosine index. CONCURRENTLY is not usable inside a txn and the table is tiny (8.5k rows), so
-- a plain build is fine; IF NOT EXISTS keeps the migration idempotent.
create index if not exists ops_knowledge_emb_hnsw
  on public.ops_knowledge using hnsw (embedding_gte vector_cosine_ops);

-- 2b. BACKFILL PICKER INDEX. The embedder repeatedly asks "give me the next rows with no embedding
-- yet". Without an index that predicate is a sequential scan, and under the rapid UPDATE churn of the
-- backfill (each update leaves a dead tuple until autovacuum catches up) that scan slows past the edge
-- role's short statement_timeout, stalling the backfill. A partial index over exactly the unembedded
-- rows makes "next unembedded" O(log n) and shrinks to nothing as the backfill completes.
create index if not exists ops_knowledge_unembedded
  on public.ops_knowledge (record_id) where embedding_gte is null;

begin;

-- 3. THE SEMANTIC RETRIEVER. Cosine nearest-neighbours over ops_knowledge, visible to the agent under
-- the SAME predicate fn_agent_context_v3 uses for its narrative slices (fn_context_slice + the rules
-- block): company/external knowledge is universal; department knowledge is scoped through the merge-
-- aware fn_dept_scope; role knowledge is matched on the agent's packaged role ids. runtime_eligible +
-- supersession_state='current' mirror what the agent is allowed to see. p_query_embedding is computed
-- for free by the caller (gte-small in the edge runtime); Postgres only does the cosine search.
create or replace function public.fn_ops_knowledge_match(
  p_query_embedding vector(384),
  p_agent_key       text,
  p_match_count     integer default 8
)
returns table(record_id text, title text, content text, layer text, record_type text,
              authority_tier text, dept_key text, role_key text, similarity real)
language plpgsql stable security definer set search_path to 'public', 'pg_temp'
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
       and (
             o.scope_type in ('company','external_source')
          or (o.scope_type = 'department' and o.dept_key = any(v_scope))
          or (o.role_key = any(coalesce(v_role_ids, '{}')))
       )
     order by o.embedding_gte <=> p_query_embedding
     limit greatest(1, least(coalesce(p_match_count, 8), 20));
end
$function$;

-- SECURITY DEFINER + a fresh CREATE grants EXECUTE to PUBLIC; revoke it (the runtime calls this as
-- service_role / an internal credential, never anon).
revoke execute on function public.fn_ops_knowledge_match(vector, text, integer) from public;

commit;

-- 4. BACKFILL CRON — identical style to the existing kb_embed crons (net.http_post to the edge, driven
-- by the free gte-small there). Drains ops_knowledge oldest-first in small batches; throughput comes
-- from frequency, not batch size (the gte-small session grows its allocation per run, so the batch
-- ceiling stays low). Self-maintaining: any newly-authored operating knowledge is embedded within a
-- minute of landing. Unschedule-then-schedule keeps it idempotent.
select cron.unschedule(jobid) from cron.job where jobname = 'kb_embed_ops_knowledge';
select cron.schedule('kb_embed_ops_knowledge', '* * * * *', $cron$
  select net.http_post(
    url := 'https://' || (select value from public.app_secrets where key = 'project_ref') || '.supabase.co/functions/v1/kb_embed',
    headers := '{"Content-Type":"application/json"}'::jsonb,
    body := jsonb_build_object('__secret', (select value from app_secrets where key = 'cred_cron_knowledge'),
                               'target', 'ops_knowledge',
                               'limit', 8))
  from generate_series(1, 6);
$cron$);
