-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260706003605   name: knowledge_graph
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- #13 Knowledge graph: nodes + edges over customer -> rfq -> supplier -> quote -> outcome -> review
create table if not exists graph_nodes (
  kind text not null,           -- customer|supplier|rfq|quote|review|category
  ref_id text not null,
  label text,
  props jsonb default '{}'::jsonb,
  updated_at timestamptz default now(),
  primary key (kind, ref_id)
);
create table if not exists graph_edges (
  src_kind text not null, src_ref text not null,
  rel text not null,            -- created|in_category|invited|quoted|hired|reviewed
  dst_kind text not null, dst_ref text not null,
  props jsonb default '{}'::jsonb,
  updated_at timestamptz default now(),
  primary key (src_kind, src_ref, rel, dst_kind, dst_ref)
);
create index if not exists graph_edges_dst on graph_edges(dst_kind, dst_ref, rel);
create index if not exists graph_edges_rel on graph_edges(rel);
alter table graph_nodes enable row level security;
alter table graph_edges enable row level security;
revoke all on graph_nodes from anon, authenticated;
revoke all on graph_edges from anon, authenticated;

-- Idempotent rebuild from active data (bounded by inquiries/quotes/reviews, not the full lead table).
create or replace function fn_graph_rebuild() returns jsonb language plpgsql as $$
declare n_nodes int; n_edges int;
begin
  -- nodes: categories
  insert into graph_nodes(kind,ref_id,label,props,updated_at)
    select 'category', category, category, '{}'::jsonb, now() from inquiries where category is not null
    on conflict (kind,ref_id) do update set updated_at=now();
  -- nodes: rfqs
  insert into graph_nodes(kind,ref_id,label,props,updated_at)
    select 'rfq', id::text, coalesce(summary,category), jsonb_build_object('status',status,'stage',pipeline_stage,'emirate',emirate,'budget',budget), now() from inquiries
    on conflict (kind,ref_id) do update set label=excluded.label, props=excluded.props, updated_at=now();
  -- nodes: customers referenced by inquiries
  insert into graph_nodes(kind,ref_id,label,props,updated_at)
    select 'customer', c.id::text, coalesce(c.full_name,c.email), '{}'::jsonb, now()
    from customers c where c.id in (select distinct customer_id from inquiries where customer_id is not null)
    on conflict (kind,ref_id) do update set updated_at=now();
  -- nodes: suppliers referenced by matches/quotes/hires
  insert into graph_nodes(kind,ref_id,label,props,updated_at)
    select 'supplier', l.id::text, l.company_name, jsonb_build_object('emirate',l.emirate), now()
    from leads l where l.id in (
      select supplier_id from inquiry_matches where supplier_id is not null
      union select supplier_id from quotes where supplier_id is not null
      union select hired_supplier_id from inquiries where hired_supplier_id is not null)
    on conflict (kind,ref_id) do update set label=excluded.label, updated_at=now();
  -- edges
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
  select count(*) into n_nodes from graph_nodes;
  select count(*) into n_edges from graph_edges;
  return jsonb_build_object('nodes',n_nodes,'edges',n_edges);
end $$;

select fn_graph_rebuild() as result;
