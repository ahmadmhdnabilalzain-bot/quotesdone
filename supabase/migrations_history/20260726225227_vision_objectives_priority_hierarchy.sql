-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260726225227   name: vision_objectives_priority_hierarchy
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

alter table public.company_goals add column if not exists category text;
alter table public.company_goals add column if not exists horizon  text not null default 'year_1';
alter table public.company_goals add column if not exists direction text not null default 'at_least'; -- at_least | at_most | exactly

-- 3-year vision
create table if not exists public.vision_horizon (
  year_no    int primary key,
  label      text not null,
  statement  text not null,
  active     boolean not null default true
);
alter table public.vision_horizon enable row level security;

-- Department objectives, distinct from KPI targets
create table if not exists public.department_objective (
  id         bigserial primary key,
  dept_key   text not null,
  objective  text not null,
  horizon    text not null default 'year_1',
  sort       int not null default 0,
  active     boolean not null default true,
  unique (dept_key, objective)
);
alter table public.department_objective enable row level security;

-- The objectives every employee pursues regardless of department
create table if not exists public.universal_objective (
  id        int primary key,
  objective text not null unique,
  active    boolean not null default true
);
alter table public.universal_objective enable row level security;

-- THE TIE-BREAKER: when goals conflict, this ordering decides.
create table if not exists public.priority_hierarchy (
  rank       int primary key,
  principle  text not null unique,
  meaning    text not null,
  overrides_below boolean not null default true
);
alter table public.priority_hierarchy enable row level security;

insert into vision_horizon (year_no, label, statement) values
(1,'Year 1','Become the most intelligent quotation platform in the UAE.'),
(2,'Year 2','Become the default procurement platform for SMEs in the UAE.'),
(3,'Year 3','Expand across the GCC with autonomous AI procurement.')
on conflict (year_no) do nothing;

insert into priority_hierarchy (rank, principle, meaning) values
(1,'Protect legal and regulatory compliance','No goal, deadline or revenue justifies a compliance breach. If an action risks UAE regulatory violation, stop and escalate to Legal.'),
(2,'Protect customer trust and data security','Anonymity, confidentiality and PDPL obligations outrank speed and convenience. Never reveal supplier identity before authorization.'),
(3,'Deliver high-quality outcomes','A correct, complete answer late beats a fast wrong one. Do not ship work that fails its quality standard.'),
(4,'Support sustainable revenue growth','Prefer actions that move a company goal. Revenue that damages trust or compliance is not growth.'),
(5,'Improve efficiency and reduce costs','Choose the cheapest path that still satisfies ranks 1 to 4. Deterministic code over an LLM; small model over large.'),
(6,'Continuously learn and improve','Record what worked and what did not. Feed it back into institutional memory.')
on conflict (rank) do nothing;

insert into universal_objective (id, objective) values
(1,'Improve customer satisfaction'),
(2,'Improve supplier satisfaction'),
(3,'Reduce operational costs'),
(4,'Increase automation'),
(5,'Improve response speed'),
(6,'Reduce errors'),
(7,'Increase company revenue where appropriate'),
(8,'Share lessons learned with the organization'),
(9,'Suggest process improvements'),
(10,'Continuously update and validate knowledge')
on conflict (id) do nothing;

comment on table public.priority_hierarchy is 'Decision tie-breaker. When goals conflict, lower rank wins. Rank 1 overrides everything below it.';
comment on table public.universal_objective is 'Pursued by every employee regardless of department.';
