-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260710214630   name: graph_regulations_supersedes_risk
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- 1) Explicit supersedes link between regulations (curator-populated).
alter table public.regulations
  add column if not exists supersedes_id bigint references public.regulations(id);

-- 2) Extend the knowledge graph: regulation nodes + regulation->category + supersedes edges.
create or replace function public.fn_graph_rebuild()
 returns jsonb
 language plpgsql
 set search_path to 'public','pg_temp'
as $function$
declare n_nodes int; n_edges int;
begin
  insert into graph_nodes(kind,ref_id,label,props,updated_at)
    select 'category', category, category, '{}'::jsonb, now() from inquiries where category is not null
    on conflict (kind,ref_id) do update set updated_at=now();
  insert into graph_nodes(kind,ref_id,label,props,updated_at)
    select 'rfq', id::text, coalesce(summary,category), jsonb_build_object('status',status,'stage',pipeline_stage,'emirate',emirate,'budget',budget), now() from inquiries
    on conflict (kind,ref_id) do update set label=excluded.label, props=excluded.props, updated_at=now();
  insert into graph_nodes(kind,ref_id,label,props,updated_at)
    select 'customer', c.id::text, coalesce(c.full_name,c.email), '{}'::jsonb, now()
    from customers c where c.id in (select distinct customer_id from inquiries where customer_id is not null)
    on conflict (kind,ref_id) do update set updated_at=now();
  insert into graph_nodes(kind,ref_id,label,props,updated_at)
    select 'supplier', l.id::text, l.company_name, jsonb_build_object('emirate',l.emirate), now()
    from leads l where l.id in (
      select supplier_id from inquiry_matches where supplier_id is not null
      union select supplier_id from quotes where supplier_id is not null
      union select hired_supplier_id from inquiries where hired_supplier_id is not null)
    on conflict (kind,ref_id) do update set label=excluded.label, updated_at=now();
  -- NEW: regulation nodes
  insert into graph_nodes(kind,ref_id,label,props,updated_at)
    select 'regulation', id::text, coalesce(title, doc_ref, 'regulation '||id),
           jsonb_build_object('authority',authority,'status',status,'version',version,'effective_date',effective_date,'doc_ref',doc_ref), now()
    from regulations
    on conflict (kind,ref_id) do update set label=excluded.label, props=excluded.props, updated_at=now();
  -- NEW: ensure category nodes referenced by regulations exist
  insert into graph_nodes(kind,ref_id,label,props,updated_at)
    select distinct 'category', c, c, '{}'::jsonb, now()
    from regulations r, unnest(r.categories) c where c is not null and c<>''
    on conflict (kind,ref_id) do update set updated_at=now();

  insert into graph_edges(src_kind,src_ref,rel,dst_kind,dst_ref,props,updated_at)
    select 'customer', customer_id::text, 'created', 'rfq', id::text, '{}'::jsonb, now() from inquiries where customer_id is not null
    on conflict do nothing;
  insert into graph_edges(src_kind,src_ref,rel,dst_kind,dst_ref,props,updated_at)
    select 'rfq', id::text, 'in_category', 'category', category, '{}'::jsonb, now() from inquiries where category is not null
    on conflict do nothing;
  insert into graph_edges(src_kind,src_ref,rel,dst_kind,dst_ref,props,updated_at)
    select 'rfq', inquiry_id::text, 'invited', 'supplier', supplier_id::text, '{}'::jsonb, now() from inquiry_matches where supplier_id is not null
    on conflict do nothing;
  insert into graph_edges(src_kind,src_ref,rel,dst_kind,dst_ref,props,updated_at)
    select 'supplier', supplier_id::text, 'quoted', 'rfq', inquiry_id::text, jsonb_build_object('amount',quote_amount), now() from quotes where supplier_id is not null
    on conflict (src_kind,src_ref,rel,dst_kind,dst_ref) do update set props=excluded.props, updated_at=now();
  insert into graph_edges(src_kind,src_ref,rel,dst_kind,dst_ref,props,updated_at)
    select 'rfq', id::text, 'hired', 'supplier', hired_supplier_id::text, '{}'::jsonb, now() from inquiries where hired_supplier_id is not null
    on conflict do nothing;
  insert into graph_edges(src_kind,src_ref,rel,dst_kind,dst_ref,props,updated_at)
    select 'customer', customer_id::text, 'reviewed', 'supplier', supplier_id::text, jsonb_build_object('rating',rating), now() from reviews where supplier_id is not null and customer_id is not null
    on conflict (src_kind,src_ref,rel,dst_kind,dst_ref) do update set props=excluded.props, updated_at=now();
  -- NEW: regulation applies_to category
  insert into graph_edges(src_kind,src_ref,rel,dst_kind,dst_ref,props,updated_at)
    select distinct 'regulation', r.id::text, 'applies_to', 'category', c, '{}'::jsonb, now()
    from regulations r, unnest(r.categories) c where c is not null and c<>''
    on conflict do nothing;
  -- NEW: regulation supersedes regulation (explicit)
  insert into graph_edges(src_kind,src_ref,rel,dst_kind,dst_ref,props,updated_at)
    select 'regulation', id::text, 'supersedes', 'regulation', supersedes_id::text, '{}'::jsonb, now()
    from regulations where supersedes_id is not null
    on conflict do nothing;

  select count(*) into n_nodes from graph_nodes;
  select count(*) into n_edges from graph_edges;
  return jsonb_build_object('nodes',n_nodes,'edges',n_edges);
end $function$;

-- 3) Per-article knowledge risk tier.
create or replace view public.v_kb_risk as
select id, category, source_kind, left(title,80) as title, effective_date,
  case when source_kind='regulation' then 'high'
       when source_kind in ('material','trade') then 'medium'
       else 'low' end as risk_tier,
  case when source_kind='regulation' then 'compliance/legal'
       when source_kind in ('material','trade') then 'technical/spec'
       else 'general' end as risk_reason
from public.kb_chunks;
revoke all on public.v_kb_risk from anon, authenticated;

select public.fn_graph_rebuild() as graph;
