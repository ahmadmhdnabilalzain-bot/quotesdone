-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260727002021   name: company_economics_and_resource_management
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- ============ 6. COMPANY ECONOMICS ============
create table if not exists public.company_economics (
  id           bigserial primary key,
  topic        text not null unique,
  statement    text not null,
  formula      text,
  current_value text,
  source_ref   text,
  every_employee_must_know boolean not null default true,
  updated_at   timestamptz not null default now()
);

insert into public.company_economics (topic, statement, formula, current_value, source_ref) values
('Revenue model',
 'QuotesDone earns in two ways. (1) A reveal fee charged to the buyer when they choose to unlock a supplier''s identity on an anonymous quote. (2) An annual supplier registration fee. Nothing else is charged: no commission on the works, no listing fee, no pay-per-lead.',
 'revenue = reveal_fees + supplier_registration_fees',
 'reveal rate 3% of quote value; supplier registration AED 1,000/year',
 'pricing_config'),
('Reveal fee',
 'The reveal fee is a percentage of the quoted amount, charged once, to the buyer. It is the only transaction revenue. If a supplier never responds after reveal, the fee is refundable inside the refund window - so a reveal that does not lead to contact is not revenue, it is a liability.',
 'reveal_fee = quote_amount * standard_reveal_rate (capped at standard_reveal_cap)',
 '3.0%, cap effectively none, refund window 3 working days',
 'pricing_config, transactions.reveal_fee'),
('Supplier registration',
 'Suppliers pay an annual registration fee to quote. The first 1,000 suppliers are exempt - that exemption is a deliberate liquidity subsidy, not a discount, and it expires as a cohort.',
 'supplier_revenue = paying_suppliers * supplier_reg_fee',
 'AED 1,000/year, first 1,000 suppliers free',
 'pricing_config.supplier_free_count'),
('The liquidity constraint',
 'This is a two-sided marketplace. Buyer demand is worthless without supplier supply in the same category and emirate, and supply is worthless without demand. The binding constraint is always the thinner side of a specific category, never the platform total. A healthy total with three dead categories is three dead categories.',
 'liquidity(category) = min(active_buyers, responsive_suppliers)',
 'see v_marketplace_liquidity',
 'v_marketplace_liquidity'),
('Contribution margin per reveal',
 'Gross reveal fee less payment processing, less the AI cost of producing the RFQ, matching, quote extraction and anonymisation for that inquiry, less refund provision. AI cost is a real variable cost per transaction, not overhead - which is why model routing is an economic decision, not a technical one.',
 'contribution = reveal_fee - psp_fee - ai_cost_per_inquiry - refund_provision',
 'AI cost tracked in ai_cost_log; psp ~2.9% + AED 1',
 'ai_cost_log, model_policy'),
('Cost of acquiring a supplier',
 'Suppliers are acquired by outreach, not advertising: scrape, enrich, invite, chase, verify licence, approve. The cost is mostly AI and messaging, and the failure mode is spend on suppliers who never quote. Cost per VERIFIED, RESPONSIVE supplier is the only version of this number worth tracking.',
 'CAC_supplier = outreach_cost / suppliers_verified_and_responsive',
 'currently unmeasurable: 0 verified suppliers',
 'leads.verified, supplier_score'),
('Cost of acquiring a buyer',
 'Buyers arrive through marketing and word of mouth. A buyer only becomes revenue when they post an inquiry that receives quotes AND they reveal one. Every step in between is leakage that must be measured separately - traffic without inquiries and inquiries without quotes are different failures with different fixes.',
 'CAC_buyer = marketing_spend / buyers_who_revealed_once',
 'currently unmeasurable: marketing_golive is false',
 'budget_lines, transactions'),
('Buyer lifetime value',
 'A buyer who procures repeatedly is worth many multiples of a one-off. Repeat rate, not first reveal, is what makes the model work, because the acquisition cost is paid once and the reveal fee is earned many times.',
 'LTV_buyer = avg_reveal_fee * reveals_per_buyer_per_year * expected_years',
 'unmeasurable until reveals exist',
 'transactions'),
('Break-even',
 'Fixed monthly cost is infrastructure, AI baseline and tooling. Break-even is the number of reveals per month at average contribution that covers it. It is a small number, and that is the point: this business does not need scale to be viable, it needs liquidity in a handful of categories.',
 'breakeven_reveals = fixed_monthly_cost / contribution_per_reveal',
 'department_budget total AED 7,700/month declared',
 'department_budget'),
('What destroys the economics',
 'Four things, in order: (1) reveals that refund because suppliers do not respond, (2) AI spend on tasks that deterministic code could do, (3) buying supply in categories with no demand, (4) unverified suppliers reaching buyers, which costs trust and trust is the whole product.',
 null,
 null,
 'model_policy, risk_register')
on conflict (topic) do update set statement=excluded.statement, formula=excluded.formula,
  current_value=excluded.current_value, source_ref=excluded.source_ref, updated_at=now();

