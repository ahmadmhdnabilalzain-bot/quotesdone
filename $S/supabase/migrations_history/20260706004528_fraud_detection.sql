-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260706004528   name: fraud_detection
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- #11 Fraud detection: flags table + a multi-signal scan
create table if not exists fraud_flags (
  kind text not null,
  subject_type text not null,
  subject_id text not null,
  severity text not null default 'medium',   -- high | medium | low
  detail jsonb default '{}'::jsonb,
  status text not null default 'open',        -- open | reviewed | dismissed | confirmed
  created_at timestamptz default now(),
  updated_at timestamptz default now(),
  primary key (kind, subject_type, subject_id)
);
alter table fraud_flags enable row level security;
revoke all on fraud_flags from anon, authenticated;

create or replace function fn_fraud_scan() returns jsonb language plpgsql as $$
declare before_ct int; after_ct int;
begin
  select count(*) into before_ct from fraud_flags;

  -- Abnormal pricing vs category benchmark (uses fn_price_confidence bands)
  insert into fraud_flags(kind,severity,subject_type,subject_id,detail,updated_at)
  select 'abnormal_price',
         case when (x.pc->>'band')='suspiciously_low' then 'high' else 'medium' end,
         'quote', q.id::text,
         jsonb_build_object('band',x.pc->>'band','amount',q.quote_amount,'category',i.category,'median',x.pc->>'median'), now()
  from quotes q join inquiries i on i.id=q.inquiry_id
  cross join lateral (select fn_price_confidence(i.category, q.quote_amount) as pc) x
  where (x.pc->>'band') in ('suspiciously_low','suspiciously_high')
  on conflict (kind,subject_type,subject_id) do update set detail=excluded.detail, severity=excluded.severity, updated_at=now();

  -- Duplicate registered-supplier phones
  insert into fraud_flags(kind,severity,subject_type,subject_id,detail,updated_at)
  select 'dup_supplier_phone','medium','phone', phone,
         jsonb_build_object('supplier_ids', array_agg(id), 'count', count(*)), now()
  from leads where claimed = true and coalesce(phone,'') <> '' group by phone having count(*) > 1
  on conflict (kind,subject_type,subject_id) do update set detail=excluded.detail, updated_at=now();

  -- Duplicate customer phones
  insert into fraud_flags(kind,severity,subject_type,subject_id,detail,updated_at)
  select 'dup_customer_phone','medium','cphone', phone,
         jsonb_build_object('customer_ids', array_agg(id), 'count', count(*)), now()
  from customers where coalesce(phone,'') <> '' group by phone having count(*) > 1
  on conflict (kind,subject_type,subject_id) do update set detail=excluded.detail, updated_at=now();

  -- Identical bid amounts on the same RFQ from different suppliers (possible collusion/copy)
  insert into fraud_flags(kind,severity,subject_type,subject_id,detail,updated_at)
  select 'identical_bids','high','inquiry', inquiry_id::text,
         jsonb_build_object('amount', quote_amount, 'suppliers', array_agg(distinct supplier_id)), now()
  from quotes where quote_amount > 0
  group by inquiry_id, quote_amount having count(distinct supplier_id) > 1
  on conflict (kind,subject_type,subject_id) do update set detail=excluded.detail, updated_at=now();

  -- Copied quotations: same committed_hash across different suppliers
  insert into fraud_flags(kind,severity,subject_type,subject_id,detail,updated_at)
  select 'copied_quote','high','hash', committed_hash,
         jsonb_build_object('quote_ids', array_agg(id), 'suppliers', array_agg(distinct supplier_id)), now()
  from quotes where coalesce(committed_hash,'') <> ''
  group by committed_hash having count(distinct supplier_id) > 1
  on conflict (kind,subject_type,subject_id) do update set detail=excluded.detail, updated_at=now();

  select count(*) into after_ct from fraud_flags;
  return jsonb_build_object('total_flags', after_ct, 'new_flags', after_ct - before_ct);
end $$;

select fn_fraud_scan() as scan;
