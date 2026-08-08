-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260708101035   name: erp_po_ap_views
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- Open POs with outstanding receipt/billing
create or replace view public.po_open as
select o.id, o.po_no, v.name as vendor, o.status, o.order_date, o.expected_date, o.subtotal,
       coalesce(sum(l.qty*l.unit_price),0)                              as ordered_value,
       coalesce(sum(l.qty_received*l.unit_price),0)                     as received_value,
       coalesce(sum((l.qty-l.qty_received)*l.unit_price),0)             as outstanding_value
from public.po_orders o
join public.po_vendors v on v.id=o.vendor_id
left join public.po_lines l on l.po_id=o.id
where o.status in ('draft','approved','partial','received')
group by o.id, o.po_no, v.name, o.status, o.order_date, o.expected_date, o.subtotal;

-- Open AP bills (unpaid balance)
create or replace view public.ap_open_bills as
select b.id, b.bill_no, v.name as vendor, b.bill_date, b.due_date,
       b.total, b.amount_paid, (b.total-b.amount_paid) as balance_due, b.status,
       (current_date - b.due_date) as days_overdue
from public.ap_bills b
join public.po_vendors v on v.id=b.vendor_id
where b.status in ('open','partial')
order by b.due_date nulls last;

-- AP aging buckets
create or replace view public.ap_aging as
select v.name as vendor,
  sum(case when current_date <= coalesce(b.due_date,b.bill_date) then b.total-b.amount_paid else 0 end) as current_due,
  sum(case when current_date - coalesce(b.due_date,b.bill_date) between 1 and 30  then b.total-b.amount_paid else 0 end) as d1_30,
  sum(case when current_date - coalesce(b.due_date,b.bill_date) between 31 and 60 then b.total-b.amount_paid else 0 end) as d31_60,
  sum(case when current_date - coalesce(b.due_date,b.bill_date) between 61 and 90 then b.total-b.amount_paid else 0 end) as d61_90,
  sum(case when current_date - coalesce(b.due_date,b.bill_date) > 90 then b.total-b.amount_paid else 0 end) as d90_plus,
  sum(b.total-b.amount_paid) as total_due
from public.ap_bills b
join public.po_vendors v on v.id=b.vendor_id
where b.status in ('open','partial')
group by v.name;

