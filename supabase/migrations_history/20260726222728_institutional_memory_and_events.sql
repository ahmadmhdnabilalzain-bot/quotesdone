-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260726222728   name: institutional_memory_and_events
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- PILLAR 3: institutional memory. The company retains what it learns even as
-- individual employees change. Scoped so the right employee gets the right recall.
create table if not exists public.institutional_memory (
  id            bigserial primary key,
  kind          text not null,      -- supplier_interaction | customer_interaction | rfq_outcome | pricing_pattern |
                                    -- negotiation_outcome | approval_decision | lesson_learned | kpi_trend | process_improvement
  subject_type  text,               -- supplier | customer | category | department | company
  subject_id    text,
  category_slug text,
  headline      text not null,
  detail        text not null,
  outcome       text,               -- success | failure | mixed | pending
  money_aed     numeric,
  learned_by    text,               -- agent_key
  confidence    numeric,
  evidence_ref  text,               -- table:id that proves this
  visible_to    text[] default '{}',-- agent_keys or department keys; empty = whole company
  occurred_at   timestamptz not null default now(),
  created_at    timestamptz not null default now()
);
alter table public.institutional_memory enable row level security;
create index if not exists im_kind_idx on public.institutional_memory(kind, occurred_at desc);
create index if not exists im_subject_idx on public.institutional_memory(subject_type, subject_id);
create index if not exists im_category_idx on public.institutional_memory(category_slug);

-- EVENT SYSTEM: everything important becomes an event; employees subscribe rather than poll.
create table if not exists public.company_event (
  id           bigserial primary key,
  event_type   text not null,       -- rfq.created | quote.received | supplier.approved | invoice.paid | campaign.published ...
  entity_type  text,
  entity_id    text,
  actor        text,
  payload      jsonb,
  occurred_at  timestamptz not null default now()
);
alter table public.company_event enable row level security;
create index if not exists ce_type_idx on public.company_event(event_type, occurred_at desc);

create table if not exists public.event_subscription (
  agent_key   text not null,
  event_type  text not null,
  reason      text,
  active      boolean not null default true,
  primary key (agent_key, event_type)
);
alter table public.event_subscription enable row level security;

-- RISK REGISTER, per department, with the fields a real register carries.
create table if not exists public.risk_register (
  id           bigserial primary key,
  dept_key     text not null,
  risk         text not null,
  category     text,               -- technical | commercial | legal | financial | operational | schedule | supplier | customer | security
  probability  text not null default 'medium',  -- low | medium | high
  impact       text not null default 'medium',
  owner_agent  text,
  mitigation   text,
  status       text not null default 'open',    -- open | mitigating | accepted | closed
  review_due   date,
  updated_at   timestamptz not null default now()
);
alter table public.risk_register enable row level security;

-- DECISION FRAMEWORK: every significant decision recorded in one structure.
create table if not exists public.decision_record (
  id               bigserial primary key,
  decided_by       text not null,
  dept_key         text,
  problem          text not null,
  context          text,
  options          jsonb,
  risks            text,
  benefits         text,
  recommendation   text not null,
  confidence       numeric,
  expected_outcome text,
  rollback_plan    text,
  serves_goal      text references public.company_goals(key),
  approved_by      text,
  status           text not null default 'proposed',  -- proposed | approved | rejected | executed | rolled_back
  actual_outcome   text,
  created_at       timestamptz not null default now()
);
alter table public.decision_record enable row level security;

-- SKILLS MATRIX: what each employee is actually good at, for routing and gap analysis.
create table if not exists public.skills_matrix (
  agent_key  text not null,
  skill      text not null,
  rating     int not null check (rating between 1 and 5),
  evidence   text,
  updated_at timestamptz not null default now(),
  primary key (agent_key, skill)
);
alter table public.skills_matrix enable row level security;

-- SCENARIO LIBRARY: the Layer 4 stress tests, as repeatable regression cases.
create table if not exists public.scenario_library (
  scenario_key text primary key,
  name         text not null,
  category     text,
  situation    text not null,
  expected_behaviour text not null,
  departments  text[],
  last_run     timestamptz,
  last_result  text,               -- pass | fail | not_run
  notes        text
);
alter table public.scenario_library enable row level security;

comment on table public.institutional_memory is 'PILLAR 3: what the company remembers, independent of any individual employee.';
comment on table public.company_event is 'Event backbone: employees subscribe to events instead of polling.';
