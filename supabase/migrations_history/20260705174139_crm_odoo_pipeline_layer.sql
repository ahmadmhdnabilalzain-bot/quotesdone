-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260705174139   name: crm_odoo_pipeline_layer
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- Structured pipeline stages (Odoo-style: ordered, weighted, won/lost)
create table if not exists crm_stages (
  key text primary key,
  label text not null,
  sort_order int not null default 0,
  probability int not null default 0 check (probability between 0 and 100),
  is_won boolean not null default false,
  is_lost boolean not null default false,
  active boolean not null default true
);

insert into crm_stages (key,label,sort_order,probability,is_won,is_lost) values
  ('new','New',10,10,false,false),
  ('qualifying','Qualifying',20,25,false,false),
  ('matched','Matched',30,40,false,false),
  ('quoted','Quoted',40,60,false,false),
  ('revealed','Revealed',50,80,false,false),
  ('won','Won',60,100,true,false),
  ('lost','Lost',70,0,false,true),
  ('cancelled','Cancelled',80,0,false,true)
on conflict (key) do update set
  label=excluded.label, sort_order=excluded.sort_order, probability=excluded.probability,
  is_won=excluded.is_won, is_lost=excluded.is_lost;

-- Lost reasons
create table if not exists crm_lost_reasons (
  id bigint generated always as identity primary key,
  label text not null unique,
  sort_order int not null default 0,
  active boolean not null default true
);
insert into crm_lost_reasons (label,sort_order) values
  ('Price too high',10),('Chose a competitor',20),('No budget / on hold',30),
  ('Timing not right',40),('No supplier response',50),('Not qualified / out of scope',60),
  ('Duplicate / spam',70),('Other',99)
on conflict (label) do nothing;

-- Deal economics on inquiries (additive, nullable)
alter table inquiries add column if not exists expected_value numeric;
alter table inquiries add column if not exists lost_reason text;

-- Pipeline report: per-stage counts + weighted value
create or replace view crm_pipeline_report as
select s.key, s.label, s.sort_order, s.probability, s.is_won, s.is_lost,
  count(i.id)::int as deals,
  round(coalesce(sum(i.expected_value),0),2) as value,
  round(coalesce(sum(i.expected_value * s.probability / 100.0),0),2) as weighted
from crm_stages s
left join inquiries i on i.pipeline_stage = s.key
where s.active
group by s.key, s.label, s.sort_order, s.probability, s.is_won, s.is_lost
order by s.sort_order;

-- KPIs: open/won/lost, avg cycle, weighted forecast, overdue activities
create or replace view crm_deal_kpis as
select
  (select count(*) from inquiries i join crm_stages s on s.key=i.pipeline_stage where not s.is_won and not s.is_lost)::int as open_deals,
  (select count(*) from inquiries i join crm_stages s on s.key=i.pipeline_stage where s.is_won)::int as won_deals,
  (select count(*) from inquiries i join crm_stages s on s.key=i.pipeline_stage where s.is_lost)::int as lost_deals,
  (select round(avg(extract(epoch from (coalesce(completed_at, now()) - created_at))/86400.0)::numeric,1)
     from inquiries i join crm_stages s on s.key=i.pipeline_stage where s.is_won) as avg_cycle_days,
  (select round(coalesce(sum(i.expected_value * s.probability/100.0),0),2)
     from inquiries i join crm_stages s on s.key=i.pipeline_stage where not s.is_won and not s.is_lost) as weighted_forecast,
  (select count(*) from crm_activities where done=false and due_at is not null and due_at < now())::int as overdue_activities;
