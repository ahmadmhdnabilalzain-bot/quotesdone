-- LAYER 2c SCOPES LIKE THE PLAYBOOK BINDER (6 Sep 2026). Knowledge audit company_wide.md action #7.
--
-- MEASURED: fn_ops_knowledge_search(dept, query, n) - the keyword retrieval behind "# LAYER 2c - HOW
-- THIS COMPANY OPERATES" in every query-aware context - filtered `o.dept_key = p_dept` EXACTLY. The
-- organisation merged 23 departments into 10 (org_departments.merged_into), and every other scope
-- predicate in the estate (fn_ops_knowledge_match, fn_apply_playbook, fn_agent_context_v3) reads that
-- merge through fn_dept_scope(dept). This one did not, so a people_ops employee's 2c could never see
-- the 271 rows filed under `hr`, a legal employee never saw the 134 `trust_safety` rows, and Supply
-- could not reach the 97 `marketplace_expert` senior-operator records (dept_key marketplace, module
-- marketplace_expert). Rows reachable per department before -> after (company/external/unowned-
-- workflow rows included in both): customer_experience 572 -> 975, data_intel 587 -> 1,148, exec
-- 772 -> 1,048, finance 994 -> 1,134, growth 574 -> 1,119, legal 851 -> 985, marketplace 582 ->
-- 1,542, people_ops 485 -> 1,169, product_eng 561 -> 1,658, supply 485 -> 1,126.
--
-- THE FIX. fn_ops_knowledge_search uses fn_dept_scope. The one alias that is not a department merge
-- - a knowledge MODULE shared by two departments - is recorded in dept_knowledge_alias with its reason,
-- read by fn_dept_module_scope(dept), and honoured by both retrieval paths (keyword here, cosine in
-- fn_ops_knowledge_match). hr -> people_ops and trust_safety -> legal need no row: they are
-- org_departments.merged_into, which fn_dept_scope already reads; the table also accepts alias_kind =
-- 'dept' so a future cross-department read that is NOT a merge can be declared without editing a
-- routine. fn_dept_scope now reads those too.
--
--   node scripts/apply_sql.mjs scripts/sql/layer_2c_scopes_like_the_playbook_binder.sql --apply --ddl

begin;

create table if not exists public.dept_knowledge_alias (
  dept_key   text not null references public.org_departments(dept_key),
  alias_kind text not null check (alias_kind in ('dept','module')),
  alias_key  text not null,
  reason     text not null,
  created_at timestamptz not null default now(),
  primary key (dept_key, alias_kind, alias_key)
);
comment on table public.dept_knowledge_alias is
  'Knowledge-scope aliases that are NOT a department merge (those live in org_departments.merged_into). alias_kind dept: the department also reads ops_knowledge rows filed under alias_key as a dept_key; module: it also reads rows whose ops_knowledge.module = alias_key. Read by fn_dept_scope / fn_dept_module_scope.';
alter table public.dept_knowledge_alias enable row level security;
revoke all on public.dept_knowledge_alias from public, anon, authenticated;
grant select on public.dept_knowledge_alias to service_role;

insert into public.dept_knowledge_alias (dept_key, alias_kind, alias_key, reason) values
  ('supply', 'module', 'marketplace_expert',
   'The 97 marketplace_expert senior-operator records are filed under dept_key marketplace; Supply (supplier acquisition, verification, coverage) works the same supplier network and was measured unable to reach any of them - knowledge audit 6 Sep 2026.'),
  ('marketplace', 'module', 'marketplace_expert',
   'Own module, declared so the alias reads the same for both departments that share it.')
on conflict (dept_key, alias_kind, alias_key) do update set reason = excluded.reason;

CREATE OR REPLACE FUNCTION public.fn_dept_scope(p_dept text)
 RETURNS text[]
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  select array(select p_dept
               union
               select d.dept_key from public.org_departments d where d.merged_into = p_dept
               union
               select a.alias_key from public.dept_knowledge_alias a where a.dept_key = p_dept and a.alias_kind = 'dept');
$function$;

create or replace function public.fn_dept_module_scope(p_dept text)
 returns text[]
 language sql
 stable
 set search_path to 'public'
as $function$
  select coalesce(array(select a.alias_key from public.dept_knowledge_alias a
                         where a.dept_key = p_dept and a.alias_kind = 'module'), '{}'::text[]);
$function$;

CREATE OR REPLACE FUNCTION public.fn_ops_knowledge_search(p_dept text, p_query text, p_limit integer DEFAULT 5)
 RETURNS TABLE(record_id text, title text, content text, record_type text, authority_tier text, implementation_status text, rank real)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare q_or tsquery; words text[]; v_scope text[]; v_modules text[];
