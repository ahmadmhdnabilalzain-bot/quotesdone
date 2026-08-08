-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260708101254   name: erp_inventory_core
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- ============================================================
-- ERP: Inventory (weighted-average costing, posts to GL)
-- ============================================================

create table if not exists public.inv_items (
  id bigint generated always as identity primary key,
  sku text unique,
  name text not null,
  uom text not null default 'unit',
  category text,
  inventory_account text not null default '1500' references public.gl_accounts(code),
  cogs_account text not null default '5000' references public.gl_accounts(code),
  reorder_point numeric(18,4) not null default 0,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists public.inv_stock_moves (
  id bigint generated always as identity primary key,
  item_id bigint not null references public.inv_items(id),
  move_date date not null default current_date,
  move_type text not null check (move_type in ('in','out','adjust')),
  qty_delta numeric(18,4) not null,        -- signed: + adds stock, - removes
  cost_delta numeric(18,2) not null,       -- signed value change
  unit_cost numeric(18,4),                 -- cost applied to this move
  ref_type text, ref_id text,
  gl_journal_id bigint references public.gl_journal(id),
  memo text, created_by text,
  created_at timestamptz not null default now()
);
create index if not exists idx_inv_moves_item on public.inv_stock_moves(item_id);

-- link PO lines to inventory items now that inv_items exists
do $$ begin
  if not exists (select 1 from pg_constraint where conname='po_lines_item_id_fkey') then
    alter table public.po_lines
      add constraint po_lines_item_id_fkey foreign key (item_id) references public.inv_items(id);
  end if;
end $$;

-- On-hand qty / value / weighted-average cost per item
create or replace view public.inv_on_hand as
select i.id, i.sku, i.name, i.uom, i.category,
       coalesce(sum(m.qty_delta),0)  as qty_on_hand,
       coalesce(sum(m.cost_delta),0) as inventory_value,
       case when coalesce(sum(m.qty_delta),0) <> 0
            then round(sum(m.cost_delta)/sum(m.qty_delta),4) else 0 end as avg_unit_cost,
       i.reorder_point,
       (coalesce(sum(m.qty_delta),0) <= i.reorder_point) as needs_reorder
from public.inv_items i
left join public.inv_stock_moves m on m.item_id=i.id
group by i.id, i.sku, i.name, i.uom, i.category, i.reorder_point;

-- Total inventory valuation (should tie to GL account 1500 balance)
create or replace view public.inv_valuation as
select coalesce(sum(cost_delta),0) as total_inventory_value,
       count(distinct item_id) filter (where true) as items_with_moves
from public.inv_stock_moves;

