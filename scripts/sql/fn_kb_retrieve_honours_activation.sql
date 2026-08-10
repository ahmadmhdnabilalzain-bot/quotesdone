-- fn_kb_retrieve now HONOURS route activation.
--
-- WHY. fn_kb_route_activation_blocked(catalog_num) decides whether one of the 86 operational
-- routes may be used: it requires a settled regulatory coverage status, a mapped subcategory and
-- an Arabic alias. It had ZERO callers. So "activation" was a number on a scorecard and nothing
-- in production could act on it — a route whose regulatory review was withdrawn would have gone
-- on answering customers exactly as before.
--
-- The gate belongs on retrieval, because retrieval is what activation grants. fn_kb_retrieve is
-- called by fn_agent_context, which is on the path of every AI call in the company.
--
-- All 86 routes are unblocked today, so this changes no result on any live route. Proved in an
-- aborted transaction by blocking one route and watching its knowledge disappear while its
-- neighbour's stayed — see the session record.
create or replace function public.fn_kb_retrieve(
  p_catalog_num integer, p_query text, p_limit integer default 6, p_modules text[] default null::text[])
returns table(record_id text, title text, content text, module text, record_type text,
              authority text, validation_status text, confidence numeric, source_ids jsonb,
              escalate boolean, rank real)
language sql
stable
as $function$
with gate as (
  select coalesce((public.fn_kb_route_activation_blocked(p_catalog_num)->>'blocked')::boolean, true) as blocked
), scope as (
  select m.package_slug, m.subcategory_slug from public.kb_operational_route_map m, gate
  where m.catalog_num = p_catalog_num and not gate.blocked
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
$function$;