begin
  words := array(select w from unnest(regexp_split_to_array(lower(regexp_replace(coalesce(p_query,''),'[^a-z0-9 ]',' ','g')),'\s+')) w where length(w)>2);
  if array_length(words,1) is null then return; end if;
  begin q_or := to_tsquery('english', array_to_string(words,' | ')); exception when others then return; end;
  -- THE SAME SCOPE THE PLAYBOOK BINDER USES. fn_dept_scope reads org_departments.merged_into plus the
  -- declared dept aliases; fn_dept_module_scope the declared module aliases. `dept_key = p_dept` alone
  -- hid every merged-in package from keyword retrieval (people_ops never saw hr; supply never saw
  -- marketplace_expert) while the cosine path and fn_apply_playbook could see them.
  v_scope   := public.fn_dept_scope(p_dept);
  v_modules := public.fn_dept_module_scope(p_dept);
  return query
    select o.record_id, o.title, o.content, o.record_type, o.authority_tier,
           o.implementation_status, ts_rank(o.tsv, q_or) as rank
      from ops_knowledge o
     where (p_dept is null
            or o.dept_key = any(v_scope)
            or o.module = any(v_modules)
            -- company principles and the UAE source registry apply to every department, and a
            -- cross-department workflow that names no single owner belongs to all of them by
            -- definition. Without these three branches 884 of 3,959 records were reachable by
            -- nothing at all — the same defect as the corpus itself, one level down.
            or o.scope_type in ('company','external_source')
            or (o.scope_type = 'workflow' and o.dept_key is null))
       and o.tsv @@ q_or
     order by ts_rank(o.tsv, q_or) desc, o.record_id
     limit greatest(1, least(coalesce(p_limit,5),20));
end $function$;

-- Load pgvector's shared library into THIS backend before the CREATE below is validated: the SET
-- clauses name hnsw.* GUCs, which exist only once vector.so has run its init; a backend that has not
-- touched a vector value refuses them with "permission denied to set parameter" (measured on the first
-- apply of this file, exactly as fn_ops_knowledge_match_returns_k_rows_for_a_scoped_agent.sql records).
select '[0]'::vector;

CREATE OR REPLACE FUNCTION public.fn_ops_knowledge_match(p_query_embedding vector, p_agent_key text, p_match_count integer DEFAULT 8, p_record_types text[] DEFAULT NULL::text[])
 RETURNS TABLE(record_id text, title text, content text, layer text, record_type text, authority_tier text, dept_key text, role_key text, similarity real)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
 SET "hnsw.iterative_scan" TO 'relaxed_order'
 SET "hnsw.ef_search" TO '200'
AS $function$
declare
  v_key      text;
  v_dept     text;
  v_scope    text[];
  v_modules  text[];
  v_role_ids text[];
begin
  if p_query_embedding is null then return; end if;
  -- resolve exactly as v3 does, so an alias or packaged role resolves to the same identity
  v_key := coalesce(public.fn_org_agent_resolve(p_agent_key), p_agent_key);
  select a.department into v_dept from public.org_agents a where a.agent_key = v_key;
  if v_dept is null then return; end if;
  v_scope   := public.fn_dept_scope(v_dept);
  v_modules := public.fn_dept_module_scope(v_dept);
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
          or (o.scope_type = 'department' and o.module = any(v_modules))
          or (o.role_key = any(coalesce(v_role_ids, '{}')))
       )
     order by o.embedding_gte <=> p_query_embedding
     limit greatest(1, least(coalesce(p_match_count, 8), 20));
end
$function$;

-- PROOF, in-file and read-only: the scope widened where the audit measured it closed.
do $proof$
declare n_hr int; n_ts int; n_mx int;
begin
  select count(*) into n_hr from public.ops_knowledge o where o.dept_key = any(public.fn_dept_scope('people_ops')) and o.dept_key = 'hr';
  select count(*) into n_ts from public.ops_knowledge o where o.dept_key = any(public.fn_dept_scope('legal')) and o.dept_key = 'trust_safety';
  select count(*) into n_mx from public.ops_knowledge o where o.module = any(public.fn_dept_module_scope('supply')) and o.module = 'marketplace_expert';
  if n_hr = 0 or n_ts = 0 or n_mx = 0 then
    raise exception 'scope did not widen: hr via people_ops %, trust_safety via legal %, marketplace_expert via supply %', n_hr, n_ts, n_mx;
  end if;
end $proof$;

commit;