create or replace view public.v_unit_economics as
with p as (select standard_reveal_rate::numeric as rate, supplier_reg_fee::numeric as reg_fee from pricing_config limit 1),
t as (
  select count(*) filter (where revealed_at is not null)                                as reveals_total,
         count(*) filter (where revealed_at > now() - interval '30 days')               as reveals_30d,
         coalesce(sum(reveal_fee) filter (where revealed_at is not null),0)             as reveal_revenue_total,
         coalesce(sum(reveal_fee) filter (where revealed_at > now() - interval '30 days'),0) as reveal_revenue_30d,
         coalesce(avg(reveal_fee) filter (where revealed_at is not null),0)             as avg_reveal_fee,
         count(*) filter (where refund_status is not null and refund_status <> 'none')  as refunds
  from transactions
),
s as (
  select count(*) filter (where verified) as verified_suppliers,
         count(*)                          as leads_total,
         count(*) filter (where registration_paid_at is not null) as paying_suppliers
  from leads
),
i as (
  select count(*) as inquiries_total,
         count(*) filter (where created_at > now() - interval '30 days') as inquiries_30d
  from inquiries
),
c as (select coalesce(sum(cost_aed),0) as ai_cost_30d from ai_cost_log where occurred_at > now() - interval '30 days'),
b as (select coalesce(sum(monthly_aed),0) as fixed_monthly_aed from department_budget)
select p.rate as reveal_rate, p.reg_fee as supplier_reg_fee_aed,
       t.reveals_total, t.reveals_30d, t.reveal_revenue_total, t.reveal_revenue_30d,
       round(t.avg_reveal_fee,2) as avg_reveal_fee_aed, t.refunds,
       s.leads_total, s.verified_suppliers, s.paying_suppliers,
       i.inquiries_total, i.inquiries_30d,
       c.ai_cost_30d, b.fixed_monthly_aed,
       case when t.reveals_30d > 0 then round(c.ai_cost_30d / t.reveals_30d, 2) end as ai_cost_per_reveal_aed,
       case when t.avg_reveal_fee > 0 then ceil(b.fixed_monthly_aed / t.avg_reveal_fee) end as breakeven_reveals_per_month,
       case when t.reveals_total = 0 then 'PRE-REVENUE: no reveal has ever been paid' else 'LIVE' end as state
from p, t, s, i, c, b;

-- ============ 7. RESOURCE MANAGEMENT ============
create table if not exists public.resource_pool (
  id            bigserial primary key,
  resource      text not null unique,
  kind          text not null check (kind in ('budget','capacity','rate_limit','quota','headcount','storage')),
  owner_dept    text,
  unit          text not null,
  capacity      numeric not null,
  committed     numeric not null default 0,
  window_label  text,
  degrade_at_pct integer not null default 80,
  halt_at_pct    integer not null default 100,
  source_ref    text,
  note          text,
  updated_at    timestamptz not null default now()
);

insert into public.resource_pool (resource, kind, owner_dept, unit, capacity, committed, window_label, degrade_at_pct, halt_at_pct, source_ref, note) values
('AI token budget - company',   'budget','exec','AED', 7700, 0, 'monthly', 80, 100, 'department_budget', 'Sum of the 10 department budgets. Degrade to cheaper models at 80%, halt non-critical LLM calls at 100%.'),
('Supplier invites',            'rate_limit','supplier_success','invites/day', 10, 0, 'daily', 80, 100, 'invite_daily_cap', 'At 10/day the 2,000 verified supplier target takes about 2.7 years. This is the single biggest throughput constraint in the company.'),
('Outbound email',              'rate_limit','marketing','emails/day', 2000, 0, 'daily', 80, 100, 'Resend plan', 'Shared across invites, nudges, notifications and marketing. Transactional wins on contention.'),
('WhatsApp / SMS',              'rate_limit','supplier_success','messages/day', 1000, 0, 'daily', 80, 100, 'Twilio', 'Cost per message is real; use only where email has already failed.'),
('Edge function invocations',   'quota','it','invocations/month', 2000000, 0, 'monthly', 80, 95, 'Supabase plan', 'pg_cron schedules are the main consumer. Polling loops are the main waste.'),
('Database storage',            'storage','it','GB', 8, 0, 'rolling', 80, 95, 'Supabase plan', 'agent_knowledge and embeddings dominate growth.'),
('Document storage',            'storage','it','GB', 100, 0, 'rolling', 80, 95, 'Supabase Storage + Dropbox', 'Drawings, BOQs, licences, signed terms.'),
('Employee attention',          'capacity','exec','open tasks', 550, 0, 'rolling', 80, 100, 'org_agents.max_open_tasks', '55 employees x 10 open tasks. Beyond this the queue is theatre, not work.'),
('Scraping / enrichment',       'quota','supplier_success','records/month', 20000, 0, 'monthly', 80, 100, 'Apify', 'Feeds the lead pipeline. Useless while invites are capped at 10/day.'),
('Payment processing',          'rate_limit','finance','transactions/day', 500, 0, 'daily', 90, 100, 'Stripe', 'Not currently a constraint - there are no live reveals.')
on conflict (resource) do update set capacity=excluded.capacity, note=excluded.note, updated_at=now();

create or replace view public.v_resource_pressure as
select r.resource, r.kind, r.owner_dept, r.unit, r.capacity, r.committed,
       case when r.capacity > 0 then round(100.0 * r.committed / r.capacity, 1) else null end as used_pct,
       case
         when r.capacity = 0 then 'UNSET'
         when 100.0 * r.committed / r.capacity >= r.halt_at_pct then 'HALT'
         when 100.0 * r.committed / r.capacity >= r.degrade_at_pct then 'DEGRADE'
         else 'OK'
       end as state,
       r.note
from public.resource_pool r;

alter table public.company_economics enable row level security;
alter table public.resource_pool enable row level security;
