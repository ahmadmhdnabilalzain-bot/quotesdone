-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260726232912   name: innovation_and_intelligence
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- Item 10: Innovation pipeline. Idea -> evaluation -> business case -> ROI -> approval -> implement -> measure.
create table if not exists public.idea (
  id            bigserial primary key,
  submitted_by  text not null,
  dept_key      text,
  title         text not null,
  problem       text not null,
  proposal      text not null,
  category      text,          -- new_service | workflow | ai_improvement | cost_reduction | customer_feature | revenue
  serves_goal   text references public.company_goals(key),
  effort        text,          -- small | medium | large
  expected_value_aed numeric,
  confidence    numeric,
  score         numeric,       -- computed at evaluation
  stage         text not null default 'submitted', -- submitted|evaluated|business_case|approved|implementing|measuring|done|rejected
  decided_by    text,
  outcome       text,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);
alter table public.idea enable row level security;

-- Item 6: Supplier intelligence. Reliability scoring from observed behaviour, not opinion.
create table if not exists public.supplier_score (
  lead_id        bigint primary key,
  response_rate  numeric,
  avg_response_hours numeric,
  quotes_submitted int not null default 0,
  quotes_won     int not null default 0,
  rejection_count int not null default 0,
  price_index    numeric,      -- 1.0 = market median
  quality_rating numeric,
  reliability    numeric,      -- composite
  last_active    timestamptz,
  computed_at    timestamptz not null default now()
);
alter table public.supplier_score enable row level security;

-- Item 5: Customer intelligence.
create table if not exists public.customer_score (
  customer_id    bigint primary key,
  rfqs_posted    int not null default 0,
  rfqs_awarded   int not null default 0,
  avg_budget_aed numeric,
  preferred_categories text[],
  lifetime_value_aed numeric,
  churn_risk     numeric,
  last_active    timestamptz,
  computed_at    timestamptz not null default now()
);
alter table public.customer_score enable row level security;

-- Item 20: marketplace health beyond revenue. Liquidity is the metric that predicts viability.
create or replace view public.v_marketplace_liquidity as
select c.slug as category, c.name,
       cov.coverage,
       cov.supplier_supply as suppliers_in_pipeline,
       (select count(*) from leads l
          join lead_trade_map t on l.invite_trades && array[t.trade_key]
         where t.catalog_slug = c.slug and l.verified) as suppliers_verified,
       (select count(*) from inquiries i where i.category = c.slug) as inquiries,
       case
         when (select count(*) from leads l join lead_trade_map t on l.invite_trades && array[t.trade_key]
                where t.catalog_slug=c.slug and l.verified) >= 5 then 'liquid'
         when cov.supplier_supply >= 50 then 'supply_available_unverified'
         when cov.supplier_supply > 0 then 'thin_supply'
         else 'no_supply' end as liquidity_status
from catalog_supplier_categories c
join v_category_coverage cov on cov.catalog_slug = c.slug;

comment on table public.idea is 'Innovation pipeline: any employee submits, evaluation scores, business case justifies, outcome is measured.';
comment on view public.v_marketplace_liquidity is 'Marketplace liquidity per category - the metric that predicts whether the model works at all.';
