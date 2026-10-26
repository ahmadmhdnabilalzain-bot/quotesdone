-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260708100931   name: erp_po_procure_to_pay
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- ============================================================
-- ERP: Purchase Orders / Procure-to-Pay (posts to GL)
-- ============================================================

-- 1) Supporting GL accounts (idempotent)
insert into public.gl_accounts (code,name,type,subtype,normal_balance,parent_code,is_active) values
 ('1150','VAT Recoverable (Input)','asset','tax','D',null,true),
 ('2250','GRNI (Goods Received Not Invoiced)','liability','accrual','C',null,true)
on conflict (code) do nothing;

-- 2) Vendors (AP suppliers we purchase from)
create table if not exists public.po_vendors (
  id bigint generated always as identity primary key,
  name text not null,
  email text, phone text, trn text,
  currency text not null default 'AED',
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

-- 3) Purchase order header
create table if not exists public.po_orders (
  id bigint generated always as identity primary key,
  po_no text unique,
  vendor_id bigint not null references public.po_vendors(id),
  order_date date not null default current_date,
  expected_date date,
  currency text not null default 'AED',
  status text not null default 'draft'
    check (status in ('draft','approved','partial','received','billed','closed','cancelled')),
  memo text,
  subtotal numeric(18,2) not null default 0,
  created_by text,
  approved_by text,
  approved_at timestamptz,
  created_at timestamptz not null default now()
);

-- 4) Purchase order lines
create table if not exists public.po_lines (
  id bigint generated always as identity primary key,
  po_id bigint not null references public.po_orders(id) on delete cascade,
  line_no int not null,
  description text not null,
  account_code text not null references public.gl_accounts(code),
  item_id bigint,                      -- links to inv_items (added by inventory module)
  qty numeric(18,4) not null check (qty > 0),
  unit_price numeric(18,4) not null default 0,
  qty_received numeric(18,4) not null default 0,
  qty_billed numeric(18,4) not null default 0,
  unique (po_id, line_no)
);
create index if not exists idx_po_lines_po on public.po_lines(po_id);

-- 5) Vendor bills (AP)
create table if not exists public.ap_bills (
  id bigint generated always as identity primary key,
  bill_no text,
  vendor_id bigint not null references public.po_vendors(id),
  po_id bigint references public.po_orders(id),
  bill_date date not null default current_date,
  due_date date,
  currency text not null default 'AED',
  subtotal numeric(18,2) not null default 0,
  vat_amount numeric(18,2) not null default 0,
  total numeric(18,2) not null default 0,
  amount_paid numeric(18,2) not null default 0,
  status text not null default 'open' check (status in ('open','partial','paid','void')),
  gl_journal_id bigint references public.gl_journal(id),
  pay_journal_id bigint references public.gl_journal(id),
  created_by text,
  created_at timestamptz not null default now()
);
create index if not exists idx_ap_bills_vendor on public.ap_bills(vendor_id);
create index if not exists idx_ap_bills_status on public.ap_bills(status);

