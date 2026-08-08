-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260726224820   name: ai_cost_governor
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- MODEL POLICY: task class -> tier. Configurable, not hard-coded in prompts.
create table if not exists public.model_policy (
  task_class    text primary key,
  tier          text not null,               -- small | medium | large
  model_primary text not null,
  model_fallback text,
  max_tokens    int not null default 800,
  rationale     text,
  deterministic_alternative text,            -- if set, an LLM should not be used at all
  active        boolean not null default true
);
alter table public.model_policy enable row level security;

-- DEPARTMENT BUDGETS with automatic degradation as spend approaches the cap.
create table if not exists public.department_budget (
  dept_key        text primary key,
  monthly_aed     numeric not null,
  spent_aed       numeric not null default 0,
  period_label    text not null,
  degrade_at_pct  int not null default 70,   -- prefer cheaper models beyond this
  halt_at_pct     int not null default 95,   -- only gated/critical work beyond this
  updated_at      timestamptz not null default now()
);
alter table public.department_budget enable row level security;

-- COST GOVERNOR: every AI request logged with why the model was chosen and
-- whether something cheaper would have done.
create table if not exists public.ai_cost_log (
  id             bigserial primary key,
  occurred_at    timestamptz not null default now(),
  fn             text,
  dept_key       text,
  agent_key      text,
  task_class     text,
  model_used     text not null,
  model_selected_because text,
  tier           text,
  prompt_tokens  int default 0,
  output_tokens  int default 0,
  cached         boolean not null default false,
  cache_hit_key  text,
  latency_ms     int,
  cost_aed       numeric,
  confidence     numeric,
  could_be_cheaper boolean,
  cheaper_reason text,
  ok             boolean not null default true
);
alter table public.ai_cost_log enable row level security;
create index if not exists acl_dept_idx on public.ai_cost_log(dept_key, occurred_at desc);
create index if not exists acl_cheaper_idx on public.ai_cost_log(could_be_cheaper) where could_be_cheaper;

-- CACHE: answer once, reuse. Keyed on a hash of task_class + normalised prompt.
create table if not exists public.llm_cache (
  cache_key    text primary key,
  task_class   text,
  prompt_hash  text not null,
  response     text not null,
  model_used   text,
  hits         int not null default 0,
  created_at   timestamptz not null default now(),
  last_hit_at  timestamptz,
  expires_at   timestamptz
);
alter table public.llm_cache enable row level security;

-- Model rates, so cost is computed rather than guessed. AED per 1M tokens.
create table if not exists public.model_rate (
  model     text primary key,
  tier      text not null,
  in_aed_per_mtok  numeric not null,
  out_aed_per_mtok numeric not null,
  note      text
);
alter table public.model_rate enable row level security;

comment on table public.ai_cost_log is 'AI Cost Governor: model used, why, tokens, cost, and whether a cheaper model would have sufficed.';
comment on table public.model_policy is 'Task class to model tier routing. deterministic_alternative set means no LLM should be used at all.';
