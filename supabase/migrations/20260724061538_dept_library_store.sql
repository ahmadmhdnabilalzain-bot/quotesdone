-- Generic queryable knowledge store for every department (two-layer pattern, generalized from marketing_library).
-- The 4 UAE libraries (IT/CS→it, Finance→finance, Engineering→procurement, general/law→legal) were chunked
-- (1420 chunks) and loaded as DATA via the REST API; source zips are in knowledge/. Distilled always-on rows
-- (47) were loaded into agent_knowledge (agent_key it/cfo/legal + _global trade rows). This file is the schema.
create table if not exists public.dept_library (
  id bigserial primary key, department text not null, category text, domain text,
  title text not null, content text not null, tags text, source_file text,
  tsv tsvector generated always as (to_tsvector('english', coalesce(title,'')||' '||coalesce(tags,'')||' '||coalesce(content,''))) stored,
  created_at timestamptz default now()
);
create index if not exists idx_dept_library_tsv on public.dept_library using gin(tsv);
create index if not exists idx_dept_library_dept on public.dept_library(department);
alter table public.dept_library enable row level security;
create or replace function public.fn_dept_library_search(p_dept text, p_query text, p_limit int default 5)
returns table(id bigint, department text, title text, content text, rank real)
language plpgsql stable security definer set search_path to 'public','pg_temp' as $$
declare q_or tsquery; words text[];
begin
  words := array(select w from unnest(regexp_split_to_array(lower(regexp_replace(coalesce(p_query,''),'[^a-z0-9 ]',' ','g')),'\s+')) w where length(w)>2);
  if array_length(words,1) is null then return; end if;
  begin q_or := to_tsquery('english', array_to_string(words,' | ')); exception when others then return; end;
  return query select l.id,l.department,l.title,l.content, ts_rank(l.tsv,q_or) as rank from dept_library l
    where (p_dept is null or l.department=p_dept) and l.tsv @@ q_or order by ts_rank(l.tsv,q_or) desc, l.id
    limit greatest(1, least(coalesce(p_limit,5),20));
end $$;
