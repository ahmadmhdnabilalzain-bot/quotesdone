-- Retrieval, second pass. The first version used websearch_to_tsquery, which ANDs every term: a
-- perfectly ordinary question - "liquid applied membrane warranty roof" - required all five words in
-- the same record and returned NOTHING for a category holding 3,000 relevant ones. In production
-- that reads as "the knowledge base is empty" and sends the caller straight to a premium model,
-- which is the exact cost this import exists to remove. Filtering should be permissive and RANKING
-- should discriminate: OR the terms with prefix matching, rank by ts_rank, return the top handful.
create or replace function public.fn_kb_retrieve(p_catalog_num int, p_query text,
                                                 p_limit int default 6, p_modules text[] default null)
returns table (record_id text, title text, content text, module text, record_type text,
               authority text, validation_status text, confidence numeric, source_ids jsonb,
               escalate boolean, rank real)
language sql stable as $$
with scope as (
  select m.package_slug, m.subcategory_slug from public.kb_operational_route_map m
  where m.catalog_num = p_catalog_num
), q as (
  select to_tsquery('simple',
           nullif(array_to_string(
             array(select w || ':*' from unnest(regexp_split_to_array(lower(coalesce(p_query,'')), '[^a-z0-9؀-ۿ]+')) w
                   where length(w) >= 3), ' | '), '')) tsq
)
select r.record_id, r.title, left(r.content, 4000), r.module, r.record_type, r.authority,
       r.validation_status, r.confidence, r.source_ids,
       (r.escalation_rule is not null or r.module = 'uae_regulations') as escalate,
       ts_rank(to_tsvector('simple', r.title || ' ' || left(r.content, 4000)), q.tsq) as rank
from kb_stage.records r
join scope s on s.package_slug = r.category_slug and s.subcategory_slug = r.subcategory_slug
cross join q
where r.validation_status in ('reviewed', 'source_verified', 'approved')
  and (p_modules is null or r.module = any (p_modules))
  and (q.tsq is null or to_tsvector('simple', r.title || ' ' || left(r.content, 4000)) @@ q.tsq)
order by rank desc, r.confidence desc nulls last, r.record_id
limit greatest(p_limit, 1);
$$;
