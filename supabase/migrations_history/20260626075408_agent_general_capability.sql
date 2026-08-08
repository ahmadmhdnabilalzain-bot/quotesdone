-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260626075408   name: agent_general_capability
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

create table if not exists templates (
  name text primary key,
  content text,
  description text,
  updated_at timestamptz default now(),
  updated_by text
);
create table if not exists undo_log (
  id uuid primary key default gen_random_uuid(),
  table_name text,
  row_id text,
  op text,
  before jsonb,
  actor text,
  reverted boolean default false,
  created_at timestamptz default now()
);
create index if not exists undo_log_created_idx on undo_log(created_at desc);
insert into templates(name, content, description) values
  ('weekly_finance_report', 'Sections: KPI row (Revenue, Costs, Net, Monthly burn); CFO commentary; Monthly costs by category table; This week operationally table.', 'Layout for the recurring weekly CFO finance report'),
  ('email_supplier', 'Friendly professional tone, QuotesDone branding, clear call to action, signature from the QuotesDone team.', 'Default style for supplier emails'),
  ('email_customer', 'Friendly professional tone, QuotesDone branding, clear next step, signature from the QuotesDone team.', 'Default style for customer emails')
on conflict (name) do nothing;
select name, description from templates order by name;
