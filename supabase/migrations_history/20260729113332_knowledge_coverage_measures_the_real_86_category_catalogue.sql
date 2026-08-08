-- WHY. The Knowledge coverage screen reported "95%, 53 of 56 service categories covered" and the
-- founder correctly asked why the number was smaller than the category list he supplied.
--
-- Two independent defects, both in fn_ws_knowledge:
--
-- 1. WRONG LIST. Coverage was measured against category_specs (56 rows: hvac, tiling, roofing,
--    fitout - an early short-slug trade list). The business actually runs on
--    catalog_supplier_categories (86 rows, numbered 1-86: hvac-suppliers, roofing-suppliers,
--    steel-and-reinforcement-suppliers). The two tables share ZERO slugs - verified: 0 of 56
--    category_specs slugs appear in the catalogue. So the screen was reporting near-perfect
--    coverage of a taxonomy the company does not trade on, and the 86 real categories were not
--    measured anywhere.
--
-- 2. HALF THE KNOWLEDGE WAS INVISIBLE. kb_chunks carries two conventions for the same thing:
--    'cat:<slug>' (1,495 chunks, written by the agent_knowledge -> kb_chunks sync) and bare
--    '<slug>' (2,818 chunks). The function matched the bare form only, so every prefixed chunk
--    was uncounted. kb_chunks already has a category_norm column that strips the prefix and it
--    was not used.
--
-- Together these made real knowledge look missing. Counting the prefix-stripped form against the
-- real catalogue: 84 of the 86 categories already hold 3+ chunks. Only 2 are genuinely empty.
--
-- The fix puts the definition of "coverage" in ONE view so the screen, the KPIs and anything added
-- later cannot drift apart again.

create or replace view public.v_kb_coverage as
select c.slug          as category,
       c.name          as label,
       c.num           as num,
       count(k.id)     as chunks,
       case when count(k.id) = 0 then 'gap'
            when count(k.id) < 3 then 'thin'
            else 'covered' end as status
from public.catalog_supplier_categories c
left join public.kb_chunks k
       on regexp_replace(coalesce(k.category,''), '^cat:', '') = c.slug
group by c.slug, c.name, c.num;

comment on view public.v_kb_coverage is
 'Single definition of knowledge coverage: the 86-row catalog_supplier_categories catalogue joined to kb_chunks with the cat: prefix stripped. Both conventions (cat:<slug> and bare <slug>) count. Replaces two divergent inline queries in fn_ws_knowledge.';

revoke all on public.v_kb_coverage from public, anon;
grant select on public.v_kb_coverage to service_role, authenticated;

create or replace function public.fn_ws_knowledge()
 returns jsonb
 language sql
 stable security definer
 set search_path to 'public', 'pg_catalog'
as $function$
  select jsonb_build_object(
    'kpis', jsonb_build_object(
      'chunks',(select count(*) from kb_chunks),
      'document_chunks',(select count(*) from kb_chunks where source_kind='document'),
      'categories',(select count(distinct category) from kb_chunks),
      'category_specs',(select count(*) from catalog_supplier_categories)
    ),
    'curator', jsonb_build_object(
      'health', (select (kpis->>'health')::numeric from knowledge_kpi_snapshots order by snapshot_date desc limit 1),
      'coverage_pct', k.coverage_pct, 'knowledge_coverage_pct', k.knowledge_coverage_pct, 'playbook_coverage_pct', k.playbook_coverage_pct,
      'accuracy_pct', k.accuracy_pct, 'freshness_pct', k.freshness_pct, 'usage_reach_pct', k.usage_reach_pct,
      'regulations', k.regulations, 'regulations_pending', k.regulations_pending, 'standards', k.standards, 'manufacturers', k.manufacturers, 'brands', k.brands, 'materials', k.materials, 'playbooks', k.playbooks,
      'open_items', (select count(*) from agent_actions where agent='knowledge_curator' and status in ('pending','needs_review')),
      'tasks', coalesce((select jsonb_agg(jsonb_build_object('title',title,'risk',risk,'reco',recommendation))
          from agent_actions where agent='knowledge_curator' and status in ('pending','needs_review')),'[]'::jsonb)
    ),
    'reg_library', jsonb_build_object(
      'coverage', (select to_jsonb(rc) from reg_coverage rc),
      'indexed', coalesce((select jsonb_agg(jsonb_build_object('authority',authority,'code',code_name,'domain',domain) order by authority) from reg_catalog where status='indexed'),'[]'::jsonb),
      'missing', coalesce((select jsonb_agg(jsonb_build_object('authority',authority,'code',code_name,'domain',domain,'priority',priority,'status',status) order by priority, authority) from reg_catalog where copyright='free' and status<>'indexed'),'[]'::jsonb),
      'reference_only', coalesce((select jsonb_agg(jsonb_build_object('authority',authority,'code',code_name) order by authority) from reg_catalog where copyright='copyrighted'),'[]'::jsonb)
    ),
    'regulations', coalesce((select jsonb_agg(jsonb_build_object('title',title,'status',authority||coalesce(' · '||status,''),'source_url',source_url) order by coalesce(effective_date, created_at) desc)
        from (select * from regulations order by coalesce(effective_date, created_at) desc limit 20) rg),'[]'::jsonb),
    'categories', coalesce((select jsonb_agg(jsonb_build_object('key',cat,'count',c) order by c desc) from (
        select coalesce(nullif(regexp_replace(coalesce(category,''),'^cat:',''),''),'general') cat, count(*) c from kb_chunks group by 1 order by 2 desc limit 16) kk),'[]'::jsonb),
    'coverage', coalesce((select jsonb_agg(jsonb_build_object('category',v.category,'label',v.label,'chunks',v.chunks,'status',v.status) order by v.chunks asc, v.num)
        from v_kb_coverage v),'[]'::jsonb),
    'coverage_kpis', jsonb_build_object(
        'gaps',(select count(*) from v_kb_coverage where status='gap'),
        'thin',(select count(*) from v_kb_coverage where status='thin'),
        'covered',(select count(*) from v_kb_coverage where status='covered'),
        'total',(select count(*) from v_kb_coverage)
    ),
    'recent', coalesce((select jsonb_agg(jsonb_build_object('id',id,'title',title,'category',category,'citation',citation)) from (select * from kb_chunks order by created_at desc limit 20) c),'[]'::jsonb)
  )
  from knowledge_kpis k;
$function$;