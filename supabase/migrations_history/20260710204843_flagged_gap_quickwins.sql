-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260710204843   name: flagged_gap_quickwins
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- 1) Same-owner / duplicate-entity conflict-of-interest detector.
create or replace view public.v_supplier_coi as
with sup as (
  select id, company_name,
         nullif(regexp_replace(coalesce(phone,''),    '\D','','g'),'') as ph,
         nullif(regexp_replace(coalesce(whatsapp,''), '\D','','g'),'') as wa,
         lower(nullif(email,''))              as em,
         nullif(trn,'')                       as trn,
         nullif(trade_license_no,'')          as lic
  from public.leads where claimed = true
),
ids as (
  select id, company_name, 'phone'::text k, ph v from sup where ph  is not null and length(ph) >= 7
  union all select id, company_name, 'whatsapp', wa from sup where wa is not null and length(wa) >= 7
  union all select id, company_name, 'email',    em from sup where em is not null
  union all select id, company_name, 'trn',      trn from sup where trn is not null
  union all select id, company_name, 'license',  lic from sup where lic is not null
)
select k as shared_field, v as shared_value,
       count(distinct id)          as supplier_count,
       array_agg(distinct id)      as supplier_ids,
       array_agg(distinct company_name) as companies
from ids
group by k, v
having count(distinct id) > 1
order by count(distinct id) desc, k;
revoke all on public.v_supplier_coi from anon, authenticated;

-- 2) Customer lifetime value (revenue to date from paid reveal fees + engagement).
create or replace view public.v_customer_ltv as
select c.id as customer_id, c.full_name, c.email,
  (select count(*) from public.inquiries i where i.customer_id=c.id) as inquiries,
  (select count(*) from public.inquiries i where i.customer_id=c.id and (i.completed_at is not null or i.outcome='won')) as completed,
  (select count(*) from public.transactions t where t.customer_id=c.id and t.fee_status='paid') as paid_reveals,
  coalesce((select sum(reveal_fee) from public.transactions t where t.customer_id=c.id and t.fee_status='paid'),0)::numeric(12,2) as revenue_to_date_aed,
  greatest((select max(created_at) from public.inquiries i where i.customer_id=c.id),
           (select max(revealed_at) from public.transactions t where t.customer_id=c.id)) as last_activity,
  case
    when coalesce((select sum(reveal_fee) from public.transactions t where t.customer_id=c.id and t.fee_status='paid'),0) >= 2000 then 'high'
    when coalesce((select sum(reveal_fee) from public.transactions t where t.customer_id=c.id and t.fee_status='paid'),0) >= 500 then 'medium'
    when coalesce((select sum(reveal_fee) from public.transactions t where t.customer_id=c.id and t.fee_status='paid'),0) > 0 then 'low'
    else 'none' end as value_tier
from public.customers c
order by revenue_to_date_aed desc;
revoke all on public.v_customer_ltv from anon, authenticated;

-- 3) Supplier load / capacity (active matched RFQs vs responsiveness).
create or replace view public.v_supplier_load as
select l.id as supplier_id, l.company_name,
  count(distinct im.inquiry_id) filter (where i.completed_at is null and coalesce(i.status,'') <> 'cancelled') as active_matched,
  count(distinct im.inquiry_id) as total_matched,
  sh.response as response_rate, sh.risk_tier,
  ( count(distinct im.inquiry_id) filter (where i.completed_at is null and coalesce(i.status,'') <> 'cancelled') >= 10
    and coalesce(sh.response, 100) < 50 ) as overloaded
from public.leads l
join public.inquiry_matches im on im.supplier_id = l.id
left join public.inquiries i on i.id = im.inquiry_id
left join public.supplier_health sh on sh.supplier_id = l.id
where l.claimed = true
group by l.id, l.company_name, sh.response, sh.risk_tier
order by active_matched desc;
revoke all on public.v_supplier_load from anon, authenticated;

-- 4) Per-table data-owner registry (governance).
create table if not exists public.data_owner_registry (
  table_name     text primary key,
  owner          text not null default 'Founder',
  steward_agent  text,
  classification text,
  notes          text,
  updated_at     timestamptz not null default now()
);
alter table public.data_owner_registry enable row level security;
insert into public.data_owner_registry(table_name, steward_agent, classification, notes) values
 ('customers','Customer Success','PII','Buyer accounts; PDPL-sensitive'),
 ('leads','Supplier Success','PII/operational','Supplier directory + registrants'),
 ('inquiries','RFQ / Procurement','operational','Buyer RFQs'),
 ('quotes','RFQ / Procurement','operational','Supplier quotes'),
 ('transactions','Finance AI','financial','Reveal fees, refunds'),
 ('supplier_dues','Finance AI','financial','Non-response fines'),
 ('company_faq','Knowledge Curator','knowledge','Canonical answers (single source of truth)'),
 ('agent_knowledge','Knowledge Curator','knowledge','Compiled agent knowledge'),
 ('kb_chunks','Knowledge Curator','knowledge','Ingested authority docs'),
 ('security_events','Security AI','security','Security signals'),
 ('security_audit_log','Security AI','security','Append-only governance audit trail'),
 ('app_secrets','Founder','secret','Service-role only')
on conflict (table_name) do nothing;
-- audit changes to the registry too
drop trigger if exists trg_audit_data_owner on public.data_owner_registry;
create trigger trg_audit_data_owner after insert or update or delete on public.data_owner_registry
  for each row execute function public.fn_security_audit();

-- 5) AI quality / hallucination proxy: agent override rate + latest eval scores.
create or replace view public.v_ai_quality_proxy as
select agent,
  count(*) filter (where decided_at is not null) as decided_30d,
  count(*) filter (where lower(coalesce(status,'')) in ('rejected','dismissed','declined','overridden')) as rejected_30d,
  round(case when count(*) filter (where decided_at is not null) > 0
    then count(*) filter (where lower(coalesce(status,'')) in ('rejected','dismissed','declined','overridden'))::numeric
       / count(*) filter (where decided_at is not null) * 100 else null end, 1) as override_pct
from public.agent_actions
where created_at > now() - interval '30 days'
group by agent
order by override_pct desc nulls last;
revoke all on public.v_ai_quality_proxy from anon, authenticated;

create or replace view public.v_eval_latest as
select prompt_key, score, cases_total, created_at
from (select *, row_number() over (partition by prompt_key order by created_at desc) rn
      from public.prompt_eval_runs) x
where rn = 1
order by score asc nulls first;
revoke all on public.v_eval_latest from anon, authenticated;
